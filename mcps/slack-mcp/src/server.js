#!/usr/bin/env node
/**
 * Slack MCP Server
 *
 * A Model Context Protocol server for Slack integration.
 * Provides read/write access to Slack messages, channels, and users.
 *
 * Features:
 * - Automatic token refresh from Chrome
 * - LRU user cache with TTL
 * - Network error retry with exponential backoff
 * - Background token health monitoring
 *
 * Speaks MCP 2026-07-28 and every 2025 revision over the same stdio pipe:
 * the SDK's stdio entry reads the client's opening message, selects the era,
 * and pins one server instance for the life of the connection.
 */

import { serveStdio } from "@modelcontextprotocol/server/stdio";
import { pathToFileURL } from "node:url";

import { loadTokensReadOnly } from "../lib/token-store.js";
import { checkTokenHealth } from "../lib/slack-client.js";
import { getActiveToolProfile } from "../lib/tools.js";
import { RELEASE_VERSION } from "../lib/public-metadata.js";
import { createSlackMcpServer, SERVER_NAME } from "../lib/mcp-server.js";

const SERVER_VERSION = RELEASE_VERSION;

// Background refresh interval (4 hours)
const BACKGROUND_REFRESH_INTERVAL = 4 * 60 * 60 * 1000;

// Resolve the advertised tool surface once per process. SLACK_MCP_TOOLS (or
// --tools=…) can narrow it to cut per-turn schema cost; the default is the full
// surface. Handlers stay fully wired regardless of what is advertised.
const ACTIVE_TOOLS = getActiveToolProfile();

// Main entry point
async function main() {
  // Check for credentials at startup
  const credentials = loadTokensReadOnly();
  if (!credentials) {
    console.error("WARNING: No Slack credentials found at startup");
    console.error("Use npx -y @jtalk22/slack-mcp --setup to configure credentials");
  } else {
    console.error(`Credentials loaded from: ${credentials.source}`);

    // Check token health on startup
    const health = await checkTokenHealth({ error: () => {} });
    if (health.warning) {
      console.error(`Token age: ${health.age_hours}h - ${health.message}`);
    }
  }

  // Background token health check (every 4 hours)
  // unref() alone doesn't prevent the stdio transport from keeping the event
  // loop alive after the MCP client disconnects — we add explicit shutdown
  // handlers below to kill zombie processes on stdin EOF and signals.
  const backgroundTimer = setInterval(async () => {
    try {
      const health = await checkTokenHealth(console);
      if (health.refreshed) {
        console.error("Background: tokens refreshed successfully");
      } else if (health.critical) {
        console.error("Background: tokens critical - open Slack in Chrome");
      }
    } catch (err) {
      console.error(`Background health check failed: ${err.message}`);
    }
  }, BACKGROUND_REFRESH_INTERVAL);
  backgroundTimer.unref();

  // Explicit shutdown path prevents the zombie-process pileup we were seeing
  // when Claude Code or another MCP client disconnected without signalling.
  // The stdio transport doesn't exit the event loop on its own when stdin EOFs.
  let shuttingDown = false;
  const shutdown = (reason) => {
    if (shuttingDown) return;
    shuttingDown = true;
    try { clearInterval(backgroundTimer); } catch {}
    console.error(`slack-mcp-server exiting: ${reason}`);
    process.exit(0);
  };
  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGHUP", () => shutdown("SIGHUP"));
  process.stdin.on("end", () => shutdown("stdin end (MCP client disconnected)"));
  process.stdin.on("error", (err) => shutdown(`stdin error: ${err?.message || err}`));

  // Surface which tool profile is active so a narrowed surface is never a
  // silent surprise (and a mistyped SLACK_MCP_TOOLS says so out loud).
  if (ACTIVE_TOOLS.warning) console.error(`Tool profile: ${ACTIVE_TOOLS.warning}`);
  console.error(
    `Tool profile: ${ACTIVE_TOOLS.profile} (${ACTIVE_TOOLS.tools.length} tools, source: ${ACTIVE_TOOLS.source})`
  );

  // Start server. The entry owns the transport and the era decision; the
  // default `legacy: 'serve'` keeps every 2025-era client working unchanged.
  serveStdio(() => createSlackMcpServer({ tools: ACTIVE_TOOLS.tools }), {
    onerror: (error) => console.error(`stdio transport: ${error?.message || error}`),
  });
  console.error(`${SERVER_NAME} v${SERVER_VERSION} running`);
}

function isDirectExecution() {
  if (!process.argv[1]) return false;
  try {
    return import.meta.url === pathToFileURL(process.argv[1]).href;
  } catch {
    return false;
  }
}

if (isDirectExecution()) {
  main().catch(error => {
    console.error("Fatal error:", error);
    process.exit(1);
  });
}

/**
 * Smithery sandbox server for capability scanning
 * Returns a server instance with mock config for tool discovery
 */
export function createSandboxServer() {
  return createSlackMcpServer({ tools: ACTIVE_TOOLS.tools });
}
