#!/usr/bin/env node
/**
 * Slack Web API Server
 *
 * Exposes Slack MCP tools as REST endpoints for browser access.
 * Run alongside or instead of the MCP server for web-based access.
 *
 */

import express from "express";
import { randomBytes } from "crypto";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { existsSync, readFileSync, writeFileSync, chmodSync } from "fs";
import { homedir } from "os";
import { loadTokensReadOnly } from "../lib/token-store.js";
import { PUBLIC_METADATA, RELEASE_VERSION } from "../lib/public-metadata.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
import {
  handleTokenStatus,
  handleHealthCheck,
  handleRefreshTokens,
  handleListConversations,
  handleConversationsHistory,
  handleGetFullConversation,
  handleSearchMessages,
  handleUsersInfo,
  handleSendMessage,
  handleGetThread,
  handleListUsers,
  handleAddReaction,
  handleRemoveReaction,
  handleConversationsMark,
  handleConversationsUnreads,
  handleUsersSearch,
} from "../lib/handlers.js";

const app = express();
const PORT = process.env.PORT || 3000;

// Secure API key management
const API_KEY_FILE = join(homedir(), ".slack-mcp-api-key");

function getOrCreateAPIKey() {
  // Priority 1: Environment variable
  if (process.env.SLACK_API_KEY) {
    return process.env.SLACK_API_KEY;
  }

  // Priority 2: Key file
  if (existsSync(API_KEY_FILE)) {
    try {
      return readFileSync(API_KEY_FILE, "utf-8").trim();
    } catch {}
  }

  // Priority 3: Generate new secure key
  const newKey = `smcp_${randomBytes(24).toString('base64url')}`;
  try {
    writeFileSync(API_KEY_FILE, newKey);
    chmodSync(API_KEY_FILE, 0o600);
  } catch {}

  return newKey;
}

const API_KEY = getOrCreateAPIKey();

// Middleware
app.use(express.json());
app.use(express.static(join(__dirname, "../public")));
// Compatibility alias so local web mode supports GitHub Pages-style /public/* URLs.
app.use("/public", express.static(join(__dirname, "../public")));
// Keep /docs URL compatibility for demo media and documentation links.
app.use("/docs", express.static(join(__dirname, "../docs")));

// CORS - restricted to localhost for security
// Using * would allow any website to make requests to your local server
const ALLOWED_ORIGINS = [
  `http://localhost:${PORT}`,
  `http://127.0.0.1:${PORT}`,
  'http://localhost:3000',
  'http://127.0.0.1:3000'
];

app.use((req, res, next) => {
  const origin = req.headers.origin;
  if (ALLOWED_ORIGINS.includes(origin)) {
    res.header("Access-Control-Allow-Origin", origin);
  }
  res.header("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
  if (req.method === "OPTIONS") {
    return res.sendStatus(200);
  }
  next();
});

function safeParseInt(value, fallback, max = 10000) {
  const n = parseInt(value, 10);
  if (isNaN(n) || n < 1) return fallback;
  return Math.min(n, max);
}

// API Key authentication
function authenticate(req, res, next) {
  const authHeader = req.headers.authorization;
  const providedKey = authHeader?.replace("Bearer ", "");

  if (providedKey !== API_KEY) {
    return res.status(401).json({
      status: "error",
      code: "unauthorized",
      message: "Invalid API key",
      next_action: "Provide Authorization: Bearer <api-key>."
    });
  }
  next();
}

function sendStructuredError(res, statusCode, code, message, nextAction = null, details = null) {
  const payload = {
    status: "error",
    code,
    message,
    next_action: nextAction,
  };
  if (details) payload.details = details;
  return res.status(statusCode).json(payload);
}

// Helper to extract response content
function extractContent(result) {
  if (result.content && result.content[0] && result.content[0].text) {
    try {
      return JSON.parse(result.content[0].text);
    } catch {
      return { text: result.content[0].text };
    }
  }
  return result;
}

// Root endpoint (no auth required)
app.get("/", (req, res) => {
  res.json({
    name: "Slack Web API Server",
    version: RELEASE_VERSION,
    status: "ok",
    code: "ok",
    message: "Web API server is running.",
    endpoints: [
      "GET  /health",
      "POST /refresh",
      "GET  /conversations",
      "GET  /conversations/:id/history",
      "GET  /conversations/:id/full",
      "GET  /conversations/:id/thread/:ts",
      "GET  /search",
      "POST /messages",
      "GET  /users",
      "GET  /users/:id",
      "POST /reactions",
      "DELETE /reactions",
      "POST /conversations/:id/mark",
      "GET  /conversations/unreads",
      "GET  /users/search",
    ],
    docs: "Add Authorization: Bearer <api-key> header to all requests"
  });
});

// Token status (detailed health + cache info)
app.get("/token-status", authenticate, async (req, res) => {
  try {
    const result = await handleTokenStatus();
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "token_status_failed", String(e?.message || e));
  }
});

// Health check
app.get("/health", authenticate, async (req, res) => {
  try {
    const result = await handleHealthCheck();
    const payload = extractContent(result);
    if (result.isError) {
      return res.status(400).json(payload);
    }
    res.json(payload);
  } catch (e) {
    sendStructuredError(res, 500, "health_check_failed", String(e?.message || e));
  }
});

// Refresh tokens
app.post("/refresh", authenticate, async (req, res) => {
  try {
    const result = await handleRefreshTokens();
    const payload = extractContent(result);
    if (result.isError) {
      return res.status(400).json(payload);
    }
    res.json(payload);
  } catch (e) {
    sendStructuredError(res, 500, "refresh_failed", String(e?.message || e));
  }
});

// List conversations
app.get("/conversations", authenticate, async (req, res) => {
  try {
    const result = await handleListConversations({
      types: req.query.types || "im,mpim",
      limit: safeParseInt(req.query.limit, 100)
    });
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "list_conversations_failed", String(e?.message || e));
  }
});

// Get unread conversations
app.get("/conversations/unreads", authenticate, async (req, res) => {
  try {
    const result = await handleConversationsUnreads({
      types: req.query.types || "im,mpim,public_channel,private_channel",
      limit: safeParseInt(req.query.limit, 50)
    });
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "unreads_failed", String(e?.message || e));
  }
});

// Get conversation history
app.get("/conversations/:id/history", authenticate, async (req, res) => {
  try {
    const result = await handleConversationsHistory({
      channel_id: req.params.id,
      limit: safeParseInt(req.query.limit, 50),
      oldest: req.query.oldest,
      latest: req.query.latest,
      resolve_users: req.query.resolve_users !== "false"
    });
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "history_failed", String(e?.message || e));
  }
});

// Get full conversation with threads
app.get("/conversations/:id/full", authenticate, async (req, res) => {
  try {
    const result = await handleGetFullConversation({
      channel_id: req.params.id,
      oldest: req.query.oldest,
      latest: req.query.latest,
      max_messages: safeParseInt(req.query.max_messages, 2000, 50000),
      include_threads: req.query.include_threads !== "false",
      output_file: req.query.output_file
    });
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "full_export_failed", String(e?.message || e));
  }
});

// Get thread
app.get("/conversations/:id/thread/:ts", authenticate, async (req, res) => {
  try {
    const result = await handleGetThread({
      channel_id: req.params.id,
      thread_ts: req.params.ts
    });
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "thread_fetch_failed", String(e?.message || e));
  }
});

// Mark conversation as read
app.post("/conversations/:id/mark", authenticate, async (req, res) => {
  try {
    if (!req.body.timestamp) {
      return sendStructuredError(
        res,
        400,
        "invalid_request",
        "timestamp is required",
        "Include timestamp in request JSON."
      );
    }
    const result = await handleConversationsMark({
      channel_id: req.params.id,
      timestamp: req.body.timestamp
    });
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "mark_failed", String(e?.message || e));
  }
});

// Search messages
app.get("/search", authenticate, async (req, res) => {
  try {
    if (!req.query.q) {
      return sendStructuredError(
        res,
        400,
        "invalid_request",
        "Query parameter 'q' is required",
        "Set the q query string and retry."
      );
    }
    const result = await handleSearchMessages({
      query: req.query.q,
      count: safeParseInt(req.query.count, 20)
    });
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "search_failed", String(e?.message || e));
  }
});

// Send message
app.post("/messages", authenticate, async (req, res) => {
  try {
    if (!req.body.channel_id || !req.body.text) {
      return sendStructuredError(
        res,
        400,
        "invalid_request",
        "channel_id and text are required",
        "Include channel_id and text in request JSON."
      );
    }
    const result = await handleSendMessage({
      channel_id: req.body.channel_id,
      text: req.body.text,
      thread_ts: req.body.thread_ts
    });
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "send_message_failed", String(e?.message || e));
  }
});

// List users
app.get("/users", authenticate, async (req, res) => {
  try {
    const result = await handleListUsers({
      limit: safeParseInt(req.query.limit, 100)
    });
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "list_users_failed", String(e?.message || e));
  }
});

// Search users (must be registered before /users/:id to avoid Express matching "search" as an ID)
app.get("/users/search", authenticate, async (req, res) => {
  try {
    if (!req.query.q) {
      return sendStructuredError(
        res,
        400,
        "invalid_request",
        "Query parameter 'q' is required",
        "Set the q query string and retry."
      );
    }
    const result = await handleUsersSearch({
      query: req.query.q,
      limit: safeParseInt(req.query.limit, 20)
    });
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "user_search_failed", String(e?.message || e));
  }
});

// Get user info
app.get("/users/:id", authenticate, async (req, res) => {
  try {
    const result = await handleUsersInfo({
      user_id: req.params.id
    });
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "user_info_failed", String(e?.message || e));
  }
});

// Add reaction
app.post("/reactions", authenticate, async (req, res) => {
  try {
    if (!req.body.channel_id || !req.body.timestamp || !req.body.reaction) {
      return sendStructuredError(
        res,
        400,
        "invalid_request",
        "channel_id, timestamp, and reaction are required",
        "Include channel_id, timestamp, and reaction in request JSON."
      );
    }
    const result = await handleAddReaction({
      channel_id: req.body.channel_id,
      timestamp: req.body.timestamp,
      reaction: req.body.reaction
    });
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "add_reaction_failed", String(e?.message || e));
  }
});

// Remove reaction
app.delete("/reactions", authenticate, async (req, res) => {
  try {
    if (!req.body.channel_id || !req.body.timestamp || !req.body.reaction) {
      return sendStructuredError(
        res,
        400,
        "invalid_request",
        "channel_id, timestamp, and reaction are required",
        "Include channel_id, timestamp, and reaction in request JSON."
      );
    }
    const result = await handleRemoveReaction({
      channel_id: req.body.channel_id,
      timestamp: req.body.timestamp,
      reaction: req.body.reaction
    });
    res.json(extractContent(result));
  } catch (e) {
    sendStructuredError(res, 500, "remove_reaction_failed", String(e?.message || e));
  }
});

// Start server
async function main() {
  // Check for credentials
  const credentials = loadTokensReadOnly();
  if (!credentials) {
    console.error("WARNING: No Slack credentials found");
    console.error("Run: npx -y @jtalk22/slack-mcp --setup");
  } else {
    console.log(`Credentials loaded from: ${credentials.source}`);
  }

  // Bind to localhost only - prevents access from other devices on the network
  app.listen(PORT, '127.0.0.1', () => {
    // Print to stderr to keep logs clean (stdout reserved for JSON in some setups)
    console.error(`\n${"═".repeat(60)}`);
    console.error(`  Slack Web API Server v${RELEASE_VERSION}`);
    console.error(`${"═".repeat(60)}`);
    console.error(`\n  Dashboard: http://localhost:${PORT}/?key=${API_KEY.slice(0, 8)}...`);
    console.error(`\n  API Key:   ${API_KEY.slice(0, 8)}${"*".repeat(12)}`);
    console.error(`\n  curl -H "Authorization: Bearer <key>" http://localhost:${PORT}/health`);
    console.error(`\n  Security: Bound to localhost only (127.0.0.1)`);
    console.error(`\n${"═".repeat(60)}\n`);
  });
}

main().catch(e => {
  console.error("Fatal error:", e);
  process.exit(1);
});
