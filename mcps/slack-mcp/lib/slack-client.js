/**
 * Slack API Client
 *
 * Handles all Slack API communication with:
 * - Automatic token refresh on auth failure
 * - User name caching with LRU + TTL
 * - Rate limiting
 * - Network error retry with exponential backoff
 * - Proactive token health checking
 */

import {
  loadTokens,
  saveTokens,
  extractFromChrome,
  getLastExtractionError,
  saveAutoHealTelemetry,
} from "./token-store.js";

// ============ Configuration ============

const TOKEN_WARNING_AGE = 10 * 24 * 60 * 60 * 1000;   // 10 days
const TOKEN_CRITICAL_AGE = 13 * 24 * 60 * 60 * 1000;  // 13 days
const STUCK_THRESHOLD_MS = 24 * 60 * 60 * 1000;       // Escalate to 'stuck' after 24h of repeated auto-heal failures
const REFRESH_COOLDOWN = 60 * 60 * 1000;        // 1 hour between refresh attempts
const USER_CACHE_MAX_SIZE = 500;
const USER_CACHE_TTL = 60 * 60 * 1000;          // 1 hour

const RETRYABLE_NETWORK_ERRORS = [
  'ECONNRESET', 'ETIMEDOUT', 'ENOTFOUND', 'EAI_AGAIN',
  'ECONNREFUSED', 'EPIPE', 'UND_ERR_CONNECT_TIMEOUT'
];

// Slack API methods that require form-encoded params instead of JSON
const FORM_ENCODED_METHODS = new Set([
  "conversations.replies",
  "search.messages",
  "search.all",
  "search.files",
  "users.info",
]);

let lastRefreshAttempt = 0;

// ============ Conservative request pacing ============
// Slack's session-anomaly detection — most aggressively on Enterprise Grid —
// reacts to burst velocity, not only to the documented per-method rate limits.
// By default we space outbound request STARTS by a minimum interval and cap
// concurrent in-flight requests. Both are configurable; set the interval to 0
// to disable spacing entirely.

function readIntEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export const REQUEST_PACING = Object.freeze({
  minIntervalMs: Math.max(0, readIntEnv("SLACK_MCP_MIN_REQUEST_INTERVAL_MS", 350)),
  maxConcurrency: Math.max(1, readIntEnv("SLACK_MCP_MAX_CONCURRENCY", 3)),
});

/**
 * Build a request pacer: a scheduler that caps concurrency and spaces request
 * starts by a minimum interval. Injectable clock/sleep make it deterministically
 * testable. Returns a `schedule(fn)` that resolves with fn()'s result once a
 * slot is free and the interval has elapsed.
 */
export function createRequestPacer({
  minIntervalMs = 0,
  maxConcurrency = Infinity,
  sleepFn = sleep,
  now = () => Date.now(),
} = {}) {
  const cap = maxConcurrency > 0 ? maxConcurrency : Infinity;
  let active = 0;
  let lastStart = Number.NEGATIVE_INFINITY;
  const waiters = [];

  function acquire() {
    if (active < cap) {
      active += 1;
      return Promise.resolve();
    }
    return new Promise((resolve) => waiters.push(resolve));
  }

  function release() {
    active -= 1;
    const next = waiters.shift();
    if (next) {
      active += 1;
      next();
    }
  }

  async function schedule(fn) {
    await acquire();
    try {
      if (minIntervalMs > 0) {
        // Gate on the ACTUAL previous start, re-checking after every sleep.
        // Reserving nominal wake times instead would bunch requests whenever
        // the event loop stalls longer than the interval (synchronous PBKDF2
        // during token extraction can do exactly that): several sleeps would
        // expire together and fire at once — the burst this exists to prevent.
        // The check and the claim below sit in one synchronous block, so two
        // callers waking in the same tick cannot both pass.
        for (;;) {
          const t = now();
          const earliest = lastStart + minIntervalMs;
          if (t >= earliest) {
            lastStart = t;
            break;
          }
          await sleepFn(earliest - t);
        }
      }
      return await fn();
    } finally {
      release();
    }
  }

  schedule.stats = () => ({ active, cap, minIntervalMs, queued: waiters.length });
  return schedule;
}

// Process-wide pacer applied to every outbound Slack HTTP request.
const requestPacer = createRequestPacer(REQUEST_PACING);

// ============ LRU Cache with TTL ============

class LRUCache {
  constructor(maxSize = 500, ttlMs = 60 * 60 * 1000) {
    this.maxSize = maxSize;
    this.ttlMs = ttlMs;
    this.cache = new Map();
  }

  get(key) {
    const entry = this.cache.get(key);
    if (!entry) return null;
    if (Date.now() > entry.expiry) {
      this.cache.delete(key);
      return null;
    }
    // Move to end (most recently used)
    this.cache.delete(key);
    this.cache.set(key, entry);
    return entry.value;
  }

  set(key, value) {
    // Delete if exists (to update position)
    this.cache.delete(key);
    // Evict oldest if at capacity
    if (this.cache.size >= this.maxSize) {
      const firstKey = this.cache.keys().next().value;
      this.cache.delete(firstKey);
    }
    this.cache.set(key, {
      value,
      expiry: Date.now() + this.ttlMs
    });
  }

  has(key) {
    return this.get(key) !== null;
  }

  get size() { return this.cache.size; }

  clear() { this.cache.clear(); }

  stats() {
    return { size: this.cache.size, maxSize: this.maxSize, ttlMs: this.ttlMs };
  }
}

// User cache with LRU + TTL
const userCache = new LRUCache(USER_CACHE_MAX_SIZE, USER_CACHE_TTL);

// ============ Token Health ============

/**
 * Check token health and attempt proactive refresh if needed
 */
export async function checkTokenHealth(logger = console) {
  const silentLogger = { error: () => {}, warn: () => {}, log: () => {} };
  const creds = loadTokens(false, silentLogger, { autoExtract: false });

  if (!creds) {
    return {
      healthy: false,
      reason: 'no_tokens',
      age_known: false,
      age_state: 'missing',
      message: 'No credentials found'
    };
  }

  const updatedAtMs = creds.updatedAt ? new Date(creds.updatedAt).getTime() : Number.NaN;
  const hasKnownAge = Number.isFinite(updatedAtMs);
  const tokenAge = hasKnownAge ? Date.now() - updatedAtMs : null;
  const ageHours = hasKnownAge
    ? Math.round(tokenAge / (60 * 60 * 1000) * 10) / 10
    : null;

  // Read auto-heal telemetry (only populated when source is "file")
  let lastAutoHealAttempt = creds.lastAutoHealAttempt || null;
  let lastAutoHealError = creds.lastAutoHealError || null;
  let stuckSince = creds.stuckSince || null;

  // Attempt proactive refresh if token is getting old
  if (hasKnownAge && tokenAge > TOKEN_WARNING_AGE && Date.now() - lastRefreshAttempt > REFRESH_COOLDOWN) {
    lastRefreshAttempt = Date.now();
    const attemptAt = new Date().toISOString();
    logger.error?.(`Token is ${ageHours}h old, attempting proactive refresh...`);

    const newTokens = extractFromChrome();
    if (newTokens) {
      let persistError = null;
      try {
        saveTokens(newTokens.token, newTokens.cookie);
      } catch (e) {
        // Persistence failed (e.g. locked Keychain in keychain-only mode).
        // The fresh tokens stay available via the in-memory fallback in
        // token-store, but this is NOT a clean refresh: record the failure in
        // telemetry (so stuck-detection can trip) and report it honestly.
        persistError = e;
        logger.error?.(`Refreshed tokens could not be persisted: ${e.message}`);
      }
      const persistErrorCode = persistError ? (persistError.code || 'token_persist_failed') : null;
      saveAutoHealTelemetry({ attemptAt, error: persistErrorCode });
      if (!persistError) {
        logger.error?.('Proactively refreshed tokens from Chrome');
      }
      const persistStuckSince = persistError
        ? (lastAutoHealError === persistErrorCode ? stuckSince : attemptAt)
        : null;
      return {
        healthy: true,
        refreshed: true,
        persisted: !persistError,
        persist_error: persistErrorCode,
        age_hours: 0,
        age_known: true,
        age_state: 'fresh',
        source: 'chrome-auto',
        last_auto_heal_attempt: attemptAt,
        last_auto_heal_error: persistErrorCode,
        stuck_since: persistStuckSince,
        message: persistError
          ? `Tokens refreshed in memory, but could not be persisted: ${persistError.message}`
          : 'Tokens refreshed successfully'
      };
    } else {
      const extractionError = getLastExtractionError();
      const errorCode = extractionError?.code || 'chrome_extraction_failed';
      saveAutoHealTelemetry({ attemptAt, error: errorCode });
      lastAutoHealAttempt = attemptAt;
      if (lastAutoHealError !== errorCode) {
        stuckSince = attemptAt;
      }
      lastAutoHealError = errorCode;
      logger.error?.(`Could not refresh from Chrome: ${extractionError?.message || 'unknown error'}`);
    }
  }

  const stuckSinceMs = stuckSince ? new Date(stuckSince).getTime() : Number.NaN;
  const isStuck = Number.isFinite(stuckSinceMs)
    && (Date.now() - stuckSinceMs) > STUCK_THRESHOLD_MS
    && !!lastAutoHealError;

  return {
    healthy: !hasKnownAge || tokenAge < TOKEN_CRITICAL_AGE,
    age_hours: ageHours,
    age_known: hasKnownAge,
    age_state: isStuck
      ? 'stuck'
      : !hasKnownAge
        ? 'unknown'
        : tokenAge > TOKEN_CRITICAL_AGE
          ? 'critical'
          : tokenAge > TOKEN_WARNING_AGE
            ? 'warning'
            : 'healthy',
    warning: hasKnownAge && tokenAge > TOKEN_WARNING_AGE,
    critical: hasKnownAge && tokenAge > TOKEN_CRITICAL_AGE,
    stuck: isStuck,
    source: creds.source,
    updated_at: creds.updatedAt,
    last_auto_heal_attempt: lastAutoHealAttempt,
    last_auto_heal_error: lastAutoHealError,
    stuck_since: stuckSince,
    message: isStuck
      ? `Auto-heal has been failing since ${stuckSince} (last error: ${lastAutoHealError}). Open Chrome > View > Developer > Allow JavaScript from Apple Events, then run npm run tokens:auto.`
      : !hasKnownAge
        ? 'Token age unknown (missing timestamp) - auth can still be valid'
        : tokenAge > TOKEN_CRITICAL_AGE
          ? 'Token may expire soon - open Slack in Chrome'
          : tokenAge > TOKEN_WARNING_AGE
            ? 'Token is getting old - will auto-refresh if Slack tab is open'
            : 'Token is healthy'
  };
}

/**
 * Make an authenticated Slack API call
 * Features: auth retry, rate limit handling, network error retry
 */
export async function slackAPI(method, params = {}, options = {}) {
  const { retryOnAuthFail = true, retryCount = 0, maxRetries = 3, logger = console } = options;

  const creds = loadTokens(false, logger);
  if (!creds) {
    throw new Error("No credentials available. Run npx -y @jtalk22/slack-mcp --setup or open Slack in Chrome.");
  }

  // Proactive token health check (non-blocking, only on first attempt)
  if (retryCount === 0) {
    checkTokenHealth({ error: () => {} }).catch(() => {});
  }

  const useForm = FORM_ENCODED_METHODS.has(method);

  let response;
  try {
    const headers = {
      "Authorization": `Bearer ${creds.token}`,
      "Cookie": `d=${creds.cookie}`,
    };

    let body;
    if (useForm) {
      // URLSearchParams coerces non-primitives to "[object Object]",
      // so stringify any arrays/objects before encoding.
      const safeParams = {};
      for (const [key, value] of Object.entries(params)) {
        if (value === undefined || value === null) continue;
        safeParams[key] = (typeof value === "object")
          ? JSON.stringify(value)
          : String(value);
      }
      headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8";
      body = new URLSearchParams(safeParams).toString();
    } else {
      headers["Content-Type"] = "application/json; charset=utf-8";
      body = JSON.stringify(params);
    }

    // Route through the pacer: caps concurrency and spaces request starts so a
    // burst of tool calls doesn't read as anomalous session velocity. Retries
    // recurse back through slackAPI and are paced again.
    response = await requestPacer(() => fetch(`https://slack.com/api/${method}`, {
      method: "POST",
      headers,
      body,
    }));
  } catch (networkError) {
    // Retry on network errors with exponential backoff + jitter
    if (retryCount < maxRetries) {
      const isRetryable = RETRYABLE_NETWORK_ERRORS.some(e =>
        networkError.message?.includes(e) ||
        networkError.code === e ||
        networkError.cause?.code === e
      );
      if (isRetryable || networkError.message?.includes('fetch')) {
        const backoff = Math.min(1000 * Math.pow(2, retryCount), 10000);
        const jitter = Math.random() * 1000;
        logger.error?.(`Network error on ${method}: ${networkError.message}, retry ${retryCount + 1}/${maxRetries} in ${Math.round(backoff + jitter)}ms`);
        await sleep(backoff + jitter);
        return slackAPI(method, params, { ...options, retryCount: retryCount + 1 });
      }
    }
    throw networkError;
  }

  let data;
  try {
    data = await response.json();
  } catch (parseError) {
    throw new Error(`Slack API ${method} returned non-JSON (HTTP ${response.status}): ${parseError.message}`);
  }

  if (!data.ok) {
    // Handle rate limiting with exponential backoff
    if (data.error === "ratelimited" && retryCount < maxRetries) {
      const retryAfter = parseInt(response.headers.get("Retry-After") || "5", 10);
      const backoff = Math.min(retryAfter * 1000, 30000) * (retryCount + 1);
      const jitter = Math.random() * 1000;
      logger.error?.(`Rate limited on ${method}, waiting ${Math.round(backoff + jitter)}ms before retry ${retryCount + 1}/${maxRetries}`);
      await sleep(backoff + jitter);
      return slackAPI(method, params, { ...options, retryCount: retryCount + 1 });
    }

    // Handle auth errors with auto-retry
    if ((data.error === "invalid_auth" || data.error === "token_expired") && retryOnAuthFail) {
      logger.error?.("Token expired, attempting Chrome auto-extraction...");
      const attemptAt = new Date().toISOString();
      const chromeTokens = extractFromChrome();
      if (chromeTokens) {
        let persistError = null;
        try {
          saveTokens(chromeTokens.token, chromeTokens.cookie);
        } catch (e) {
          // The extraction still succeeded: token-store keeps the fresh
          // tokens in memory, so the retry below uses them instead of
          // re-reading the stale persisted credentials. Telemetry must
          // record the persistence failure, not a clean heal.
          persistError = e;
          logger.error?.(`Refreshed tokens could not be persisted (${e.message}) — retrying with in-memory tokens.`);
        }
        saveAutoHealTelemetry({ attemptAt, error: persistError ? (persistError.code || 'token_persist_failed') : null });
        // Retry the request
        return slackAPI(method, params, { ...options, retryOnAuthFail: false });
      }
      const extractionError = getLastExtractionError() || {
        code: 'chrome_extraction_failed',
        message: 'Auto-heal attempted but no structured error surfaced.',
        detail: null
      };
      saveAutoHealTelemetry({ attemptAt, error: extractionError.code });
      const err = new Error(
        `Slack auth failed (${data.error}) and auto-heal could not refresh tokens: ${extractionError.message}`
      );
      err.code = 'token_auth_failed';
      err.slack_error = data.error;
      err.extraction_error = extractionError;
      err.next_action = 'Open http://localhost:3000 and click Refresh, OR run `npm run tokens:auto` with Slack open in Chrome, OR check Chrome > View > Developer > Allow JavaScript from Apple Events.';
      throw err;
    }
    throw new Error(data.error || "Slack API error");
  }

  return data;
}

/**
 * Resolve user ID to real name (with LRU caching)
 */
export async function resolveUser(userId, options = {}) {
  if (!userId) return "unknown";

  const cached = userCache.get(userId);
  if (cached) return cached;

  try {
    const result = await slackAPI("users.info", { user: userId }, options);
    const name = result.user?.real_name || result.user?.name || userId;
    userCache.set(userId, name);
    return name;
  } catch (e) {
    // Cache the ID itself to avoid repeated failed lookups
    userCache.set(userId, userId);
    return userId;
  }
}

/**
 * Clear the user cache
 */
export function clearUserCache() {
  userCache.clear();
}

/**
 * Get user cache stats
 */
export function getUserCacheStats() {
  return userCache.stats();
}

/**
 * Format a Slack timestamp to ISO string
 */
export function formatTimestamp(ts) {
  const parsed = parseFloat(ts);
  if (!Number.isFinite(parsed)) return null;
  return new Date(parsed * 1000).toISOString();
}

/**
 * Convert ISO date to Slack timestamp
 */
export function toSlackTimestamp(isoDate) {
  return (new Date(isoDate).getTime() / 1000).toString();
}

/**
 * Sleep for rate limiting
 */
export function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
