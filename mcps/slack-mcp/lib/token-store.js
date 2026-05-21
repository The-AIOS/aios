/**
 * Token Storage Module
 *
 * Multi-layer token persistence:
 * 1. Environment variables (highest priority)
 * 2. Token file (~/.slack-mcp-tokens.json)
 * 3. macOS Keychain (most secure)
 * 4. Chrome auto-extraction (fallback)
 */

import { readFileSync, writeFileSync, existsSync, renameSync, unlinkSync } from "fs";
import { homedir, platform } from "os";
import { join } from "path";
import { execSync, execFileSync } from "child_process";

const TOKEN_FILE = join(homedir(), ".slack-mcp-tokens.json");
const KEYCHAIN_SERVICE = "slack-mcp-server";

// Platform detection
const IS_MACOS = platform() === 'darwin';

// Refresh lock to prevent concurrent extraction attempts
let refreshInProgress = null;
let lastExtractionError = null;

// ============ Keychain Storage (macOS only) ============

export function getFromKeychain(key) {
  if (!IS_MACOS) return null; // Keychain is macOS-only
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
}

export function saveToKeychain(key, value) {
  if (!IS_MACOS) return false; // Keychain is macOS-only
  try {
    // Delete existing entry
    try {
      execFileSync("security", ["delete-generic-password", "-s", KEYCHAIN_SERVICE, "-a", key], { stdio: 'pipe' });
    } catch (e) { /* ignore */ }

    // Add new entry
    execFileSync("security", ["add-generic-password", "-s", KEYCHAIN_SERVICE, "-a", key, "-w", value], { stdio: 'pipe' });
    return true;
  } catch (e) {
    return false;
  }
}

// ============ File Storage ============

export function getFromFile() {
  if (!existsSync(TOKEN_FILE)) return null;
  try {
    const data = JSON.parse(readFileSync(TOKEN_FILE, "utf-8"));
    return {
      token: data.SLACK_TOKEN,
      cookie: data.SLACK_COOKIE,
      updatedAt: data.updated_at || data.UPDATED_AT || null
    };
  } catch (e) {
    return null;
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
      try { execSync(`chmod 600 "${tempPath}"`); } catch {}
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
  atomicWriteSync(TOKEN_FILE, JSON.stringify(data, null, 2));
}

// ============ Chrome Extraction ============

// Multiple localStorage paths Slack might use (for robustness)
const SLACK_TOKEN_PATHS = [
  // Current known path
  `JSON.parse(localStorage.localConfig_v2).teams[Object.keys(JSON.parse(localStorage.localConfig_v2).teams)[0]].token`,
  // Potential future paths
  `JSON.parse(localStorage.localConfig_v3).teams[Object.keys(JSON.parse(localStorage.localConfig_v3).teams)[0]].token`,
  // Redux store path (older Slack)
  `JSON.parse(localStorage.getItem('reduxPersist:localConfig'))?.teams?.[Object.keys(JSON.parse(localStorage.getItem('reduxPersist:localConfig'))?.teams || {})[0]]?.token`,
  // Direct boot data
  `window.boot_data?.api_token`,
];

function normalizeExtractionError(error) {
  const raw = String(error?.message || error || "");

  if (raw.includes("Executing JavaScript through AppleScript is turned off")) {
    return {
      code: "apple_events_javascript_disabled",
      message: "Chrome blocked JavaScript execution from Apple Events.",
      detail: "Enable it in Chrome: View > Developer > Allow JavaScript from Apple Events."
    };
  }

  if (raw.includes("Application isn't running") || raw.includes("Google Chrome got an error")) {
    return {
      code: "chrome_not_ready",
      message: "Chrome is not ready for token extraction.",
      detail: "Open Google Chrome with an active Slack tab at app.slack.com."
    };
  }

  if (raw.toLowerCase().includes("timed out")) {
    return {
      code: "chrome_extraction_timeout",
      message: "Chrome token extraction timed out.",
      detail: "Ensure Slack is open in Chrome and retry."
    };
  }

  return {
    code: "chrome_extraction_failed",
    message: "Chrome token extraction failed.",
    detail: raw || "Unknown extraction error."
  };
}

/**
 * Extract tokens from Chrome (macOS only, uses AppleScript)
 * Returns null on non-macOS platforms
 */
function extractFromChromeInternal() {
  lastExtractionError = null;
  if (!IS_MACOS) {
    // AppleScript/osascript is macOS-only
    lastExtractionError = {
      code: "unsupported_platform",
      message: "Chrome auto-extraction is only available on macOS.",
      detail: "Use manual token setup on this platform."
    };
    return null;
  }

  try {
    // Extract cookie
    const cookieScript = `
      tell application "Google Chrome"
        repeat with w in windows
          repeat with t in tabs of w
            if URL of t contains "slack.com" then
              return execute t javascript "document.cookie.split('; ').find(c => c.startsWith('d='))?.split('=')[1] || ''"
            end if
          end repeat
        end repeat
        return ""
      end tell
    `;
    const cookie = execSync(`osascript -e '${cookieScript.replace(/'/g, "'\"'\"'")}'`, {
      encoding: 'utf-8', timeout: 5000
    }).trim();

    if (!cookie || !cookie.startsWith('xoxd-')) {
      lastExtractionError = {
        code: "cookie_not_found",
        message: "Could not extract Slack cookie from Chrome.",
        detail: "Ensure a logged-in Slack tab is open at app.slack.com."
      };
      return null;
    }

    // Try multiple token extraction paths
    const tokenPathsJS = SLACK_TOKEN_PATHS.map((path, i) =>
      `try { var t${i} = ${path}; if (t${i}?.startsWith('xoxc-')) return t${i}; } catch(e) {}`
    ).join(' ');

    const tokenScript = `
      tell application "Google Chrome"
        repeat with w in windows
          repeat with t in tabs of w
            if URL of t contains "slack.com" then
              return execute t javascript "(function() { ${tokenPathsJS} return ''; })()"
            end if
          end repeat
        end repeat
        return ""
      end tell
    `;
    const token = execSync(`osascript -e '${tokenScript.replace(/'/g, "'\"'\"'")}'`, {
      encoding: 'utf-8', timeout: 5000
    }).trim();

    if (!token || !token.startsWith('xoxc-')) {
      lastExtractionError = {
        code: "token_not_found",
        message: "Could not extract Slack token from Chrome.",
        detail: "Refresh Slack in Chrome and retry extraction."
      };
      return null;
    }

    return { token, cookie };
  } catch (e) {
    lastExtractionError = normalizeExtractionError(e);
    return null;
  }
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

// ============ Main Token Loader ============

function getStoredTokens() {
  if (process.env.SLACK_TOKEN && process.env.SLACK_COOKIE) {
    return {
      token: process.env.SLACK_TOKEN,
      cookie: process.env.SLACK_COOKIE,
      source: "environment"
    };
  }

  const fileTokens = getFromFile();
  if (fileTokens?.token && fileTokens?.cookie) {
    return {
      token: fileTokens.token,
      cookie: fileTokens.cookie,
      source: "file",
      updatedAt: fileTokens.updatedAt
    };
  }

  const keychainToken = getFromKeychain("token");
  const keychainCookie = getFromKeychain("cookie");
  if (keychainToken && keychainCookie) {
    return {
      token: keychainToken,
      cookie: keychainCookie,
      source: "keychain"
    };
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
    saveTokens(chromeTokens.token, chromeTokens.cookie);
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
  saveToFile(token, cookie);
  saveToKeychain("token", token);
  saveToKeychain("cookie", cookie);
}

export { TOKEN_FILE, KEYCHAIN_SERVICE };
