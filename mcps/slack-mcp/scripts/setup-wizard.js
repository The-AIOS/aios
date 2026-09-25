#!/usr/bin/env node
/**
 * slack-mcp-server Setup Wizard
 *
 * Interactive setup that:
 * - Detects platform
 * - Auto-extracts tokens on macOS
 * - Guides manual entry on Linux/Windows
 * - Validates tokens against Slack API
 * - Saves to ~/.slack-mcp-tokens.json
 */

import { platform } from "os";
import * as readline from "readline";
import {
  saveTokens,
  extractFromChrome,
  getLastExtractionError,
  isAutoRefreshAvailable,
  TOKEN_FILE,
  getFromFile,
  getFromKeychain,
  getStorageMode,
  getStorageModeDetail,
  setPersistedStorageMode,
  ACTIVE_PROFILE,
} from "../lib/token-store.js";
import { PUBLIC_METADATA, RELEASE_VERSION } from "../lib/public-metadata.js";

const IS_MACOS = platform() === 'darwin';

// Validate the storage mode up front so a bad SLACK_MCP_TOKEN_STORAGE value
// fails with the clear one-line error instead of a mid-wizard stack trace.
// Read live (not cached) everywhere below: the wizard can change the
// persisted mode mid-run.
try {
  getStorageMode();
} catch (e) {
  console.error(e.message);
  process.exit(1);
}

// keychain-only is a macOS-only backend. Fail here — before any credentials
// are collected — instead of gathering valid tokens that cannot be saved.
if (!IS_MACOS && getStorageMode() === 'keychain-only') {
  const origin = getStorageModeDetail().source === 'env'
    ? 'Unset SLACK_MCP_TOKEN_STORAGE, or set it to "file" or "auto".'
    : 'Remove the storage_mode entry from ~/.slack-mcp-meta.json, or set SLACK_MCP_TOKEN_STORAGE=file to override.';
  console.error(`keychain-only token storage requires the macOS Keychain, which is not available on this platform. ${origin}`);
  process.exit(1);
}

function isKeychainOnly() {
  return getStorageMode() === 'keychain-only';
}

function storageDestination() {
  return isKeychainOnly() ? 'the macOS Keychain (keychain-only mode)' : TOKEN_FILE;
}

function savedMessage() {
  return isKeychainOnly()
    ? 'Tokens saved to the macOS Keychain — no plaintext file written'
    : 'Tokens saved with chmod 600';
}

/**
 * Persist tokens with a friendly failure path: saveTokens() throws in
 * keychain-only mode when the Keychain is locked/unavailable or a leftover
 * plaintext file cannot be removed. A first-run stack trace for a locked
 * Keychain is the worst possible setup experience — translate each failure
 * into the action that fixes it. The success message only prints after the
 * save (including plaintext removal) fully succeeded.
 */
function persistTokens(token, cookie) {
  print();
  print(`Writing to ${storageDestination()}...`);
  try {
    saveTokens(token, cookie);
  } catch (e) {
    error(`Could not save tokens: ${e.message}`);
    if (e.code === 'keychain_write_failed' || e.code === 'keychain_unavailable') {
      print('Unlock the macOS Keychain (open Keychain Access, or log in again), then re-run --setup.');
      print('Or re-run --setup and choose option 1 to store tokens in a file instead.');
    } else if (e.code === 'plaintext_removal_failed') {
      print('Your tokens ARE saved in the Keychain — but the old plaintext token file could not be removed.');
    }
    return false;
  }
  success(savedMessage());
  return true;
}
const VERSION = RELEASE_VERSION;
const MIN_NODE_MAJOR = 20;
const AUTH_TEST_URL = process.env.SLACK_MCP_AUTH_TEST_URL || "https://slack.com/api/auth.test";

// ANSI colors
const colors = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  red: '\x1b[31m',
  cyan: '\x1b[36m',
};

function print(msg = '') {
  console.log(msg);
}

function printBox(lines, width = 60) {
  const border = '─'.repeat(width);
  print(`┌${border}┐`);
  for (const line of lines) {
    const padding = ' '.repeat(Math.max(0, width - line.length));
    print(`│ ${line}${padding}│`);
  }
  print(`└${border}┘`);
}

function success(msg) {
  print(`${colors.green}✓${colors.reset} ${msg}`);
}

function warn(msg) {
  print(`${colors.yellow}⚠${colors.reset} ${msg}`);
}

function error(msg) {
  print(`${colors.red}✗${colors.reset} ${msg}`);
}

function info(msg) {
  print(`${colors.blue}ℹ${colors.reset} ${msg}`);
}

async function question(rl, prompt) {
  return new Promise(resolve => rl.question(prompt, resolve));
}

async function pressEnterToContinue(rl) {
  await question(rl, `\n${colors.dim}[Press Enter to continue, Ctrl+C to cancel]${colors.reset}`);
}

async function validateTokens(token, cookie) {
  try {
    const response = await fetch(AUTH_TEST_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Cookie": `d=${cookie}`,
        "Content-Type": "application/json; charset=utf-8",
      },
      body: JSON.stringify({}),
    });

    const result = await response.json();
    if (!result.ok) {
      return { valid: false, error: result.error || "auth.test_failed" };
    }

    return { valid: true, user: result.user, team: result.team, userId: result.user_id };
  } catch (e) {
    return { valid: false, error: e.message };
  }
}

/**
 * Ask where credentials should live and remember the answer, so the choice
 * follows every process (MCP server, CLI, LaunchAgent) without plumbing an
 * env var into each client config. Skipped when SLACK_MCP_TOKEN_STORAGE is
 * set — the env var is the authoritative override — and on platforms
 * without a Keychain, where the token file is the only option.
 */
async function chooseStorageMode(rl) {
  if (!IS_MACOS) return;

  const detail = getStorageModeDetail();
  if (detail.source === 'env') {
    info(`Storage mode: ${detail.mode} (set via SLACK_MCP_TOKEN_STORAGE — overrides the setup choice)`);
    return;
  }

  const current = detail.mode;
  const defaultChoice = current === 'keychain-only' ? '2' : '1';
  print();
  print(`${colors.bold}Where should your Slack tokens be stored?${colors.reset}`);
  print(`  1) Token file (chmod 600) + macOS Keychain backup${current !== 'keychain-only' ? `  ${colors.dim}(current)${colors.reset}` : ''}`);
  print(`  2) macOS Keychain only — no plaintext file on disk${current === 'keychain-only' ? `  ${colors.dim}(current)${colors.reset}` : ''}`);
  print();

  // Accept only 1, 2, or Enter-for-default: for a credential-storage choice a
  // typo must re-prompt, never silently select plaintext storage.
  let mode = null;
  while (mode === null) {
    const answer = (await question(rl, `Choice [${defaultChoice}]: `)).trim() || defaultChoice;
    if (answer === '1') mode = 'auto';
    else if (answer === '2') mode = 'keychain-only';
    else warn(`"${answer}" is not an option — answer 1 or 2.`);
  }
  setPersistedStorageMode(mode);

  if (mode === 'keychain-only') {
    success('Keychain-only storage selected — credentials never touch a plaintext file.');
  }
  print();
}

async function runMacOSSetup(rl) {
  print();
  info("Detected platform: macOS");
  info("Auto-extraction available via AppleScript");
  print();
  print("Requirements:");
  print("  • Chrome browser installed");
  print("  • Logged into Slack in a Chrome tab");
  print("  • That Slack tab currently open");

  await pressEnterToContinue(rl);

  print();
  print("Checking for Chrome...");

  // Check if Chrome is running with a Slack tab
  const tokens = extractFromChrome();

  if (!tokens) {
    const extractionError = getLastExtractionError();
    print();
    error("Could not extract tokens from Chrome.");
    if (extractionError) {
      print(`Reason: ${extractionError.message}`);
      if (extractionError.detail) {
        print(`Detail: ${extractionError.detail}`);
      }
    }
    print();
    if (extractionError?.code === "apple_events_javascript_disabled") {
      print();
      printBox([
        "Chrome needs one setting enabled (one-time only):",
        "",
        "1. Open Chrome",
        "2. Menu bar: View → Developer → Allow JavaScript",
        "   from Apple Events  ✓",
        "3. Run this command again",
      ], 55);
      print();
      print("Once enabled, --setup extracts tokens automatically.");
      print("No DevTools, no copy-paste, just one command.");
    } else {
      print("Make sure:");
      print("  1. Chrome is running");
      print("  2. You have a Slack tab open (app.slack.com)");
      print("  3. You're logged into that workspace");
      print();
      print(`${colors.dim}Chrome-free or non-macOS? Hosted tier bypasses Chrome entirely:${colors.reset}`);
      print(`${colors.dim}  https://mcp.revasserlabs.com${colors.reset}`);
    }
    print();

    const retry = await question(rl, "Try manual entry instead? (y/n): ");
    if (retry.toLowerCase() === 'y') {
      return await runManualSetup(rl);
    }
    return false;
  }

  success(`Extracted token: ${tokens.token.substring(0, 20)}...`);
  success(`Extracted cookie: ${tokens.cookie.substring(0, 20)}...`);

  print();
  print("Validating against Slack API...");

  const validation = await validateTokens(tokens.token, tokens.cookie);

  if (!validation.valid) {
    error(`Token validation failed: ${validation.error}`);
    print();
    print("Try refreshing your Slack tab and running again.");
    return false;
  }

  success(`Workspace: ${validation.team}`);
  success(`User: ${validation.user}`);

  return persistTokens(tokens.token, tokens.cookie);
}

async function runManualSetup(rl) {
  print();
  if (IS_MACOS) {
    info("Switching to manual token entry...");
    info("Note: On macOS, the session cookie can be extracted automatically.");
  } else {
    info(`Detected platform: ${platform()}`);
    warn("Auto-extraction not available on this platform.");
  }

  const consoleHotkey = IS_MACOS ? "Cmd+Option+J" : "Ctrl+Shift+J";
  // Token-only one-liner (cookie is HttpOnly and cannot be read via document.cookie)
  const oneLiner = `copy(JSON.parse(localStorage.localConfig_v2).teams[Object.keys(JSON.parse(localStorage.localConfig_v2).teams)[0]].token)`;

  print();
  print(`${colors.bold}Quick extract (recommended):${colors.reset}`);
  print();
  print(`  1. Open Chrome → ${colors.cyan}app.slack.com${colors.reset} (must be logged in)`);
  print(`  2. Press ${colors.cyan}${consoleHotkey}${colors.reset} to open the Console`);
  print(`  3. Paste this one-liner and press Enter:`);
  print();
  printBox([oneLiner], oneLiner.length + 4);
  print();
  print(`  4. Your token is now on the clipboard. Paste below.`);
  if (IS_MACOS) {
    print(`  ${colors.dim}(Cookie will be extracted automatically from Chrome)${colors.reset}`);
  }
  print();
  print(`${colors.dim}(Or paste a JSON object with token+cookie, or a raw xoxc- token)${colors.reset}`);
  print();

  const input = await question(rl, `${colors.bold}Paste token:${colors.reset} `);
  const trimmed = input.trim();

  let token, cookie;

  // Try JSON parse first (legacy one-liner output or manual JSON)
  if (trimmed.startsWith('{')) {
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed.token) token = parsed.token;
      if (parsed.cookie) cookie = parsed.cookie;
    } catch (_) {
      // Not valid JSON — fall through to raw token
    }
  }

  // Treat as raw token
  if (!token) {
    token = trimmed;
    if (!token.startsWith('xoxc-')) {
      error("Invalid input. Expected a token starting with 'xoxc-'");
      return false;
    }
  }

  // On macOS, try to extract cookie from Chrome's cookie database automatically
  if (!cookie && IS_MACOS) {
    print();
    print("Extracting session cookie from Chrome...");
    const chromeTokens = extractFromChrome();
    if (chromeTokens?.cookie) {
      cookie = chromeTokens.cookie;
      success("Cookie extracted from Chrome automatically");
    } else {
      warn("Could not extract cookie automatically.");
      print(`  Paste the cookie manually. In Chrome: ${colors.cyan}Application${colors.reset} tab → ${colors.cyan}Cookies${colors.reset} → find '${colors.cyan}d${colors.reset}'`);
      print();
      const cookieInput = await question(rl, `${colors.bold}Paste cookie (xoxd-...):${colors.reset} `);
      cookie = cookieInput.trim();
    }
  }

  // Non-macOS: always ask for cookie
  if (!cookie) {
    print();
    print(`Paste the cookie. In Chrome: ${colors.cyan}Application${colors.reset} tab → ${colors.cyan}Cookies${colors.reset} → find '${colors.cyan}d${colors.reset}'`);
    print();
    const cookieInput = await question(rl, `${colors.bold}Paste cookie (xoxd-...):${colors.reset} `);
    cookie = cookieInput.trim();
  }

  if (!cookie.startsWith('xoxd-')) {
    error("Invalid cookie. Cookie should start with 'xoxd-'");
    return false;
  }

  print();
  print("Validating against Slack API...");

  const validation = await validateTokens(token, cookie);

  if (!validation.valid) {
    error(`Token validation failed: ${validation.error}`);
    print();
    print("Common issues:");
    print("  • Tokens expired - try refreshing Slack and copying again");
    print("  • Wrong workspace - make sure you copied from the right tab");
    print("  • Incomplete copy - ensure you got the full token/cookie");
    print();
    print(`${colors.dim}Tired of paste-the-token loops? Hosted tier uses OAuth:${colors.reset}`);
    print(`${colors.dim}  https://mcp.revasserlabs.com${colors.reset}`);
    return false;
  }

  success(`Workspace: ${validation.team}`);
  success(`User: ${validation.user}`);

  return persistTokens(token, cookie);
}

async function showStatus() {
  const creds = getDoctorCredentials();

  if (!creds) {
    error("No tokens found");
    print("Code: missing_credentials");
    print("Message: No credentials available from environment, file, or keychain.");
    print();
    print("Run setup wizard: npx -y @jtalk22/slack-mcp --setup");
    process.exit(1);
  }

  print(`Token source: ${creds.source}`);
  if (creds.path) {
    print(`Token file: ${creds.path}`);
  }
  if (creds.updatedAt) {
    print(`Last updated: ${creds.updatedAt}`);
  }
  print();

  const result = await validateTokens(creds.token, creds.cookie);
  if (!result.valid) {
    error("Status: INVALID");
    print("Code: auth_failed");
    print(`Error: ${result.error}`);
    print();
    print("Run setup wizard to refresh: npx -y @jtalk22/slack-mcp --setup");
    process.exit(1);
  }

  success("Status: VALID");
  print("Code: ok");
  print("Message: Slack auth valid.");
  print(`User: ${result.user}`);
  print(`Team: ${result.team}`);
  print(`User ID: ${result.userId}`);
}

function getDoctorCredentials() {
  if (process.env.SLACK_TOKEN && process.env.SLACK_COOKIE) {
    return { token: process.env.SLACK_TOKEN, cookie: process.env.SLACK_COOKIE, source: "environment" };
  }

  // The doctor is read-only, so in keychain-only mode it checks the Keychain
  // first and flags a lingering plaintext file instead of migrating it here —
  // migration runs on the next server start or token save.
  if (isKeychainOnly()) {
    const keychainToken = getFromKeychain("token");
    const keychainCookie = getFromKeychain("cookie");
    const legacy = getFromFile();
    const pendingMigration = Boolean(legacy?.token && legacy?.cookie);
    if (keychainToken && keychainCookie) {
      return { token: keychainToken, cookie: keychainCookie, source: "keychain", pendingMigration };
    }
    if (pendingMigration) {
      return {
        token: legacy.token,
        cookie: legacy.cookie,
        source: "file",
        path: TOKEN_FILE,
        updatedAt: legacy.updatedAt,
        pendingMigration: true,
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
      path: TOKEN_FILE,
      updatedAt: fileTokens.updatedAt,
    };
  }

  if (IS_MACOS) {
    const keychainToken = getFromKeychain("token");
    const keychainCookie = getFromKeychain("cookie");
    if (keychainToken && keychainCookie) {
      return { token: keychainToken, cookie: keychainCookie, source: "keychain" };
    }
  }

  return null;
}

function classifyAuthError(rawError) {
  const msg = String(rawError || "").toLowerCase();
  if (
    msg.includes("invalid_auth") ||
    msg.includes("token_expired") ||
    msg.includes("not_authed") ||
    msg.includes("account_inactive")
  ) {
    return 2;
  }
  return 3;
}

function parseNodeMajor() {
  return Number.parseInt(process.versions.node.split(".")[0], 10);
}

async function runDoctor() {
  print(`${colors.bold}slack-mcp-server doctor${colors.reset}`);
  print();

  const nodeMajor = parseNodeMajor();
  if (Number.isNaN(nodeMajor) || nodeMajor < MIN_NODE_MAJOR) {
    error(`Node.js ${process.versions.node} detected (requires Node ${MIN_NODE_MAJOR}+)`);
    print("Code: runtime_node_unsupported");
    print();
    print("Next action:");
    print(`  npx -y @jtalk22/slack-mcp --doctor  # rerun after upgrading Node ${MIN_NODE_MAJOR}+`);
    process.exit(3);
  }
  success(`Node.js ${process.versions.node} (supported)`);

  const creds = getDoctorCredentials();
  if (!creds) {
    error("Credentials: not found");
    print("Code: missing_credentials");
    print();
    print("Next action:");
    print("  npx -y @jtalk22/slack-mcp --setup");
    print();
    print(`${colors.dim}Prefer no local tokens? Hosted tier uses OAuth:${colors.reset}`);
    print(`${colors.dim}  https://mcp.revasserlabs.com${colors.reset}`);
    process.exit(1);
  }

  success(`Credentials loaded from: ${creds.source}`);
  if (creds.path) {
    print(`Path: ${creds.path}`);
  }
  if (creds.updatedAt) {
    print(`Last updated: ${creds.updatedAt}`);
  }
  const storageDetail = getStorageModeDetail();
  const sourceLabel = storageDetail.source === 'env'
    ? 'from SLACK_MCP_TOKEN_STORAGE'
    : storageDetail.source === 'persisted'
      ? 'chosen during setup'
      : 'default';
  print(`Storage mode: ${storageDetail.mode} (${sourceLabel})`);
  if (ACTIVE_PROFILE) {
    print(`Profile: ${ACTIVE_PROFILE}`);
  }
  if (isKeychainOnly() && creds.pendingMigration) {
    warn(`Plaintext token file still present at ${TOKEN_FILE} — it will be migrated into the Keychain and removed on the next server start or token refresh.`);
  }

  print();
  print("Validating Slack auth...");
  const validation = await validateTokens(creds.token, creds.cookie);
  if (!validation.valid) {
    const exitCode = classifyAuthError(validation.error);
    error(`Slack auth failed: ${validation.error}`);
    print(`Code: ${exitCode === 2 ? "auth_invalid" : "runtime_auth_check_failed"}`);
    print();
    print("Next action:");
    if (exitCode === 2) {
      print("  npx -y @jtalk22/slack-mcp --setup");
      print();
      print(`${colors.dim}Tokens expire every 1-2 weeks. Hosted tier has permanent OAuth:${colors.reset}`);
      print(`${colors.dim}  https://mcp.revasserlabs.com${colors.reset}`);
    } else {
      print("  Check network connectivity and retry:");
      print("  npx -y @jtalk22/slack-mcp --doctor");
    }
    process.exit(exitCode);
  }

  success(`Slack auth valid for ${validation.user} @ ${validation.team}`);
  print("Code: ok");
  print();
  print("Ready. Next command:");
  print("  npx -y @jtalk22/slack-mcp");
  process.exit(0);
}

async function showHelp() {
  print(`${colors.bold}slack-mcp-server v${VERSION}${colors.reset}`);
  print();
  print(`Turn your existing Slack browser session into ${PUBLIC_METADATA.selfHostedToolCount} tools for any stdio MCP client.`);
  print();
  print(`${colors.bold}Usage:${colors.reset}`);
  print("  npx -y @jtalk22/slack-mcp             Start MCP server (stdio)");
  print("  npx -y @jtalk22/slack-mcp --setup     Interactive token setup wizard");
  print("  npx -y @jtalk22/slack-mcp --status    Check token health");
  print("  npx -y @jtalk22/slack-mcp --doctor    Run runtime and auth diagnostics");
  print("  npx -y @jtalk22/slack-mcp --version   Print version");
  print("  npx -y @jtalk22/slack-mcp --help      Show this help");
  print();
  print(`${colors.bold}Multiple workspaces:${colors.reset}`);
  print("  Add --profile <name> to any command (or set SLACK_MCP_PROFILE) to");
  print("  keep credentials in a separate namespace per workspace — e.g.");
  print("  --setup --profile work, then a second server with --profile personal.");
  print();
  print(`${colors.bold}Tool selection:${colors.reset}`);
  print("  --tools essentials (or SLACK_MCP_TOOLS=essentials) advertises the six");
  print("  core tools to cut per-turn schema cost; 'read' advertises the 12");
  print(`  read-only Slack operations; 'all' is the default (${PUBLIC_METADATA.selfHostedToolCount}). Every handler`);
  print("  stays callable whichever surface is advertised.");
  print();
  print(`${colors.bold}Request pacing:${colors.reset}`);
  print("  Outbound Slack calls are paced by default. Tune with");
  print("  SLACK_MCP_MIN_REQUEST_INTERVAL_MS (default 350, 0 disables) and");
  print("  SLACK_MCP_MAX_CONCURRENCY (default 3).");
  print();
  print(`${colors.bold}npm scripts:${colors.reset}`);
  print("  npm start              Start MCP server");
  print("  npm run web            Start REST API + Web UI (port 3000)");
  print("  npm run tokens:auto    Auto-extract from Chrome (macOS)");
  print("  npm run tokens:status  Check token health");
  print();
  print(`${colors.bold}More info:${colors.reset}`);
  print("  https://github.com/jtalk22/slack-mcp-server");
  print();
  print(`${colors.bold}Hosted tier:${colors.reset}`);
  print("  https://mcp.revasserlabs.com — $19/mo Pro, permanent OAuth,");
  print("  semantic search, workflow continuity across channels.");
}

async function main() {
  const args = process.argv.slice(2);
  const command = args[0];

  switch (command) {
    case '--setup':
    case 'setup':
      break; // Continue to wizard
    case '--status':
    case 'status':
      await showStatus();
      return;
    case '--doctor':
    case 'doctor':
      await runDoctor();
      return;
    case '--version':
    case '-v':
      print(`slack-mcp-server v${VERSION}`);
      return;
    case '--help':
    case '-h':
    case 'help':
      await showHelp();
      return;
    default:
      if (command) {
        error(`Unknown command: ${command}`);
        print();
      }
      await showHelp();
      return;
  }

  // Run setup wizard
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  print();
  printBox([
    `🔧 slack-mcp-server Setup Wizard v${VERSION}`,
    '',
    'This wizard will extract your Slack session tokens',
    'from Chrome and configure slack-mcp-server.',
  ], 58);

  try {
    let success;

    await chooseStorageMode(rl);
    info(`Tokens will be stored in: ${storageDestination()}`);

    if (IS_MACOS && isAutoRefreshAvailable()) {
      success = await runMacOSSetup(rl);
    } else {
      success = await runManualSetup(rl);
    }

    print();
    if (success) {
      print(`${colors.green}${colors.bold}Setup complete!${colors.reset}`);
      print();
      print("Next steps:");
      print("  • Verify: npx -y @jtalk22/slack-mcp --status");
      print("  • Start server: npx -y @jtalk22/slack-mcp");
      print("  • Choose your client: https://github.com/jtalk22/slack-mcp-server/blob/main/docs/SETUP.md");
      print("  • Restart the client, then run slack_health_check");
      print();
      print(`${colors.dim}Want permanent tokens, semantic search, and workflow continuity?${colors.reset}`);
      print(`${colors.dim}Hosted tier: https://mcp.revasserlabs.com — $19/mo Pro, 25 free AI calls/mo.${colors.reset}`);
    } else {
      print(`${colors.red}Setup failed.${colors.reset} See errors above.`);
      process.exit(1);
    }
  } finally {
    rl.close();
  }
}

main().catch(e => {
  error(`Error: ${e.message}`);
  process.exit(1);
});
