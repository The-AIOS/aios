#!/usr/bin/env node
/**
 * Slack MCP Server - HTTP Transport
 *
 * Streamable HTTP version for hosted deployments (Smithery, etc.)
 * Tokens provided via environment variables.
 *
 * Per-request and stateless, per MCP 2026-07-28: every POST is answered by a
 * fresh server instance, there is no `Mcp-Session-Id`, and GET/DELETE answer
 * 405. 2025-era clients are served the same way (the SDK's stateless legacy
 * idiom), so nothing older breaks — it just never minted a session here.
 */

import http from 'node:http';
import { createMcpHandler } from "@modelcontextprotocol/server";
import { toNodeHandler } from "@modelcontextprotocol/node";

import { getActiveToolProfile } from "../lib/tools.js";
import { RELEASE_VERSION } from "../lib/public-metadata.js";
import { createSlackMcpServer, SERVER_NAME } from "../lib/mcp-server.js";

const SERVER_VERSION = RELEASE_VERSION;
const PORT = process.env.PORT || 3000;
const HTTP_INSECURE = process.env.SLACK_MCP_HTTP_INSECURE === "1";
const HTTP_AUTH_TOKEN = process.env.SLACK_MCP_HTTP_AUTH_TOKEN || process.env.SLACK_API_KEY || null;
const HTTP_ALLOWED_ORIGINS = new Set(
  String(process.env.SLACK_MCP_HTTP_ALLOWED_ORIGINS || "")
    .split(",")
    .map(origin => origin.trim())
    .filter(Boolean)
);

// The headers a 2026-07-28 client sends on every request, plus the ones a
// 2025-era client still sends. There is no session header to allow because
// there is no session.
const MCP_ALLOWED_HEADERS = "Content-Type, Authorization, Accept, MCP-Protocol-Version, Mcp-Method, Mcp-Name";

function structuredError(code, message, nextAction = null, details = null) {
  const payload = {
    status: "error",
    code,
    message,
    next_action: nextAction
  };
  if (details) payload.details = details;
  return payload;
}

function parseBearerToken(req) {
  const auth = req.headers?.authorization;
  if (!auth) return null;
  const [scheme, token] = String(auth).split(" ");
  if (scheme?.toLowerCase() !== "bearer" || !token) return null;
  return token.trim();
}

function applyCors(req, res) {
  const origin = String(req.headers?.origin || "");
  const allowOrigin =
    HTTP_INSECURE
      ? "*"
      : (origin && HTTP_ALLOWED_ORIGINS.has(origin) ? origin : null);

  if (allowOrigin) {
    res.setHeader("Access-Control-Allow-Origin", allowOrigin);
    if (allowOrigin !== "*") res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", MCP_ALLOWED_HEADERS);
  return allowOrigin;
}

function denyOrigin(res) {
  res.writeHead(403, { "Content-Type": "application/json" });
  res.end(JSON.stringify(
    structuredError(
      "cors_origin_denied",
      "Origin is not allowed.",
      "Set SLACK_MCP_HTTP_ALLOWED_ORIGINS to a comma-separated allowlist."
    )
  ));
}

// Resolve the advertised tool surface once (SLACK_MCP_TOOLS narrows it; default
// is the full surface). Handlers stay fully wired regardless.
const ACTIVE_TOOLS = getActiveToolProfile();
if (ACTIVE_TOOLS.warning) console.warn(`Tool profile: ${ACTIVE_TOOLS.warning}`);

// One handler for the process; one server instance per request. The factory
// is the same one the stdio entry uses, so both transports advertise and
// dispatch identically.
const mcpHandler = createMcpHandler(
  () => createSlackMcpServer({ tools: ACTIVE_TOOLS.tools }),
  { onerror: (error) => console.error(`mcp: ${error?.message || error}`) }
);
const handleMcp = toNodeHandler(mcpHandler);

// Create HTTP server. The whole request path is guarded: a rejection that
// escaped here would be an unhandled promise rejection, which terminates the
// process in Node — one malformed request must never take the server down.
const httpServer = http.createServer((req, res) => {
  handleHttpRequest(req, res).catch((error) => {
    console.error(`request failed: ${error?.stack || error}`);
    if (!res.headersSent) {
      res.writeHead(500, { "Content-Type": "application/json" });
    }
    if (!res.writableEnded) {
      res.end(JSON.stringify(
        structuredError("internal_error", "The request could not be served.", "Retry; if it persists, check the server log.")
      ));
    }
  });
});

async function handleHttpRequest(req, res) {
  const allowOrigin = applyCors(req, res);

  if (req.method === 'OPTIONS') {
    if (!HTTP_INSECURE && req.headers?.origin && !allowOrigin) {
      denyOrigin(res);
      return;
    }
    res.writeHead(204);
    res.end();
    return;
  }

  // Health check endpoint
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      code: 'ok',
      message: 'HTTP transport healthy',
      server: SERVER_NAME,
      version: SERVER_VERSION
    }));
    return;
  }

  // MCP endpoint
  if (req.url === '/mcp' || req.url === '/') {
    // A browser-originated request from an origin outside the allowlist is
    // refused before it reaches the protocol layer (DNS-rebinding guard).
    if (!HTTP_INSECURE && req.headers?.origin && !allowOrigin) {
      denyOrigin(res);
      return;
    }

    if (!HTTP_INSECURE) {
      if (!HTTP_AUTH_TOKEN) {
        res.writeHead(503, { "Content-Type": "application/json" });
        res.end(JSON.stringify(
          structuredError(
            "http_auth_token_missing",
            "HTTP auth token is not configured for /mcp.",
            "Set SLACK_MCP_HTTP_AUTH_TOKEN (or SLACK_API_KEY), or set SLACK_MCP_HTTP_INSECURE=1 for local testing only."
          )
        ));
        return;
      }

      const bearer = parseBearerToken(req);
      if (bearer !== HTTP_AUTH_TOKEN) {
        // A 401 without a challenge dead-ends a client that could otherwise
        // discover how to authenticate; the spec has required the header
        // since 2025-06-18.
        res.writeHead(401, {
          "Content-Type": "application/json",
          "WWW-Authenticate": 'Bearer realm="slack-mcp", error="invalid_token"'
        });
        res.end(JSON.stringify(
          structuredError(
            "unauthorized",
            "Bearer token is invalid for /mcp.",
            "Provide Authorization: Bearer <SLACK_MCP_HTTP_AUTH_TOKEN>."
          )
        ));
        return;
      }
    }

    await handleMcp(req, res);
    return;
  }

  res.writeHead(404);
  res.end('Not found');
}

httpServer.listen(PORT, () => {
  console.log(`${SERVER_NAME} v${SERVER_VERSION} HTTP server running on port ${PORT}`);
  console.log(`MCP endpoint: http://localhost:${PORT}/mcp (stateless; MCP 2026-07-28 and 2025 revisions)`);
  console.log(`Tool profile: ${ACTIVE_TOOLS.profile} (${ACTIVE_TOOLS.tools.length} tools, source: ${ACTIVE_TOOLS.source})`);
  if (HTTP_INSECURE) {
    console.warn("WARNING: SLACK_MCP_HTTP_INSECURE=1 enabled. /mcp is unauthenticated and CORS is wildcard.");
  } else {
    if (!HTTP_AUTH_TOKEN) {
      console.warn("WARNING: SLACK_MCP_HTTP_AUTH_TOKEN is not set. /mcp will reject requests with 503.");
    } else {
      console.log("HTTP auth: bearer token required for /mcp");
    }

    if (HTTP_ALLOWED_ORIGINS.size > 0) {
      console.log(`CORS allowlist: ${Array.from(HTTP_ALLOWED_ORIGINS).join(", ")}`);
    } else {
      console.log("CORS allowlist: none (browser cross-origin requests denied by default)");
    }
  }
});

const shutdown = async () => {
  try { await mcpHandler.close(); } catch {}
  httpServer.close(() => process.exit(0));
};
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
