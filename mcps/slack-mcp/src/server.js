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
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { pathToFileURL } from "node:url";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListPromptsRequestSchema,
  GetPromptRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

import { loadTokensReadOnly } from "../lib/token-store.js";
import { RELEASE_VERSION } from "../lib/public-metadata.js";
import { checkTokenHealth } from "../lib/slack-client.js";
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

// Background refresh interval (4 hours)
const BACKGROUND_REFRESH_INTERVAL = 4 * 60 * 60 * 1000;

// Package info
const SERVER_NAME = "slack-mcp-server";
const SERVER_VERSION = RELEASE_VERSION;

// MCP Prompts - predefined prompt templates for common Slack operations
const PROMPTS = [
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
const RESOURCES = [
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

// Initialize server
const server = new Server(
  { name: SERVER_NAME, version: SERVER_VERSION },
  { capabilities: { tools: {}, prompts: {}, resources: {} } }
);

// Register tool list handler
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS
}));

// Register prompts handlers
server.setRequestHandler(ListPromptsRequestSchema, async () => ({
  prompts: PROMPTS
}));

server.setRequestHandler(GetPromptRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  switch (name) {
    case "search-recent": {
      const query = args?.query || "";
      const oneWeekAgo = Math.floor(Date.now() / 1000) - (7 * 24 * 60 * 60);
      return {
        messages: [
          {
            role: "user",
            content: {
              type: "text",
              text: `Search Slack for "${query}" from the past week. Use the slack_search_messages tool with query: "${query} after:${new Date(oneWeekAgo * 1000).toISOString().split('T')[0]}"`
            }
          }
        ]
      };
    }
    case "summarize-channel": {
      const channelId = args?.channel_id || "";
      const days = parseInt(args?.days) || 7;
      const since = Math.floor(Date.now() / 1000) - (days * 24 * 60 * 60);
      return {
        messages: [
          {
            role: "user",
            content: {
              type: "text",
              text: `Get the last ${days} days of messages from channel ${channelId} and provide a summary. Use slack_conversations_history with channel_id: "${channelId}" and oldest: "${since}"`
            }
          }
        ]
      };
    }
    case "find-messages-from": {
      const username = args?.username || "";
      return {
        messages: [
          {
            role: "user",
            content: {
              type: "text",
              text: `Find messages from ${username}. Use slack_search_messages with query: "from:@${username}"`
            }
          }
        ]
      };
    }
    default:
      throw new Error(`Unknown prompt: ${name}`);
  }
});

// Register resources handlers
server.setRequestHandler(ListResourcesRequestSchema, async () => ({
  resources: RESOURCES
}));

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const { uri } = request.params;

  switch (uri) {
    case "slack://workspace/info": {
      const result = await handleHealthCheck();
      return {
        contents: [
          {
            uri,
            mimeType: "application/json",
            text: result.content[0].text
          }
        ]
      };
    }
    case "slack://conversations/list": {
      const result = await handleListConversations({ types: "im,mpim,public_channel,private_channel", limit: 50 });
      return {
        contents: [
          {
            uri,
            mimeType: "application/json",
            text: result.content[0].text
          }
        ]
      };
    }
    default:
      throw new Error(`Unknown resource: ${uri}`);
  }
});

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
              next_action: "Use tools/list to discover available tools."
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
          next_action: "Retry the call and include full arguments."
        }, null, 2)
      }],
      isError: true
    };
  }
});

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
  // Use unref() so this timer doesn't prevent the process from exiting
  // when the MCP transport closes (prevents zombie processes)
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

  // Start server
  const transport = new StdioServerTransport();
  await server.connect(transport);
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
  return server;
}
