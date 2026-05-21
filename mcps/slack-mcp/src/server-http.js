#!/usr/bin/env node
/**
 * Slack MCP Server - HTTP Transport
 *
 * Streamable HTTP version for hosted deployments (Smithery, etc.)
 * Tokens provided via environment variables.
 */

import http from 'node:http';
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

import { TOOLS } from "../lib/tools.js";
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
import { RELEASE_VERSION } from "../lib/public-metadata.js";

const SERVER_NAME = "slack-mcp-server";
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
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, mcp-session-id");
  return allowOrigin;
}

// Create MCP server
const server = new Server(
  { name: SERVER_NAME, version: SERVER_VERSION },
  { capabilities: { tools: {} } }
);

// Register tool list handler
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS
}));

// Register tool call handler
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "slack_token_status":
        return await handleTokenStatus();
      case "slack_health_check":
        return await handleHealthCheck();
      case "slack_refresh_tokens":
        return await handleRefreshTokens();
      case "slack_list_conversations":
        return await handleListConversations(args);
      case "slack_conversations_history":
        return await handleConversationsHistory(args);
      case "slack_get_full_conversation":
        return await handleGetFullConversation(args);
      case "slack_search_messages":
        return await handleSearchMessages(args);
      case "slack_users_info":
        return await handleUsersInfo(args);
      case "slack_send_message":
        return await handleSendMessage(args);
      case "slack_get_thread":
        return await handleGetThread(args);
      case "slack_list_users":
        return await handleListUsers(args);
      case "slack_add_reaction":
        return await handleAddReaction(args);
      case "slack_remove_reaction":
        return await handleRemoveReaction(args);
      case "slack_conversations_mark":
        return await handleConversationsMark(args);
      case "slack_conversations_unreads":
        return await handleConversationsUnreads(args);
      case "slack_users_search":
        return await handleUsersSearch(args);
      default:
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              status: "error",
              code: "unknown_tool",
              message: `Unknown tool: ${name}`,
              next_action: "Call tools/list to inspect available tool names."
            }, null, 2)
          }],
          isError: true
        };
    }
  } catch (error) {
    return {
      content: [{
        type: "text",
        text: JSON.stringify({
          status: "error",
          code: "tool_call_failed",
          message: String(error?.message || error),
          next_action: "Retry with validated input payload."
        }, null, 2)
      }],
      isError: true
    };
  }
});

// Create HTTP transport
const transport = new StreamableHTTPServerTransport({
  sessionIdGenerator: () => crypto.randomUUID(),
});

// Connect server to transport
await server.connect(transport);

// Create HTTP server
const httpServer = http.createServer(async (req, res) => {
  const allowOrigin = applyCors(req, res);

  if (req.method === 'OPTIONS') {
    if (!HTTP_INSECURE && req.headers?.origin && !allowOrigin) {
      res.writeHead(403, { "Content-Type": "application/json" });
      res.end(JSON.stringify(
        structuredError(
          "cors_origin_denied",
          "CORS origin is not allowed.",
          "Set SLACK_MCP_HTTP_ALLOWED_ORIGINS to a comma-separated allowlist."
        )
      ));
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
        res.writeHead(401, { "Content-Type": "application/json" });
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

    await transport.handleRequest(req, res);
    return;
  }

  res.writeHead(404);
  res.end('Not found');
});

httpServer.listen(PORT, () => {
  console.log(`${SERVER_NAME} v${SERVER_VERSION} HTTP server running on port ${PORT}`);
  console.log(`MCP endpoint: http://localhost:${PORT}/mcp`);
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
