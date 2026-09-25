/**
 * MCP Tool Definitions
 *
 * All Slack MCP tools in one place for easy maintenance.
 * Includes MCP annotations for better tool discovery and safety hints.
 */

export const TOOLS = [
  {
    name: "slack_token_status",
    description: "Check token health, age, auto-refresh status, and cache stats",
    inputSchema: {
      type: "object",
      properties: {}
    },
    annotations: {
      title: "Token Status",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: false
    }
  },
  {
    name: "slack_health_check",
    description: "Check if Slack tokens are valid and show authentication status",
    inputSchema: {
      type: "object",
      properties: {}
    },
    annotations: {
      title: "Health Check",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true
    }
  },
  {
    name: "slack_refresh_tokens",
    description: "Force refresh tokens by extracting from Chrome (requires Slack tab open in Chrome)",
    inputSchema: {
      type: "object",
      properties: {}
    },
    annotations: {
      title: "Refresh Tokens",
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    }
  },
  {
    name: "slack_list_conversations",
    description: "List all DMs and channels with user names resolved. Uses cached DMs by default for speed.",
    inputSchema: {
      type: "object",
      properties: {
        types: {
          type: "string",
          description: "Comma-separated types: im, mpim, public_channel, private_channel",
          default: "im,mpim"
        },
        limit: {
          type: "number",
          description: "Maximum results (default 100)"
        },
        discover_dms: {
          type: "boolean",
          description: "If true, actively discover all DMs (slower, may hit rate limits on large workspaces). Default false uses cached DMs."
        }
      }
    },
    annotations: {
      title: "List Conversations",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true
    }
  },
  {
    name: "slack_conversations_history",
    description: "Get messages from a channel or DM with user names resolved",
    inputSchema: {
      type: "object",
      properties: {
        channel_id: {
          type: "string",
          description: "Channel or DM ID (e.g., D063M4403MW)"
        },
        limit: {
          type: "number",
          description: "Messages to fetch (max 100, default 50)"
        },
        oldest: {
          type: "string",
          description: "Unix timestamp - get messages after this time (boundary timestamp included)"
        },
        latest: {
          type: "string",
          description: "Unix timestamp - get messages before this time (boundary timestamp included)"
        },
        resolve_users: {
          type: "boolean",
          description: "Convert user IDs to names (default true)"
        },
        include_rich_message_fields: {
          type: "boolean",
          description: "Include Slack message attachments, blocks, metadata, files, and reactions when present"
        },
        include_all_metadata: {
          type: "boolean",
          description: "Pass Slack's include_all_metadata option to conversations.history"
        }
      },
      required: ["channel_id"]
    },
    annotations: {
      title: "Conversation History",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true
    }
  },
  {
    name: "slack_get_full_conversation",
    description: "Export FULL conversation history with all messages, threads, and user names. Can save to file.",
    inputSchema: {
      type: "object",
      properties: {
        channel_id: {
          type: "string",
          description: "Channel or DM ID"
        },
        oldest: {
          type: "string",
          description: "Unix timestamp start (e.g., 1733011200 = Dec 1, 2025; boundary timestamp included)"
        },
        latest: {
          type: "string",
          description: "Unix timestamp end (boundary timestamp included)"
        },
        max_messages: {
          type: "number",
          description: "Maximum messages to retrieve (default 2000, max 10000)"
        },
        include_threads: {
          type: "boolean",
          description: "Fetch thread replies (default true)"
        },
        include_rich_message_fields: {
          type: "boolean",
          description: "Include Slack message attachments, blocks, metadata, files, and reactions when present"
        },
        include_all_metadata: {
          type: "boolean",
          description: "Pass Slack's include_all_metadata option to conversations.history and conversations.replies"
        },
        output_file: {
          type: "string",
          description: "Filename to save export (saved to ~/.slack-mcp-exports/)"
        }
      },
      required: ["channel_id"]
    },
    annotations: {
      title: "Full Conversation Export",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true
    }
  },
  {
    name: "slack_search_messages",
    description: "Search messages across the Slack workspace",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Search query (supports Slack syntax like from:@user, in:#channel)"
        },
        count: {
          type: "number",
          description: "Number of results (max 100, default 20)"
        },
        include_rich_message_fields: {
          type: "boolean",
          description: "Include Slack message attachments, blocks, metadata, files, and reactions when present"
        }
      },
      required: ["query"]
    },
    annotations: {
      title: "Search Messages",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true
    }
  },
  {
    name: "slack_users_info",
    description: "Get detailed information about a Slack user",
    inputSchema: {
      type: "object",
      properties: {
        user_id: {
          type: "string",
          description: "Slack user ID"
        }
      },
      required: ["user_id"]
    },
    annotations: {
      title: "User Info",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true
    }
  },
  {
    name: "slack_send_message",
    description: "Send a message to a channel or DM",
    inputSchema: {
      type: "object",
      properties: {
        channel_id: {
          type: "string",
          description: "Channel or DM ID to send to"
        },
        text: {
          type: "string",
          description: "Message text (supports Slack markdown)"
        },
        thread_ts: {
          type: "string",
          description: "Thread timestamp to reply to (optional)"
        }
      },
      required: ["channel_id", "text"]
    },
    annotations: {
      title: "Send Message",
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: false,
      openWorldHint: true
    }
  },
  {
    name: "slack_get_thread",
    description: "Get all replies in a message thread",
    inputSchema: {
      type: "object",
      properties: {
        channel_id: {
          type: "string",
          description: "Channel or DM ID"
        },
        thread_ts: {
          type: "string",
          description: "Thread parent message timestamp"
        },
        include_rich_message_fields: {
          type: "boolean",
          description: "Include Slack message attachments, blocks, metadata, files, and reactions when present"
        },
        include_all_metadata: {
          type: "boolean",
          description: "Pass Slack's include_all_metadata option to conversations.replies"
        }
      },
      required: ["channel_id", "thread_ts"]
    },
    annotations: {
      title: "Get Thread",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true
    }
  },
  {
    name: "slack_list_users",
    description: "List all users in the workspace",
    inputSchema: {
      type: "object",
      properties: {
        limit: {
          type: "number",
          description: "Maximum users to return (default 500, supports pagination)"
        }
      }
    },
    annotations: {
      title: "List Users",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true
    }
  },
  {
    name: "slack_add_reaction",
    description: "Add an emoji reaction to a message",
    inputSchema: {
      type: "object",
      properties: {
        channel_id: {
          type: "string",
          description: "Channel or DM ID containing the message"
        },
        timestamp: {
          type: "string",
          description: "Message timestamp to react to"
        },
        reaction: {
          type: "string",
          description: "Emoji name without colons (e.g., 'thumbsup', 'eyes', 'white_check_mark')"
        }
      },
      required: ["channel_id", "timestamp", "reaction"]
    },
    annotations: {
      title: "Add Reaction",
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true
    }
  },
  {
    name: "slack_remove_reaction",
    description: "Remove an emoji reaction from a message",
    inputSchema: {
      type: "object",
      properties: {
        channel_id: {
          type: "string",
          description: "Channel or DM ID containing the message"
        },
        timestamp: {
          type: "string",
          description: "Message timestamp to remove reaction from"
        },
        reaction: {
          type: "string",
          description: "Emoji name without colons (e.g., 'thumbsup', 'eyes')"
        }
      },
      required: ["channel_id", "timestamp", "reaction"]
    },
    annotations: {
      title: "Remove Reaction",
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true
    }
  },
  {
    name: "slack_conversations_mark",
    description: "Mark a conversation as read up to a specific message timestamp",
    inputSchema: {
      type: "object",
      properties: {
        channel_id: {
          type: "string",
          description: "Channel or DM ID to mark as read"
        },
        timestamp: {
          type: "string",
          description: "Message timestamp to mark as read up to (all messages at or before this are marked read)"
        }
      },
      required: ["channel_id", "timestamp"]
    },
    annotations: {
      title: "Mark as Read",
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true
    }
  },
  {
    name: "slack_conversations_unreads",
    description: "Get channels and DMs with unread messages, sorted by unread count (highest first)",
    inputSchema: {
      type: "object",
      properties: {
        types: {
          type: "string",
          description: "Comma-separated types: im, mpim, public_channel, private_channel (default all)",
          default: "im,mpim,public_channel,private_channel"
        },
        limit: {
          type: "number",
          description: "Maximum conversations to return (default 50)"
        }
      }
    },
    annotations: {
      title: "Unread Conversations",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true
    }
  },
  {
    name: "slack_users_search",
    description: "Search workspace users by name, display name, or email. Case-insensitive partial match.",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Search term to match against name, display name, real name, or email"
        },
        limit: {
          type: "number",
          description: "Maximum results to return (default 20)"
        }
      },
      required: ["query"]
    },
    annotations: {
      title: "Search Users",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: true
    }
  },
  // ============ Workflow Profile Primitives ============
  // Local JSON storage at ~/.slack-mcp-workflows.json. A profile is the scope
  // slack_catch_me_up reads: channels, priority people, and the cadence window.
  {
    name: "slack_workflow_save",
    description: "Save or update a workflow profile that binds a workflow_kind (support_inbox | incident_room | exec_brief | product_launch_watch | custom) to channels, priority people, retention mode, and summary cadence. Stored locally at ~/.slack-mcp-workflows.json. slack_catch_me_up reads the profile by name and returns evidence shaped by its workflow_kind.",
    inputSchema: {
      type: "object",
      properties: {
        profile_name: {
          type: "string",
          description: "Unique name for this workflow profile (e.g. 'morning-exec-brief', 'on-call-rotation')"
        },
        workflow_kind: {
          type: "string",
          enum: ["support_inbox", "incident_room", "exec_brief", "product_launch_watch", "custom"],
          description: "Workflow kind. Determines the output_contract keys slack_catch_me_up returns for this profile."
        },
        channels: {
          type: "array",
          items: { type: "string" },
          description: "Slack channel IDs to read (e.g. ['C012345', 'C067890'])"
        },
        priority_people: {
          type: "array",
          items: { type: "string" },
          description: "Slack user IDs whose messages get extra weight in summaries"
        },
        retention_mode: {
          type: "string",
          enum: ["ephemeral", "persistent"],
          description: "Retention preference recorded on the profile. Default ephemeral."
        },
        summary_cadence: {
          type: "string",
          enum: ["on_demand", "daily_8am", "weekly_monday"],
          description: "How often this profile expects to be caught up on. Sets slack_catch_me_up's default window: 24 hours for on_demand and daily_8am, 7 days for weekly_monday."
        }
      },
      required: ["profile_name", "workflow_kind"]
    },
    annotations: {
      title: "Save Workflow Profile",
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false
    }
  },
  {
    name: "slack_workflows",
    description: "List all saved workflow profiles from ~/.slack-mcp-workflows.json. Optionally filter by workflow_kind. Returns profile_name, channels, priority_people, retention_mode, summary_cadence, structured_keys, created_at, updated_at.",
    inputSchema: {
      type: "object",
      properties: {
        workflow_kind: {
          type: "string",
          enum: ["support_inbox", "incident_room", "exec_brief", "product_launch_watch", "custom"],
          description: "Optional filter — return only profiles of this workflow_kind"
        }
      }
    },
    annotations: {
      title: "List Workflow Profiles",
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: false
    }
  },
  {
    name: "slack_catch_me_up",
    description: "Catch up on a saved workflow profile. Reads the profile's channels (or everything currently unread if the profile names none), pulls messages since the cadence window or an explicit `since`, expands active threads, and returns structured evidence: which threads are unanswered and for how long, what the profile's priority people said or were pinned on, and which conversations moved most. Runs locally against your own session — no hosted account, no server-side model. The response carries an `output_contract` naming the keys to compose for this workflow_kind; write the summary from the returned `signals` and `conversations`, citing conversation names and timestamps.",
    inputSchema: {
      type: "object",
      properties: {
        profile_name: {
          type: "string",
          description: "Name of a workflow profile saved via slack_workflow_save (list them with slack_workflows)"
        },
        since: {
          type: "string",
          description: "Optional ISO 8601 timestamp — only consider messages newer than this. Defaults to the profile's cadence window: 24 hours for on_demand and daily_8am, 7 days for weekly_monday."
        }
      },
      required: ["profile_name"]
    },
    annotations: {
      title: "Catch Me Up",
      readOnlyHint: true,
      idempotentHint: false,
      openWorldHint: false
    }
  }
];

// ============ Tool Profiles (schema-cost control) ============
// The TOOLS array above is the canonical surface — drift-guarded byte-for-byte
// against TOOL_HANDLERS. A client pays for the full tool schema on every turn
// that carries it, so a client that only needs the core job can advertise a
// smaller slice and cut that per-turn cost. Selection is opt-in via
// SLACK_MCP_TOOLS=essentials|read|all (or --tools=<comma,list,of,names>);
// the default stays "all" so existing installs are unchanged. Filtering only
// narrows the ADVERTISED list — every handler stays wired, so a client that
// calls a non-advertised tool by name still works.

// The six tools covering the common case: see what's unread, read a
// conversation, search the workspace, read a thread, resolve a person, reply.
export const ESSENTIALS_TOOLS = [
  "slack_conversations_unreads",
  "slack_conversations_history",
  "slack_search_messages",
  "slack_get_thread",
  "slack_users_search",
  "slack_send_message",
];

// The 12 read-only Slack operations, matching the README's read-only table.
// Deliberately NOT derived from readOnlyHint: that annotation is an MCP safety
// signal, not a surface-selection signal — it was once also true of tools that
// made no Slack call at all, and deriving from it shipped them to people who
// had narrowed their surface. An explicit list cannot drift that way.
// slack_refresh_tokens is included: it reads Slack and writes only local
// credential state.
export const READ_TOOLS = [
  "slack_health_check",
  "slack_token_status",
  "slack_refresh_tokens",
  "slack_list_conversations",
  "slack_conversations_history",
  "slack_get_full_conversation",
  "slack_search_messages",
  "slack_get_thread",
  "slack_users_info",
  "slack_list_users",
  "slack_users_search",
  "slack_conversations_unreads",
];

const TOOLS_BY_NAME = new Map(TOOLS.map((tool) => [tool.name, tool]));

/** Names of every tool annotated readOnlyHint: true, in canonical order. */
export function readOnlyToolNames() {
  return TOOLS.filter((tool) => tool.annotations?.readOnlyHint === true).map((tool) => tool.name);
}

/**
 * Resolve a raw profile string into the tools to advertise.
 *
 * Accepts "all" (default), "read", "essentials", or a comma-separated custom
 * allow-list of exact tool names. Unknown names in a custom list are dropped
 * with a warning; a value that matches nothing at all falls back to "all"
 * rather than crashing — a mis-set filter must never silently strip Slack
 * access to zero tools. Returns { profile, tools, dropped, warning }.
 */
export function resolveToolProfile(rawValue) {
  const raw = (rawValue == null ? "" : String(rawValue)).trim();
  const lowered = raw.toLowerCase();

  if (!raw || lowered === "all") {
    return { profile: "all", tools: TOOLS, dropped: [], warning: null };
  }
  if (lowered === "essentials" || lowered === "essential") {
    return {
      profile: "essentials",
      tools: TOOLS.filter((tool) => ESSENTIALS_TOOLS.includes(tool.name)),
      dropped: [],
      warning: null,
    };
  }
  if (lowered === "read" || lowered === "read-only" || lowered === "readonly") {
    return {
      profile: "read",
      tools: TOOLS.filter((tool) => READ_TOOLS.includes(tool.name)),
      dropped: [],
      warning: null,
    };
  }

  // Custom comma-separated allow-list of exact tool names.
  const requested = raw.split(",").map((name) => name.trim()).filter(Boolean);
  const keptNames = new Set();
  const dropped = [];
  for (const name of requested) {
    if (TOOLS_BY_NAME.has(name)) {
      keptNames.add(name);
    } else {
      dropped.push(name);
    }
  }
  if (keptNames.size === 0) {
    return {
      profile: "all",
      tools: TOOLS,
      dropped,
      warning: `SLACK_MCP_TOOLS="${raw}" matched no known tools (unknown: ${dropped.join(", ") || "none"}); advertising all ${TOOLS.length}.`,
    };
  }
  return {
    profile: "custom",
    tools: TOOLS.filter((tool) => keptNames.has(tool.name)), // canonical order
    dropped,
    warning: dropped.length
      ? `SLACK_MCP_TOOLS custom list dropped unknown tool(s): ${dropped.join(", ")}.`
      : null,
  };
}

/**
 * Read the active tool profile from CLI argv (--tools=… / --tools …) and the
 * SLACK_MCP_TOOLS environment variable, argv taking precedence. Adds a `source`
 * field ("cli" | "env" | "default") to the resolveToolProfile result.
 */
export function getActiveToolProfile(argv = process.argv, env = process.env) {
  let cliValue = null;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--tools") {
      // A following option is a missing operand, not the value — never consume
      // `--setup` or `--profile=work` as a tool profile. cli.js rejects this at
      // launch; here we fall through to the environment.
      const next = argv[i + 1];
      cliValue = next === undefined || next.startsWith("--") ? null : next;
    } else if (arg.startsWith("--tools=")) {
      cliValue = arg.slice("--tools=".length);
    }
  }
  const raw = cliValue !== null ? cliValue : (env.SLACK_MCP_TOOLS ?? "");
  const source = cliValue !== null ? "cli" : (env.SLACK_MCP_TOOLS ? "env" : "default");
  return { ...resolveToolProfile(raw), source };
}

/** Convenience: just the resolved tool array for the current process. */
export function getActiveTools(argv, env) {
  return getActiveToolProfile(argv, env).tools;
}
