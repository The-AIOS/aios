/**
 * Shared MCP server factory.
 *
 * Both transports — stdio (src/server.js) and Streamable HTTP
 * (src/server-http.js) — build their protocol server here, so the advertised
 * surface, the prompts, the resources, and the dispatch path cannot drift
 * between them. The factory is also what the tests drive in-process.
 *
 * The server speaks MCP 2026-07-28 and every 2025 revision from the same
 * instance: the SDK selects the era per connection (stdio) or per request
 * (HTTP), and the handlers registered here are written once for both.
 */

import { Server } from "@modelcontextprotocol/server";

import { RELEASE_VERSION } from "./public-metadata.js";
import { getActiveToolProfile } from "./tools.js";
import {
  TOOL_HANDLERS,
  handleHealthCheck,
  handleListConversations,
} from "./handlers.js";
import { isAuthDeath, lifeboatResponse } from "./lifeboat.js";

export const SERVER_NAME = "slack-mcp-server";
export const SERVER_VERSION = RELEASE_VERSION;

// tools/list is static for the life of a process (the profile is resolved once
// at startup and TOOLS is a constant), so the 2026-07-28 cache hint can say so:
// a shared cache may hold it for a minute. Responses to 2025-era requests never
// carry cache fields, so this is invisible to older clients.
export const TOOLS_LIST_CACHE_HINT = Object.freeze({ ttlMs: 60_000, cacheScope: "public" });

// MCP Prompts - predefined prompt templates for common Slack operations
export const PROMPTS = [
  {
    name: "search-recent",
    description: "Search workspace for messages from the past week",
    arguments: [
      {
        name: "query",
        description: "Search terms to look for",
        required: true
      }
    ]
  },
  {
    name: "summarize-channel",
    description: "Get recent activity from a channel for summarization",
    arguments: [
      {
        name: "channel_id",
        description: "Channel ID to summarize",
        required: true
      },
      {
        name: "days",
        description: "Number of days to look back (default 7)",
        required: false
      }
    ]
  },
  {
    name: "find-messages-from",
    description: "Find all messages from a specific user",
    arguments: [
      {
        name: "username",
        description: "Username or display name to search for",
        required: true
      }
    ]
  }
];

// MCP Resources - data sources the server provides
export const RESOURCES = [
  {
    uri: "slack://workspace/info",
    name: "Workspace Info",
    description: "Current workspace name, team, and authenticated user",
    mimeType: "application/json"
  },
  {
    uri: "slack://conversations/list",
    name: "Conversations",
    description: "List of available channels and DMs",
    mimeType: "application/json"
  }
];

function errorResult(code, message, nextAction) {
  return {
    content: [{
      type: "text",
      text: JSON.stringify({ status: "error", code, message, next_action: nextAction }, null, 2)
    }],
    isError: true
  };
}

/**
 * Dispatch one tools/call through the shared handler map. Exported so the
 * transports and the tests share a single failure contract.
 */
export async function dispatchToolCall(name, args) {
  const handler = TOOL_HANDLERS[name];
  if (!handler) {
    return errorResult("unknown_tool", `Unknown tool: ${name}`, "Use tools/list to discover available tools.");
  }
  try {
    return await handler(args);
  } catch (error) {
    // OAuth Lifeboat: dead session token → recovery guidance, not a raw error.
    if (isAuthDeath(error)) {
      return lifeboatResponse(error);
    }
    return errorResult("tool_call_failed", String(error?.message || error), "Retry the call and include full arguments.");
  }
}

function promptMessages(name, args) {
  switch (name) {
    case "search-recent": {
      const query = args?.query || "";
      const oneWeekAgo = Math.floor(Date.now() / 1000) - (7 * 24 * 60 * 60);
      return [{
        role: "user",
        content: {
          type: "text",
          text: `Search Slack for "${query}" from the past week. Use the slack_search_messages tool with query: "${query} after:${new Date(oneWeekAgo * 1000).toISOString().split('T')[0]}"`
        }
      }];
    }
    case "summarize-channel": {
      const channelId = args?.channel_id || "";
      const days = parseInt(args?.days, 10) || 7;
      const since = Math.floor(Date.now() / 1000) - (days * 24 * 60 * 60);
      return [{
        role: "user",
        content: {
          type: "text",
          text: `Get the last ${days} days of messages from channel ${channelId} and provide a summary. Use slack_conversations_history with channel_id: "${channelId}" and oldest: "${since}"`
        }
      }];
    }
    case "find-messages-from": {
      const username = args?.username || "";
      return [{
        role: "user",
        content: {
          type: "text",
          text: `Find messages from ${username}. Use slack_search_messages with query: "from:@${username}"`
        }
      }];
    }
    default:
      throw new Error(`Unknown prompt: ${name}`);
  }
}

async function readResource(uri) {
  switch (uri) {
    case "slack://workspace/info": {
      const result = await handleHealthCheck();
      return { contents: [{ uri, mimeType: "application/json", text: result.content[0].text }] };
    }
    case "slack://conversations/list": {
      const result = await handleListConversations({ types: "im,mpim,public_channel,private_channel", limit: 50 });
      return { contents: [{ uri, mimeType: "application/json", text: result.content[0].text }] };
    }
    default:
      throw new Error(`Unknown resource: ${uri}`);
  }
}

/**
 * Build a protocol server carrying the advertised tool surface plus the
 * prompts and resources. Cheap to construct — the HTTP entry builds one per
 * request (the 2026-07-28 stateless idiom) and stdio pins one per connection.
 *
 * @param {object} [options]
 * @param {Array} [options.tools] tools to advertise; defaults to the active profile
 */
export function createSlackMcpServer({ tools } = {}) {
  const advertised = tools ?? getActiveToolProfile().tools;

  const server = new Server(
    { name: SERVER_NAME, version: SERVER_VERSION },
    {
      capabilities: { tools: {}, prompts: {}, resources: {} },
      cacheHints: { "tools/list": TOOLS_LIST_CACHE_HINT },
    }
  );

  server.setRequestHandler("tools/list", async () => ({ tools: advertised }));
  server.setRequestHandler("tools/call", async (request) => {
    const { name, arguments: args } = request.params;
    return dispatchToolCall(name, args);
  });
  server.setRequestHandler("prompts/list", async () => ({ prompts: PROMPTS }));
  server.setRequestHandler("prompts/get", async (request) => ({
    messages: promptMessages(request.params.name, request.params.arguments)
  }));
  server.setRequestHandler("resources/list", async () => ({ resources: RESOURCES }));
  server.setRequestHandler("resources/read", async (request) => readResource(request.params.uri));

  return server;
}
