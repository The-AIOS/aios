/**
 * Token Storage Module
 *
 * Multi-layer token persistence:
 * 1. Environment variables (highest priority)
 * 2. Token file (~/.slack-mcp-tokens.json)
 * 3. macOS Keychain (most secure)
 * 4. Chrome auto-extraction (fallback)
 *
 * Storage backend selection (SLACK_MCP_TOKEN_STORAGE):
 *   auto          - file + Keychain, file read first (default, original behavior)
 *   keychain-only - credentials live exclusively in the macOS Keychain;
 *                   no plaintext token file is ever written, and a legacy
 *                   file is migrated in and removed after verification (#162)
 *   file          - file only; the Keychain is never touched
 *
 * In keychain-only mode, non-secret bookkeeping (token timestamp, auto-heal
 * telemetry) moves to ~/.slack-mcp-meta.json so token-age reporting and
 * stuck-detection keep working without credentials touching disk.
 */

import { readFileSync, writeFileSync, existsSync, renameSync, unlinkSync, rmSync, chmodSync, copyFileSync, mkdtempSync, statSync, readdirSync } from "fs";
import { homedir, platform, tmpdir } from "os";
import { join } from "path";
import { execFileSync } from "child_process";
import { pbkdf2Sync, createDecipheriv } from "crypto";

/**
 * Optional workspace/profile namespace (#164): SLACK_MCP_PROFILE=work (or
 * `--profile work` on the CLI) gives every storage surface — token file,
 * metadata sidecar, write lock, Keychain service — its own namespace, so
 * multiple server instances (work + personal) run side-by-side without
 * sharing or overwriting each other's credentials. Fail-closed like the
 * storage mode: an invalid profile name dies at startup rather than silently
 * writing to the default namespace.
 */
function resolveProfile() {
  const raw = (process.env.SLACK_MCP_PROFILE || "").trim().toLowerCase();
  if (!raw) return "";
  if (!/^[a-z0-9][a-z0-9_-]{0,31}$/.test(raw)) {
    const err = new Error(
      `Invalid SLACK_MCP_PROFILE "${raw}". Use 1-32 characters: letters, digits, "-", "_" (must start alphanumeric). ` +
      "Refusing to guess for a credential-storage namespace."
    );
    err.code = "invalid_profile";
    throw err;
  }
  return raw;
}

const ACTIVE_PROFILE = resolveProfile();
const PROFILE_SUFFIX = ACTIVE_PROFILE ? `-${ACTIVE_PROFILE}` : "";

const TOKEN_FILE = join(homedir(), `.slack-mcp-tokens${PROFILE_SUFFIX}.json`);
const META_FILE = join(homedir(), `.slack-mcp-meta${PROFILE_SUFFIX}.json`);
const KEYCHAIN_SERVICE = `slack-mcp-server${PROFILE_SUFFIX}`;

// Platform detection
const IS_MACOS = platform() === 'darwin';

// Last-known-good tokens for THIS process, populated only when a save could
// not be persisted (e.g. locked Keychain in keychain-only mode). Serving them
// keeps a successful extraction usable — the auth-retry path would otherwise
// re-read the stale persisted credentials and fail again with invalid_auth.
// Cleared on the next successful save so refreshes from another process
// (LaunchAgent, CLI) are picked up again once persistence recovers.
let memoryTokens = null;

/** Test seam: clear the in-memory fallback between unit tests. */
export function _resetMemoryTokensForTests() {
  memoryTokens = null;
}

// ============ Storage Mode ============

const STORAGE_MODE_ALIASES = {
  "": "auto",
  "auto": "auto",
  "default": "auto",
  "keychain-only": "keychain-only",
  "keychain": "keychain-only",
  "file": "file",
  "file-only": "file",
};

/**
 * Resolve the storage mode with its source. Precedence:
 *   1. SLACK_MCP_TOKEN_STORAGE env var (authoritative override)
 *   2. Persisted choice from the setup wizard (~/.slack-mcp-meta.json)
 *   3. Default: auto
 *
 * Fails closed on unrecognized values from either source: a typo in a
 * security setting must never silently downgrade to writing plaintext
 * credentials.
 */
export function getStorageModeDetail() {
  const rawEnv = (process.env.SLACK_MCP_TOKEN_STORAGE || "").toLowerCase().trim();
  if (rawEnv) {
    const mode = STORAGE_MODE_ALIASES[rawEnv];
    if (!mode) {
      const err = new Error(
        `Unrecognized SLACK_MCP_TOKEN_STORAGE value "${rawEnv}". ` +
        `Valid values: auto (file + Keychain, default), keychain-only (macOS Keychain only, no plaintext file), file (token file only). ` +
        `Refusing to guess for a credential-storage setting.`
      );
      err.code = "invalid_token_storage_mode";
      throw err;
    }
    return { mode, source: "env" };
  }

  const rawPersisted = String(getMeta().storage_mode || "").toLowerCase().trim();
  if (rawPersisted) {
    const mode = STORAGE_MODE_ALIASES[rawPersisted];
    if (!mode) {
      const err = new Error(
        `Unrecognized storage_mode "${rawPersisted}" in ${META_FILE}. ` +
        `Valid values: auto, keychain-only, file. Fix or remove the entry, ` +
        `or set SLACK_MCP_TOKEN_STORAGE to override.`
      );
      err.code = "invalid_token_storage_mode";
      throw err;
    }
    return { mode, source: "persisted" };
  }

  return { mode: "auto", source: "default" };
}

export function getStorageMode() {
  return getStorageModeDetail().mode;
}

/**
 * Persist the storage mode chosen in the setup wizard, so every process
 * (MCP server, CLI, LaunchAgent) agrees on where credentials live without
 * plumbing an env var into each client config. SLACK_MCP_TOKEN_STORAGE
 * still overrides when set.
 */
export function setPersistedStorageMode(mode) {
  const normalized = STORAGE_MODE_ALIASES[String(mode || "").toLowerCase().trim()];
  if (!normalized) {
    const err = new Error(`Cannot persist unrecognized storage mode "${mode}". Valid values: auto, keychain-only, file.`);
    err.code = "invalid_token_storage_mode";
    throw err;
  }
  saveMeta({ storage_mode: normalized });
  // saveMeta is best-effort by design; a persisted security choice is not.
  if (getMeta().storage_mode !== normalized) {
    const err = new Error(`Could not persist storage mode to ${META_FILE}.`);
    err.code = "storage_mode_persist_failed";
    throw err;
  }
  return normalized;
}

// Default Chrome user-data dir on macOS
const DEFAULT_CHROME_BASE = join(homedir(), 'Library', 'Application Support', 'Google', 'Chrome');

// Slack xoxc- token regex: 3 numeric segments then a hex signature
const XOXC_TOKEN_RE = /xoxc-[0-9]+-[0-9]+-[0-9]+-[a-f0-9]{20,}/g;

// Refresh lock to prevent concurrent extraction attempts
let refreshInProgress = null;
let lastExtractionError = null;

// ============ Keychain Storage (macOS only) ============

/**
 * Default adapter shells out to /usr/bin/security. Writes use -U
 * (update-in-place) instead of delete-then-add: the old sequence had a
 * window where a failed add after a successful delete lost the entry —
 * tolerable when the token file backed it up, not when the Keychain is
 * the only store.
 */
const systemKeychainAdapter = {
  available: () => IS_MACOS,
  get(key) {
    try {
      const result = execFileSync(
        "security",
        ["find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", key, "-w"],
        { encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'] }
      );
      return result.trim();
    } catch (e) {
      return null;
    }
  },
  set(key, value) {
    try {
      execFileSync(
        "security",
        ["add-generic-password", "-U", "-s", KEYCHAIN_SERVICE, "-a", key, "-w", value],
        { stdio: 'pipe' }
      );
      return true;
    } catch (e) {
      return false;
    }
  },
};

let keychain = systemKeychainAdapter;

/**
 * Test seam: swap the Keychain adapter for an in-memory fake so the
 * keychain-only flow (verification, migration, file removal) is unit-testable
 * on any platform without touching a real Keychain. Pass null to restore.
 */
export function _setKeychainAdapterForTests(adapter) {
  keychain = adapter || systemKeychainAdapter;
}

export function isKeychainAvailable() {
  return keychain.available();
}

export function getFromKeychain(key) {
  if (!keychain.available()) return null;
  return keychain.get(key);
}

export function saveToKeychain(key, value) {
  if (!keychain.available()) return false;
  return keychain.set(key, value);
}

// ============ File Storage ============

export function getFromFile() {
  if (!existsSync(TOKEN_FILE)) return null;
  try {
    const data = JSON.parse(readFileSync(TOKEN_FILE, "utf-8"));
    return {
      token: data.SLACK_TOKEN,
      cookie: data.SLACK_COOKIE,
      updatedAt: data.updated_at || data.UPDATED_AT || null,
      lastAutoHealAttempt: data.last_auto_heal_attempt || null,
      lastAutoHealError: data.last_auto_heal_error || null,
      stuckSince: data.stuck_since || null
    };
  } catch (e) {
    return null;
  }
}

// ============ Metadata Sidecar (keychain-only mode) ============

/**
 * Non-secret bookkeeping for keychain-only mode: token timestamp plus
 * auto-heal telemetry. Contains no credentials — it exists so
 * slack_token_status age reporting and stuck-detection survive the removal
 * of the plaintext token file.
 */
function getMeta() {
  if (!existsSync(META_FILE)) return {};
  try {
    return JSON.parse(readFileSync(META_FILE, "utf-8"));
  } catch (e) {
    return {};
  }
}

function saveMeta(patch) {
  try {
    withWriteLock(() => {
      const merged = { ...getMeta(), ...patch };
      atomicWriteSync(META_FILE, JSON.stringify(merged, null, 2));
    });
  } catch (e) {
    // Best-effort: metadata must never block credential persistence.
  }
}

// ============ Cross-process write lock ============

const WRITE_LOCK_FILE = join(homedir(), `.slack-mcp-write${PROFILE_SUFFIX}.lock`);
const WRITE_LOCK_STALE_MS = 10_000;
const WRITE_LOCK_WAIT_MS = 2_000;

function sleepSync(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

/**
 * Serialize writes to the token/metadata files across processes — the MCP
 * server, the CLI, and a LaunchAgent refresh can all run concurrently, and an
 * unserialized read-modify-write on the sidecar silently drops the other
 * writer's fields. O_EXCL lock file with stale takeover.
 *
 * Availability wins over strictness: if the lock cannot be created at all
 * (read-only HOME) or the holder never frees it within the wait budget, the
 * write proceeds unlocked — exactly the pre-lock behavior.
 */
function withWriteLock(fn) {
  const deadline = Date.now() + WRITE_LOCK_WAIT_MS;
  let locked = false;
  while (!locked) {
    try {
      writeFileSync(WRITE_LOCK_FILE, String(process.pid), { flag: "wx" });
      locked = true;
    } catch (e) {
      if (e.code !== "EEXIST") break; // cannot lock here at all — proceed unlocked
      try {
        if (Date.now() - statSync(WRITE_LOCK_FILE).mtimeMs > WRITE_LOCK_STALE_MS) {
          unlinkSync(WRITE_LOCK_FILE); // dead holder — take over
          continue;
        }
      } catch {
        continue; // lock vanished between attempts — retry immediately
      }
      if (Date.now() > deadline) break; // live but slow holder — proceed unlocked
      sleepSync(15);
    }
  }
  try {
    return fn();
  } finally {
    if (locked) {
      try { unlinkSync(WRITE_LOCK_FILE); } catch {}
    }
  }
}

/**
 * Persist auto-heal telemetry.
 * Best-effort: silent on failure (tokens are more important than metadata).
 * error === null indicates a successful auto-heal; any non-null string is an
 * error code (e.g. "apple_events_javascript_disabled"). When the error code
 * changes, stuck_since is reset; when it stays the same across attempts,
 * stuck_since is preserved so downstream consumers can detect a long-running
 * stuck state.
 *
 * Destination follows the storage mode: the token file in auto/file mode
 * (unchanged), the metadata sidecar in keychain-only mode — where the token
 * file deliberately does not exist.
 */
export function saveAutoHealTelemetry({ attemptAt, error }) {
  try {
    if (getStorageMode() === "keychain-only") {
      const meta = getMeta();
      const patch = { last_auto_heal_attempt: attemptAt };
      if (error) {
        if (meta.last_auto_heal_error !== error) {
          patch.stuck_since = attemptAt;
        }
        patch.last_auto_heal_error = error;
      } else {
        patch.last_auto_heal_error = null;
        patch.stuck_since = null;
      }
      saveMeta(patch);
      return;
    }

    if (!existsSync(TOKEN_FILE)) return;
    withWriteLock(() => {
      const data = JSON.parse(readFileSync(TOKEN_FILE, "utf-8"));
      data.last_auto_heal_attempt = attemptAt;
      if (error) {
        if (data.last_auto_heal_error !== error) {
          data.stuck_since = attemptAt;
        }
        data.last_auto_heal_error = error;
      } else {
        data.last_auto_heal_error = null;
        data.stuck_since = null;
      }
      atomicWriteSync(TOKEN_FILE, JSON.stringify(data, null, 2));
    });
  } catch (e) {
    // Silent: telemetry must never break the auto-heal hot path.
  }
}

/**
 * Atomic write to prevent file corruption from concurrent writes
 */
function atomicWriteSync(filePath, content) {
  const tempPath = `${filePath}.${process.pid}.tmp`;
  try {
    writeFileSync(tempPath, content);
    if (IS_MACOS || platform() === 'linux') {
      try { chmodSync(tempPath, 0o600); } catch {}
    }
    renameSync(tempPath, filePath); // Atomic on POSIX systems
  } catch (e) {
    // Clean up temp file on error
    try { unlinkSync(tempPath); } catch {}
    throw e;
  }
}

export function saveToFile(token, cookie) {
  const data = {
    SLACK_TOKEN: token,
    SLACK_COOKIE: cookie,
    updated_at: new Date().toISOString()
  };
  // Locked so a concurrent telemetry read-modify-write can't interleave.
  withWriteLock(() => atomicWriteSync(TOKEN_FILE, JSON.stringify(data, null, 2)));
}

// ============ Chrome Extraction ============

// Multiple localStorage paths Slack might use (for robustness)
const SLACK_TOKEN_PATHS = [
  `JSON.parse(localStorage.localConfig_v2).teams[Object.keys(JSON.parse(localStorage.localConfig_v2).teams)[0]].token`,
  `JSON.parse(localStorage.localConfig_v3).teams[Object.keys(JSON.parse(localStorage.localConfig_v3).teams)[0]].token`,
  `JSON.parse(localStorage.getItem('reduxPersist:localConfig'))?.teams?.[Object.keys(JSON.parse(localStorage.getItem('reduxPersist:localConfig'))?.teams || {})[0]]?.token`,
  `window.boot_data?.api_token`,
];

// Fallback profile list used when Local State JSON can't be read
const FALLBACK_CHROME_PROFILES = ['Default', 'Profile 1', 'Profile 2', 'Profile 3', 'Profile 4', 'Profile 5'];

// ============ Chrome profile discovery ============

/**
 * Resolve the Chrome user-data directory.
 * Override with SLACK_MCP_CHROME_USER_DATA_DIR for non-standard installations
 * (e.g. a portable Chrome, a test profile, or a Chrome Canary layout).
 */
function getChromeBase() {
  return process.env.SLACK_MCP_CHROME_USER_DATA_DIR || DEFAULT_CHROME_BASE;
}

/**
 * Extraction mode config:
 *   "auto"       - LevelDB first, AppleScript fallback (default)
 *   "leveldb"    - On-disk only, never touch AppleScript (CI-safe, headless-safe)
 *   "applescript"- Legacy AppleScript-only path
 */
function getExtractionMode() {
  const mode = (process.env.SLACK_MCP_EXTRACTION_MODE || 'auto').toLowerCase();
  return ['auto', 'leveldb', 'applescript'].includes(mode) ? mode : 'auto';
}

/**
 * Enumerate all Chrome profiles present on this machine, newest cookie DB first.
 * SLACK_MCP_CHROME_PROFILE can pin a single profile (exact directory name).
 * Falls back to the legacy hardcoded list if Local State is unreadable.
 */
function enumerateChromeProfiles() {
  const envProfile = process.env.SLACK_MCP_CHROME_PROFILE;
  if (envProfile) return [envProfile];

  const base = getChromeBase();
  const localStatePath = join(base, 'Local State');

  let profiles = [];
  try {
    const localState = JSON.parse(readFileSync(localStatePath, 'utf-8'));
    profiles = Object.keys(localState.profile?.info_cache || {});
  } catch {
    profiles = [...FALLBACK_CHROME_PROFILES];
  }

  if (profiles.length === 0) profiles = [...FALLBACK_CHROME_PROFILES];

  // Rank profiles by cookie-db mtime descending so the freshest Slack session wins.
  const ranked = profiles.map(p => {
    const cookiePath = join(base, p, 'Cookies');
    let mtime = 0;
    try { mtime = statSync(cookiePath).mtimeMs; } catch {}
    return { name: p, mtime };
  });
  ranked.sort((a, b) => b.mtime - a.mtime);
  return ranked.map(x => x.name);
}

// Chrome profile directories to search (legacy helper retained for back-compat)
const CHROME_PROFILES = ['Default', 'Profile 1', 'Profile 2', 'Profile 3'];

function normalizeExtractionError(error) {
  const raw = String(error?.message || error || "");

  if (raw.includes("Executing JavaScript through AppleScript is turned off")) {
    return {
      code: "apple_events_javascript_disabled",
      message: "Chrome needs one setting enabled for token extraction.",
      detail: "In Chrome: View > Developer > Allow JavaScript from Apple Events. Cookie extraction works without this — only the token needs it."
    };
  }

  if (raw.includes("Application isn't running") || raw.includes("Google Chrome got an error")) {
    return {
      code: "chrome_not_ready",
      message: "Chrome is not running or has no windows open.",
      detail: "Open Google Chrome with a Slack tab at app.slack.com."
    };
  }

  if (raw.toLowerCase().includes("timed out")) {
    return {
      code: "chrome_extraction_timeout",
      message: "Chrome token extraction timed out.",
      detail: "Ensure Slack is open in Chrome and retry."
    };
  }

  if (raw.includes("Chrome Safe Storage")) {
    return {
      code: "keychain_access_denied",
      message: "Could not access Chrome's encryption key in Keychain.",
      detail: "You may need to allow terminal access in System Settings > Privacy > Full Disk Access."
    };
  }

  return {
    code: "chrome_extraction_failed",
    message: "Chrome token extraction failed.",
    detail: raw || "Unknown extraction error."
  };
}

// ============ Chrome Safe Storage key (#168) ============

/**
 * The Chrome Safe Storage password is per-MACHINE, not per-profile, and the
 * Keychain lookup for it can be slow (observed 4.9s against a 5s timeout) and
 * can prompt. It is therefore looked up at most once per process and cached —
 * one extraction run does one lookup total instead of one per profile per
 * path. The cache is refreshed once if a decrypt fails (Chrome re-keyed).
 */
const systemSafeStorageAdapter = {
  getKey(timeoutMs) {
    return execFileSync('security', [
      'find-generic-password', '-s', 'Chrome Safe Storage', '-w'
    ], { encoding: 'utf-8', timeout: timeoutMs }).trim();
  }
};

let safeStorageAdapter = systemSafeStorageAdapter;
let safeStorageKeyCache = null;

/** Test seam: swap the Safe Storage lookup; pass null to restore. */
export function _setSafeStorageAdapterForTests(adapter) {
  safeStorageAdapter = adapter || systemSafeStorageAdapter;
  safeStorageKeyCache = null;
}

function safeStorageTimeoutMs() {
  const raw = Number(process.env.SLACK_MCP_KEYCHAIN_TIMEOUT_MS);
  return Number.isFinite(raw) && raw > 0 ? raw : 15000;
}

function getSafeStorageKey({ forceRefresh = false } = {}) {
  if (!forceRefresh && safeStorageKeyCache) return safeStorageKeyCache.password;
  const password = safeStorageAdapter.getKey(safeStorageTimeoutMs());
  safeStorageKeyCache = { password };
  return password;
}

function isTimeoutError(e) {
  return Boolean(e?.killed) || /ETIMEDOUT|timed? ?out/i.test(String(e?.message || e));
}

/**
 * Extract the Slack `d` cookie from a specific Chrome profile's cookie DB.
 * Returns { cookie, reason }: the decrypted xoxd- string, or a machine-usable
 * failure reason — every failure path names its cause instead of collapsing
 * to null, so extraction errors can finally say WHY (#168).
 *
 * Chrome holds a WAL lock on the live DB; we copy-then-query for safety.
 */
function extractCookieForProfile(profileDir) {
  const cookiesPath = join(profileDir, 'Cookies');
  if (!existsSync(cookiesPath)) return { cookie: null, reason: 'no_cookie_db' };

  const tmpDir = mkdtempSync(join(tmpdir(), 'slack-mcp-'));
  const tmpDb = join(tmpDir, 'Cookies');
  try {
    copyFileSync(cookiesPath, tmpDb);
    // Chrome keeps recent writes in the SQLite WAL sidecar until the next
    // checkpoint — copy Cookies-wal (and -shm) too when present so the
    // snapshot isn't stale.
    for (const suffix of ['-wal', '-shm']) {
      const sidecarPath = `${cookiesPath}${suffix}`;
      if (existsSync(sidecarPath)) {
        try { copyFileSync(sidecarPath, `${tmpDb}${suffix}`); } catch {}
      }
    }

    let queryResult;
    try {
      queryResult = execFileSync('sqlite3', [
        tmpDb,
        "SELECT hex(encrypted_value) FROM cookies WHERE host_key LIKE '%.slack.com%' AND name = 'd' LIMIT 1;"
      ], { encoding: 'utf-8', timeout: 5000 }).trim();
    } catch (e) {
      return { cookie: null, reason: isTimeoutError(e) ? 'cookie_query_timeout' : 'cookie_query_failed' };
    }

    if (!queryResult) return { cookie: null, reason: 'no_slack_cookie_row' };

    const encrypted = Buffer.from(queryResult, 'hex');
    if (encrypted.length < 4) return { cookie: null, reason: 'cookie_value_malformed' };

    let safeStoragePassword;
    try {
      safeStoragePassword = getSafeStorageKey();
    } catch (e) {
      return { cookie: null, reason: isTimeoutError(e) ? 'keychain_timeout' : 'keychain_lookup_failed' };
    }

    // macOS Chrome cookies: v10 prefix + AES-128-CBC
    const prefix = encrypted.subarray(0, 3).toString('utf-8');
    if (prefix !== 'v10') return { cookie: null, reason: 'unsupported_cookie_format' };

    const ciphertext = encrypted.subarray(3);
    const decryptWith = (password) => {
      try {
        const key = pbkdf2Sync(password, 'saltysalt', 1003, 16, 'sha1');
        const decipher = createDecipheriv('aes-128-cbc', key, Buffer.alloc(16, ' '));
        return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf-8');
      } catch {
        return null;
      }
    };

    let text = decryptWith(safeStoragePassword);
    if (text === null) {
      // Chrome may have re-keyed since the password was cached — refetch once.
      try {
        text = decryptWith(getSafeStorageKey({ forceRefresh: true }));
      } catch {
        text = null;
      }
      if (text === null) return { cookie: null, reason: 'cookie_decrypt_failed' };
    }

    const xoxdIndex = text.indexOf('xoxd-');
    if (xoxdIndex < 0) return { cookie: null, reason: 'no_xoxd_in_cookie' };
    return { cookie: text.substring(xoxdIndex), reason: null };
  } catch (e) {
    return { cookie: null, reason: 'cookie_extraction_failed' };
  } finally {
    try { rmSync(tmpDir, { recursive: true, force: true }); } catch {}
  }
}

/**
 * Test seam: the profile-level extractor has no platform gate (unlike the
 * full pipeline), so its failure taxonomy and Safe Storage caching are
 * testable on any OS with sqlite3 present.
 */
export function _extractCookieForProfileForTests(profileDir) {
  return extractCookieForProfile(profileDir);
}

// A dead Keychain affects every profile identically — stop the run instead of
// hammering the (possibly prompting) lookup once per profile per path.
const FATAL_COOKIE_REASONS = new Set(['keychain_timeout', 'keychain_lookup_failed']);

function fatalKeychainError(reason) {
  return reason === 'keychain_timeout'
    ? {
        code: 'keychain_timeout',
        message: 'The Chrome Safe Storage key lookup timed out.',
        detail: `The macOS Keychain took longer than ${safeStorageTimeoutMs()}ms to return Chrome's encryption key. Retry, unlock the Keychain, or raise SLACK_MCP_KEYCHAIN_TIMEOUT_MS.`
      }
    : {
        code: 'keychain_lookup_failed',
        message: "Could not read Chrome's Safe Storage key from the Keychain.",
        detail: 'Unlock the macOS Keychain and allow this terminal Keychain access (System Settings > Privacy & Security), then retry.'
      };
}

/**
 * Legacy helper: walk profiles and return the first cookie found.
 * Retained so existing callers that only want a cookie string keep working.
 */
function extractCookieFromChromeDB() {
  const base = getChromeBase();
  for (const profile of enumerateChromeProfiles()) {
    const { cookie, reason } = extractCookieForProfile(join(base, profile));
    if (cookie) return cookie;
    if (FATAL_COOKIE_REASONS.has(reason)) return null;
  }
  return null;
}

/**
 * Extract a Slack xoxc- token by reading the on-disk LevelDB for a profile.
 * This is the preferred path:
 *   - No AppleScript required
 *   - No "Allow JavaScript from Apple Events" Chrome dev flag required
 *   - No live Slack tab required — the token just has to have been cached
 *     at some point during normal use
 *   - Works headlessly, works in CI, works when Chrome is closed
 *
 * We scan .ldb and .log files newest-first so the freshest cached token wins.
 */
function extractTokenFromLevelDB(profileDir) {
  const ldbDir = join(profileDir, 'Local Storage', 'leveldb');
  if (!existsSync(ldbDir)) return null;

  let files;
  try {
    files = readdirSync(ldbDir)
      .filter(f => /\.(ldb|log)$/.test(f))
      .map(f => {
        const p = join(ldbDir, f);
        let mtime = 0;
        try { mtime = statSync(p).mtimeMs; } catch {}
        return { path: p, mtime };
      })
      .sort((a, b) => b.mtime - a.mtime);
  } catch {
    return null;
  }

  for (const f of files) {
    try {
      // Binary encoding avoids UTF-8 re-interpretation of snappy-compressed blocks
      const txt = readFileSync(f.path).toString('binary');
      XOXC_TOKEN_RE.lastIndex = 0;
      const matches = txt.match(XOXC_TOKEN_RE);
      // LevelDB .log/.ldb files append newer records after older ones, so
      // the LAST match in a file is the most recently cached token — the
      // first match can be a stale, already-rotated token.
      if (matches && matches.length) return matches[matches.length - 1];
    } catch {
      continue;
    }
  }
  return null;
}

/**
 * Extract Slack token from Chrome via AppleScript (reads localStorage).
 * Uses strict URL matching to avoid hitting non-Slack tabs.
 */
function extractTokenFromChrome() {
  // Prefer /client URLs (active workspace), fall back to any app.slack.com
  const urlChecks = [
    'URL of t starts with "https://app.slack.com/client"',
    'URL of t starts with "https://app.slack.com"',
  ];

  const tokenPathsJS = SLACK_TOKEN_PATHS.map((path, i) =>
    `try { var t${i} = ${path}; if (t${i} && t${i}.startsWith('xoxc-')) return t${i}; } catch(e) {}`
  ).join(' ');

  for (const urlCheck of urlChecks) {
    try {
      const script = `tell application "Google Chrome"
  repeat with w in windows
    repeat with t in tabs of w
      if ${urlCheck} then
        return execute t javascript "(function() { ${tokenPathsJS} return ''; })()"
      end if
    end repeat
  end repeat
  return ""
end tell`;

      const token = execFileSync('osascript', ['-e', script], {
        encoding: 'utf-8', timeout: 8000
      }).trim();

      if (token && token.startsWith('xoxc-')) return token;
    } catch {
      continue;
    }
  }

  return null;
}

/**
 * Extract tokens from Chrome (macOS only).
 *
 * Two extraction paths:
 *
 *   1. LevelDB (preferred, default "auto" mode tries this first):
 *      Cookie: Reads the encrypted SQLite cookie DB and decrypts with the
 *              Chrome Safe Storage key from macOS Keychain.
 *      Token:  Reads the on-disk LevelDB under Local Storage and regex-matches
 *              any cached xoxc- token. Works without a live Slack tab, without
 *              the AppleScript dev flag, and works when Chrome is closed.
 *
 *   2. AppleScript (legacy fallback, or forced with SLACK_MCP_EXTRACTION_MODE=applescript):
 *      Cookie: Same SQLite-backed path.
 *      Token:  Drives Chrome via AppleScript to run JS against localStorage.
 *              Requires Chrome > View > Developer > "Allow JavaScript from
 *              Apple Events" AND a live app.slack.com tab. Kept because it
 *              grabs the token from whichever workspace is actually active
 *              right now, which can differ from what's cached on disk.
 *
 * Environment overrides:
 *   SLACK_MCP_CHROME_USER_DATA_DIR  - base Chrome dir (default ~/Library/Application Support/Google/Chrome)
 *   SLACK_MCP_CHROME_PROFILE        - pin a single profile directory name
 *   SLACK_MCP_EXTRACTION_MODE       - auto | leveldb | applescript
 */
function extractFromChromeInternal() {
  lastExtractionError = null;

  if (!IS_MACOS) {
    lastExtractionError = {
      code: "unsupported_platform",
      message: "Chrome auto-extraction is only available on macOS.",
      detail: "Use manual token setup on this platform, or set SLACK_TOKEN and SLACK_COOKIE env vars."
    };
    return null;
  }

  const mode = getExtractionMode();
  const base = getChromeBase();
  const profiles = enumerateChromeProfiles();

  if (profiles.length === 0) {
    lastExtractionError = {
      code: "no_chrome_profiles",
      message: "No Chrome profiles found.",
      detail: `Looked under ${base}. Set SLACK_MCP_CHROME_USER_DATA_DIR if Chrome is installed elsewhere.`
    };
    return null;
  }

  // Per-profile failure reasons, so the final error can say WHY instead of
  // collapsing everything into a generic all-paths failure (#168).
  const profileReasons = [];

  // --- Path 1: LevelDB (no AppleScript, no live tab needed) ---
  if (mode === 'leveldb' || mode === 'auto') {
    for (const profileName of profiles) {
      const profileDir = join(base, profileName);
      const { cookie, reason } = extractCookieForProfile(profileDir);
      if (!cookie) {
        if (FATAL_COOKIE_REASONS.has(reason)) {
          lastExtractionError = fatalKeychainError(reason);
          return null;
        }
        profileReasons.push(`${profileName}: ${reason}`);
        continue;
      }
      const token = extractTokenFromLevelDB(profileDir);
      if (!token) {
        profileReasons.push(`${profileName}: cookie ok, no cached xoxc token in LevelDB`);
        continue;
      }
      return { token, cookie, profile: profileName, extraction_mode: 'leveldb' };
    }

    if (mode === 'leveldb') {
      lastExtractionError = {
        code: "leveldb_no_matching_profile",
        message: "No Chrome profile had both a Slack cookie and a cached xoxc- token on disk.",
        detail: `Per-profile: ${profileReasons.join('; ') || 'none checked'}. Open Slack in Chrome and sign in once, then retry. SLACK_MCP_CHROME_PROFILE can pin a specific profile.`
      };
      return null;
    }
    // Fall through to AppleScript
  }

  // --- Path 2: AppleScript + SQLite (legacy, requires live tab + dev flag) ---
  if (mode === 'applescript' || mode === 'auto') {
    // The AppleScript token read talks to the running Chrome app, not to a
    // profile directory — one attempt covers every profile. Find the first
    // profile with a cookie, then run the (slow, possibly prompting)
    // AppleScript exactly once instead of once per profile (#168).
    let cookieSeen = null;
    for (const profileName of profiles) {
      const profileDir = join(base, profileName);
      const { cookie, reason } = extractCookieForProfile(profileDir);
      if (cookie) {
        cookieSeen = { cookie, profileName };
        break;
      }
      if (FATAL_COOKIE_REASONS.has(reason)) {
        lastExtractionError = fatalKeychainError(reason);
        return null;
      }
      if (mode === 'applescript') profileReasons.push(`${profileName}: ${reason}`);
    }

    if (cookieSeen) {
      let token = null;
      try {
        token = extractTokenFromChrome();
      } catch (e) {
        lastExtractionError = normalizeExtractionError(e);
      }
      if (token) {
        return { token, cookie: cookieSeen.cookie, profile: cookieSeen.profileName, extraction_mode: 'applescript' };
      }
      if (!lastExtractionError) {
        lastExtractionError = {
          code: "apple_events_javascript_disabled",
          message: "Cookie extracted, but AppleScript could not read the Slack token from localStorage.",
          detail: "Enable Chrome > View > Developer > Allow JavaScript from Apple Events, then retry. Or set SLACK_MCP_EXTRACTION_MODE=leveldb to skip AppleScript entirely."
        };
      }
      return null;
    }
  }

  if (!lastExtractionError) {
    lastExtractionError = {
      code: "extraction_failed_all_paths",
      message: "Could not extract Slack credentials via LevelDB or AppleScript.",
      detail: `Per-profile: ${profileReasons.join('; ') || `profiles checked: ${profiles.join(', ')}`}. Ensure you are logged into Slack at app.slack.com in Chrome at least once.`
    };
  }
  return null;
}

/**
 * Extract tokens from Chrome with mutex lock
 * Prevents concurrent extraction attempts (race condition fix)
 */
export function extractFromChrome() {
  // Simple mutex: if another extraction is running, skip this one
  // This prevents race conditions from background + foreground refresh
  if (refreshInProgress) {
    return null; // Let the in-progress extraction complete
  }

  try {
    refreshInProgress = true;
    return extractFromChromeInternal();
  } finally {
    refreshInProgress = false;
  }
}

export function getLastExtractionError() {
  return lastExtractionError;
}

/**
 * Check if auto-refresh is available on this platform
 */
export function isAutoRefreshAvailable() {
  return IS_MACOS;
}

// ============ Keychain-Only Mode ============

function keychainUnavailableError() {
  const err = new Error(
    "SLACK_MCP_TOKEN_STORAGE=keychain-only requires the macOS Keychain, which is not available on this platform. " +
    "Unset SLACK_MCP_TOKEN_STORAGE, or set it to \"file\" to use the token file."
  );
  err.code = "keychain_unavailable";
  return err;
}

/**
 * Write both credentials to the Keychain and verify by reading them back.
 * Throws on any failure — in keychain-only mode there is no file backstop,
 * so an unverified write must never be reported as success.
 */
function writeKeychainVerified(token, cookie) {
  if (!keychain.available()) throw keychainUnavailableError();

  const wroteToken = saveToKeychain("token", token);
  const wroteCookie = saveToKeychain("cookie", cookie);
  const readToken = getFromKeychain("token");
  const readCookie = getFromKeychain("cookie");

  if (!wroteToken || !wroteCookie || readToken !== token || readCookie !== cookie) {
    const err = new Error(
      "Keychain write could not be verified (keychain-only mode). No plaintext file was written. " +
      "Check that the Keychain is unlocked and that this process is allowed to use it, then retry."
    );
    err.code = "keychain_write_failed";
    throw err;
  }
}

/**
 * Remove the plaintext token file, failing LOUDLY if it survives. In
 * keychain-only mode a silent removal failure would mean reporting success
 * while credentials remain on disk — the exact guarantee this mode exists to
 * provide — and every subsequent load would re-attempt migration, spawning
 * `security` subprocesses on the request hot path. An already-gone file
 * (ENOENT, or another process removed it first) is success, not failure.
 */
function removePlaintextTokenFileOrThrow() {
  try {
    unlinkSync(TOKEN_FILE);
  } catch (e) {
    if (e.code === "ENOENT" || !existsSync(TOKEN_FILE)) return;
    const err = new Error(
      `keychain-only mode: credentials are safely in the Keychain, but the plaintext token file ${TOKEN_FILE} ` +
      `could not be removed (${e.message}). Delete it manually (rm "${TOKEN_FILE}") so credentials do not remain ` +
      "on disk in plaintext."
    );
    err.code = "plaintext_removal_failed";
    throw err;
  }
}

/**
 * One-time migration for keychain-only mode: import an existing plaintext
 * token file into the Keychain, then remove it — but only after both entries
 * verify by read-back (#162). On failure the file is left untouched.
 */
function migrateFileTokensToKeychain(fileTokens) {
  try {
    writeKeychainVerified(fileTokens.token, fileTokens.cookie);
  } catch (e) {
    const err = new Error(
      `keychain-only mode: could not migrate ${TOKEN_FILE} into the Keychain (${e.message}) ` +
      "The plaintext file was left in place. Fix Keychain access and retry, or unset SLACK_MCP_TOKEN_STORAGE."
    );
    err.code = "keychain_migration_failed";
    throw err;
  }

  // Preserve timestamp + telemetry before the file goes away.
  saveMeta({
    updated_at: fileTokens.updatedAt || new Date().toISOString(),
    last_auto_heal_attempt: fileTokens.lastAutoHealAttempt || null,
    last_auto_heal_error: fileTokens.lastAutoHealError || null,
    stuck_since: fileTokens.stuckSince || null
  });

  removePlaintextTokenFileOrThrow();
}

/**
 * Storage-backend summary for status surfaces (slack_token_status, CLI).
 * plaintext_file_present is the honest signal: in keychain-only mode it
 * should read false once migration has run.
 */
export function getStorageInfo() {
  const { mode, source } = getStorageModeDetail();
  return {
    mode,
    mode_source: source,
    // Workspace/profile namespace (#164); null = the default namespace.
    profile: ACTIVE_PROFILE || null,
    keychain_available: keychain.available(),
    plaintext_file_present: existsSync(TOKEN_FILE),
    // True while this process is serving freshly extracted tokens that could
    // not be persisted (e.g. locked Keychain) — the persistent store is stale.
    unpersisted_fresh_tokens: Boolean(memoryTokens)
  };
}

// ============ Main Token Loader ============

function getStoredTokens() {
  if (process.env.SLACK_TOKEN && process.env.SLACK_COOKIE) {
    return {
      token: process.env.SLACK_TOKEN,
      cookie: process.env.SLACK_COOKIE,
      source: "environment"
    };
  }

  // Only populated while persistence is failing (see saveTokens): the freshest
  // credentials this process has seen beat the stale persisted copy, so an
  // auth-failure retry actually uses the tokens that were just extracted.
  if (memoryTokens) {
    return memoryTokens;
  }

  const mode = getStorageMode();

  if (mode === "keychain-only") {
    // Legacy plaintext file present? Migrate it in, verified, then remove it.
    const legacy = getFromFile();
    if (legacy?.token && legacy?.cookie) {
      migrateFileTokensToKeychain(legacy);
    }

    const keychainToken = getFromKeychain("token");
    const keychainCookie = getFromKeychain("cookie");
    if (keychainToken && keychainCookie) {
      const meta = getMeta();
      return {
        token: keychainToken,
        cookie: keychainCookie,
        source: "keychain",
        updatedAt: meta.updated_at || null,
        lastAutoHealAttempt: meta.last_auto_heal_attempt || null,
        lastAutoHealError: meta.last_auto_heal_error || null,
        stuckSince: meta.stuck_since || null
      };
    }
    return null;
  }

  const fileTokens = getFromFile();
  if (fileTokens?.token && fileTokens?.cookie) {
    return {
      token: fileTokens.token,
      cookie: fileTokens.cookie,
      source: "file",
      updatedAt: fileTokens.updatedAt,
      lastAutoHealAttempt: fileTokens.lastAutoHealAttempt,
      lastAutoHealError: fileTokens.lastAutoHealError,
      stuckSince: fileTokens.stuckSince
    };
  }

  if (mode === "auto") {
    const keychainToken = getFromKeychain("token");
    const keychainCookie = getFromKeychain("cookie");
    if (keychainToken && keychainCookie) {
      return {
        token: keychainToken,
        cookie: keychainCookie,
        source: "keychain"
      };
    }
  }

  return null;
}

export function loadTokensReadOnly() {
  return getStoredTokens();
}

export function loadTokens(forceRefresh = false, logger = console, options = {}) {
  const { autoExtract = true } = options;
  if (!forceRefresh) {
    const storedTokens = getStoredTokens();
    if (storedTokens) return storedTokens;
  }

  if (!autoExtract) return null;

  logger.error?.("Attempting Chrome auto-extraction...");
  const chromeTokens = extractFromChrome();
  if (chromeTokens) {
    logger.error?.("Successfully extracted tokens from Chrome!");
    // Persistence failure (e.g. locked Keychain in keychain-only mode) must
    // not discard a successful extraction — the session proceeds in memory
    // and the next call re-extracts.
    try {
      saveTokens(chromeTokens.token, chromeTokens.cookie);
    } catch (e) {
      logger.error?.(`Extracted tokens could not be persisted: ${e.message}`);
    }
    return {
      token: chromeTokens.token,
      cookie: chromeTokens.cookie,
      source: "chrome-auto"
    };
  }

  if (lastExtractionError?.code === "apple_events_javascript_disabled") {
    logger.error?.(lastExtractionError.message);
    logger.error?.(lastExtractionError.detail);
  }

  return null;
}

export function saveTokens(token, cookie) {
  const mode = getStorageMode();

  try {
    if (mode === "keychain-only") {
      writeKeychainVerified(token, cookie);
      saveMeta({ updated_at: new Date().toISOString() });
      // A refresh must never resurrect the plaintext file; removal happens
      // strictly after the verified Keychain write above, and a removal
      // failure is loud — never a silent plaintext leftover.
      if (existsSync(TOKEN_FILE)) {
        removePlaintextTokenFileOrThrow();
      }
    } else {
      saveToFile(token, cookie);
      if (mode === "auto") {
        saveToKeychain("token", token);
        saveToKeychain("cookie", cookie);
      }
    }
    // Persistence succeeded: the persistent store is authoritative again, and
    // refreshes written by other processes must be visible on the next load.
    memoryTokens = null;
  } catch (e) {
    if (e.code === "plaintext_removal_failed") {
      // The credentials DID reach the Keychain — only the plaintext cleanup
      // failed. The persistent store is current, so no memory fallback:
      // holding one would misreport unpersisted_fresh_tokens.
      memoryTokens = null;
    } else {
      // Persistence failed: keep the freshest credentials available to this
      // process so the session (and the auth-failure retry) can proceed,
      // then rethrow so callers report the failure honestly.
      memoryTokens = {
        token,
        cookie,
        source: "memory",
        updatedAt: new Date().toISOString()
      };
    }
    throw e;
  }
}

export { TOKEN_FILE, META_FILE, KEYCHAIN_SERVICE, ACTIVE_PROFILE };
