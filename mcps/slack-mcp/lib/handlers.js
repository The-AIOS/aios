/**
 * Tool Handlers
 *
 * Implementation of all MCP tool handlers.
 */

import { writeFileSync, readFileSync, existsSync, renameSync, unlinkSync, mkdirSync } from "fs";
import { execSync } from "child_process";
import { homedir, platform } from "os";
import { join } from "path";
import {
  loadTokensReadOnly,
  saveTokens,
  extractFromChrome,
  isAutoRefreshAvailable,
  getLastExtractionError
} from "./token-store.js";
import { slackAPI, resolveUser, formatTimestamp, sleep, checkTokenHealth, getUserCacheStats } from "./slack-client.js";

// ============ Utilities ============

/**
 * Robust boolean parser for LLM input unpredictability
 * Handles: true, "true", "True", "1", 1, "yes", etc.
 */
function parseBool(val) {
  if (typeof val === 'boolean') return val;
  if (typeof val === 'number') return val !== 0;
  if (typeof val === 'string') {
    return ['true', '1', 'yes', 'on'].includes(val.toLowerCase());
  }
  return false;
}

function asMcpJson(payload, isError = false) {
  return {
    content: [{
      type: "text",
      text: JSON.stringify(payload, null, 2)
    }],
    ...(isError ? { isError: true } : {})
  };
}

/**
 * Atomic write to prevent file corruption from concurrent writes
 */
function atomicWriteSync(filePath, content) {
  const tempPath = `${filePath}.${process.pid}.tmp`;
  try {
    writeFileSync(tempPath, content);
    if (platform() === 'darwin' || platform() === 'linux') {
      try { execSync(`chmod 600 "${tempPath}"`); } catch {}
    }
    renameSync(tempPath, filePath);
  } catch (e) {
    try { unlinkSync(tempPath); } catch {}
    throw e;
  }
}

// ============ DM Cache ============
const DM_CACHE_FILE = join(homedir(), ".slack-mcp-dm-cache.json");
const DM_CACHE_TTL = 24 * 60 * 60 * 1000; // 24 hours

function loadDMCache() {
  if (!existsSync(DM_CACHE_FILE)) return { dms: {}, updated: 0 };
  try {
    const data = JSON.parse(readFileSync(DM_CACHE_FILE, "utf-8"));
    // Check if cache is stale
    if (Date.now() - (data.updated || 0) > DM_CACHE_TTL) {
      return { dms: {}, updated: 0 };
    }
    return data;
  } catch {
    return { dms: {}, updated: 0 };
  }
}

function saveDMCache(dms) {
  try {
    const data = { dms, updated: Date.now() };
    atomicWriteSync(DM_CACHE_FILE, JSON.stringify(data, null, 2));
  } catch {
    // Ignore write errors - cache is optional
  }
}

/**
 * Token status handler - detailed token health info
 */
export async function handleTokenStatus() {
  const health = await checkTokenHealth({ error: () => {} });
  const cacheStats = getUserCacheStats();
  const dmCache = loadDMCache();
  const tokenStatus = health.reason === 'no_tokens'
    ? "missing"
    : health.age_state === "unknown"
      ? "unknown_age"
      : health.critical
        ? "critical"
        : health.warning
          ? "warning"
          : "healthy";

  return asMcpJson({
    status: tokenStatus,
    code: health.reason
      || (health.age_state === "unknown" ? "unknown_age" : null)
      || (health.critical ? "token_critical" : health.warning ? "token_warning" : "ok"),
    message: health.message,
    next_action: health.reason === 'no_tokens' ? "Run npx -y @jtalk22/slack-mcp --setup" : null,
    details: {
      age_known: health.age_known,
      age_state: health.age_state
    },
    token: {
      status: tokenStatus,
      age_hours: health.age_hours,
      source: health.source,
      updated_at: health.updated_at
    },
    auto_refresh: {
      enabled: isAutoRefreshAvailable(),
      interval: "4 hours",
      last_attempt: health.refreshed ? "just_now" : null,
      requires: isAutoRefreshAvailable() ? "Slack tab open in Chrome" : "Not supported on this platform"
    },
    cache: {
      users: cacheStats,
      dms: {
        count: Object.keys(dmCache.dms || {}).length,
        age_hours: dmCache.updated ? Math.round((Date.now() - dmCache.updated) / (60 * 60 * 1000) * 10) / 10 : null
      }
    }
  });
}

/**
 * Health check handler
 */
export async function handleHealthCheck() {
  const creds = loadTokensReadOnly();
  if (!creds) {
    return asMcpJson({
      status: "error",
      code: "missing_credentials",
      message: "No credentials found",
      next_action: "Run npx -y @jtalk22/slack-mcp --setup"
    }, true);
  }

  try {
    const result = await slackAPI("auth.test", {}, { retryOnAuthFail: false });
    return asMcpJson({
      status: "ok",
      code: "ok",
      message: "Slack auth valid",
      user: result.user,
      user_id: result.user_id,
      team: result.team,
      team_id: result.team_id,
      token_source: creds.source,
      token_updated: creds.updatedAt || null
    });
  } catch (e) {
    return asMcpJson({
      status: "error",
      code: "auth_failed",
      message: e.message,
      next_action: "Run npx -y @jtalk22/slack-mcp --setup"
    }, true);
  }
}

/**
 * Refresh tokens handler
 */
export async function handleRefreshTokens() {
  // Check platform support
  if (!isAutoRefreshAvailable()) {
    return asMcpJson({
      status: "error",
      code: "unsupported_platform",
      message: "Auto-refresh is only available on macOS.",
      next_action: "Manually update ~/.slack-mcp-tokens.json with SLACK_TOKEN and SLACK_COOKIE."
    }, true);
  }

  const chromeTokens = extractFromChrome();
  if (chromeTokens) {
    saveTokens(chromeTokens.token, chromeTokens.cookie);
    try {
      const result = await slackAPI("auth.test", {}, { retryOnAuthFail: false });
      return asMcpJson({
        status: "ok",
        code: "refreshed",
        message: "Tokens refreshed from Chrome.",
        user: result.user,
        team: result.team
      });
    } catch (e) {
      return asMcpJson({
        status: "error",
        code: "auth_failed_after_refresh",
        message: e.message,
        next_action: "Refresh Slack in Chrome and rerun slack_refresh_tokens."
      }, true);
    }
  }

  const extractionError = getLastExtractionError();
  if (extractionError?.code === "apple_events_javascript_disabled") {
    return asMcpJson({
      status: "error",
      code: extractionError.code,
      message: extractionError.message,
      detail: extractionError.detail,
      next_action: "In Chrome: View > Developer > Allow JavaScript from Apple Events, then retry."
    }, true);
  }

  return asMcpJson({
    status: "error",
    code: extractionError?.code || "chrome_extraction_failed",
    message: extractionError?.message || "Could not extract tokens from Chrome.",
    detail: extractionError?.detail || "Ensure Chrome is running with a logged-in Slack tab at app.slack.com.",
    next_action: "Open Slack in Chrome and run slack_refresh_tokens again."
  }, true);
}

/**
 * List conversations handler (with lazy DM discovery)
 */
export async function handleListConversations(args) {
  const types = args.types || "im,mpim";
  const wantsDMs = types.includes("im") || types.includes("mpim");
  const discoverDMs = parseBool(args.discover_dms); // Robust boolean parsing

  const result = await slackAPI("conversations.list", {
    types: types,
    limit: args.limit || 100,
    exclude_archived: true
  });

  const conversations = await Promise.all((result.channels || []).map(async (c) => {
    let displayName = c.name;
    if (c.is_im && c.user) {
      displayName = await resolveUser(c.user);
    }
    return {
      id: c.id,
      name: displayName,
      type: c.is_im ? "dm" : c.is_mpim ? "group_dm" : c.is_private ? "private_channel" : "public_channel",
      user_id: c.user
    };
  }));

  // Load cached DMs first (fast path)
  const dmCache = loadDMCache();
  for (const [channelId, data] of Object.entries(dmCache.dms || {})) {
    if (!conversations.find(c => c.id === channelId)) {
      conversations.push(data);
    }
  }

  // Only do expensive full DM discovery if explicitly requested
  // This avoids hitting rate limits on large workspaces
  if (wantsDMs && discoverDMs) {
    const newDMs = { ...dmCache.dms };
    let discoveredCount = 0;

    try {
      const usersResult = await slackAPI("users.list", { limit: 200 });
      for (const user of (usersResult.members || [])) {
        if (user.is_bot || user.id === "USLACKBOT" || user.deleted) continue;

        // Skip if we already have this user's DM
        const existingDM = conversations.find(c => c.user_id === user.id && c.type === "dm");
        if (existingDM) continue;

        // Try to open DM with this user
        try {
          const dmResult = await slackAPI("conversations.open", { users: user.id });
          if (dmResult.channel?.id) {
            const channelId = dmResult.channel.id;
            if (!conversations.find(c => c.id === channelId)) {
              const dmData = {
                id: channelId,
                name: user.real_name || user.name,
                type: "dm",
                user_id: user.id
              };
              conversations.push(dmData);
              newDMs[channelId] = dmData;
              discoveredCount++;
            }
          }
          // Rate limit protection
          await sleep(50);
        } catch (e) {
          // Skip users we can't DM
        }
      }
    } catch (e) {
      // If users.list fails, continue with what we have
    }

    // Save updated cache
    if (discoveredCount > 0) {
      saveDMCache(newDMs);
    }
  }

  return {
    content: [{
      type: "text",
      text: JSON.stringify({
        count: conversations.length,
        conversations,
        cached_dms: Object.keys(dmCache.dms || {}).length,
        hint: !discoverDMs && wantsDMs ? "Use discover_dms:true for full DM discovery (slower)" : undefined
      }, null, 2)
    }]
  };
}

/**
 * Conversations history handler
 */
export async function handleConversationsHistory(args) {
  const resolveUsers = args.resolve_users !== false;
  const result = await slackAPI("conversations.history", {
    channel: args.channel_id,
    limit: args.limit || 50,
    oldest: args.oldest,
    latest: args.latest,
    inclusive: true
  });

  const messages = await Promise.all((result.messages || []).map(async (msg) => {
    const userName = resolveUsers ? await resolveUser(msg.user) : msg.user;
    return {
      ts: msg.ts,
      user: userName,
      user_id: msg.user,
      text: msg.text || "",
      datetime: formatTimestamp(msg.ts),
      has_thread: !!msg.thread_ts && msg.reply_count > 0,
      reply_count: msg.reply_count
    };
  }));

  return {
    content: [{
      type: "text",
      text: JSON.stringify({
        channel: args.channel_id,
        message_count: messages.length,
        has_more: result.has_more,
        messages
      }, null, 2)
    }]
  };
}

/**
 * Full conversation export handler
 */
export async function handleGetFullConversation(args) {
  const maxMessages = Math.min(args.max_messages || 2000, 10000);
  const includeThreads = args.include_threads !== false;
  const allMessages = [];
  let cursor;
  let hasMore = true;

  // Fetch all messages with pagination
  while (hasMore && allMessages.length < maxMessages) {
    const result = await slackAPI("conversations.history", {
      channel: args.channel_id,
      limit: Math.min(100, maxMessages - allMessages.length),
      oldest: args.oldest,
      latest: args.latest,
      cursor,
      inclusive: true
    });

    for (const msg of result.messages || []) {
      const userName = await resolveUser(msg.user);
      const message = {
        ts: msg.ts,
        user: userName,
        user_id: msg.user,
        text: msg.text || "",
        datetime: formatTimestamp(msg.ts),
        replies: []
      };

      // Fetch thread replies if present
      if (includeThreads && msg.reply_count > 0) {
        try {
          const threadResult = await slackAPI("conversations.replies", {
            channel: args.channel_id,
            ts: msg.ts
          });
          // Skip first message (parent)
          for (const reply of (threadResult.messages || []).slice(1)) {
            const replyUserName = await resolveUser(reply.user);
            message.replies.push({
              ts: reply.ts,
              user: replyUserName,
              text: reply.text || "",
              datetime: formatTimestamp(reply.ts)
            });
          }
          await sleep(50); // Rate limit
        } catch (e) {
          // Skip thread on error
        }
      }

      allMessages.push(message);
    }

    hasMore = result.has_more && result.response_metadata?.next_cursor;
    cursor = result.response_metadata?.next_cursor;
    if (hasMore) await sleep(100);
  }

  // Sort chronologically
  allMessages.sort((a, b) => parseFloat(a.ts) - parseFloat(b.ts));

  const output = {
    channel: args.channel_id,
    exported_at: new Date().toISOString(),
    total_messages: allMessages.length,
    date_range: {
      oldest: args.oldest ? formatTimestamp(args.oldest) : "beginning",
      latest: args.latest ? formatTimestamp(args.latest) : "now"
    },
    messages: allMessages
  };

  // Save to file if requested (restricted to ~/.slack-mcp-exports/ for security)
  if (args.output_file) {
    const exportDir = join(homedir(), '.slack-mcp-exports');
    // Ensure export directory exists
    try { mkdirSync(exportDir, { recursive: true }); } catch {}

    // Sanitize filename - remove any path traversal attempts
    const sanitizedName = args.output_file
      .replace(/^.*[\\\/]/, '')  // Remove any path components
      .replace(/\.\./g, '')       // Remove .. sequences
      .replace(/[<>:"|?*]/g, '') // Remove invalid chars
      || 'export.json';

    const outputPath = join(exportDir, sanitizedName);
    writeFileSync(outputPath, JSON.stringify(output, null, 2));
    output.saved_to = outputPath;
  }

  return { content: [{ type: "text", text: JSON.stringify(output, null, 2) }] };
}

/**
 * Search messages handler
 */
export async function handleSearchMessages(args) {
  const result = await slackAPI("search.messages", {
    query: args.query,
    count: args.count || 20,
    sort: "timestamp",
    sort_dir: "desc"
  });

  const matches = await Promise.all((result.messages?.matches || []).map(async (m) => ({
    ts: m.ts,
    channel: m.channel?.name || m.channel?.id,
    channel_id: m.channel?.id,
    user: await resolveUser(m.user),
    text: m.text,
    datetime: formatTimestamp(m.ts),
    permalink: m.permalink
  })));

  return {
    content: [{
      type: "text",
      text: JSON.stringify({
        query: args.query,
        total: result.messages?.total || 0,
        matches
      }, null, 2)
    }]
  };
}

/**
 * User info handler
 */
export async function handleUsersInfo(args) {
  const result = await slackAPI("users.info", { user: args.user_id });
  const user = result.user;
  return {
    content: [{
      type: "text",
      text: JSON.stringify({
        id: user.id,
        name: user.name,
        real_name: user.real_name,
        display_name: user.profile?.display_name,
        email: user.profile?.email,
        title: user.profile?.title,
        status_text: user.profile?.status_text,
        status_emoji: user.profile?.status_emoji,
        timezone: user.tz,
        is_bot: user.is_bot,
        is_admin: user.is_admin
      }, null, 2)
    }]
  };
}

/**
 * Send message handler
 */
export async function handleSendMessage(args) {
  const result = await slackAPI("chat.postMessage", {
    channel: args.channel_id,
    text: args.text,
    thread_ts: args.thread_ts
  });

  return {
    content: [{
      type: "text",
      text: JSON.stringify({
        status: "sent",
        channel: result.channel,
        ts: result.ts,
        thread_ts: args.thread_ts,
        message: result.message?.text
      }, null, 2)
    }]
  };
}

/**
 * Get thread handler
 */
export async function handleGetThread(args) {
  const result = await slackAPI("conversations.replies", {
    channel: args.channel_id,
    ts: args.thread_ts
  });

  const messages = await Promise.all((result.messages || []).map(async (msg) => ({
    ts: msg.ts,
    user: await resolveUser(msg.user),
    user_id: msg.user,
    text: msg.text || "",
    datetime: formatTimestamp(msg.ts),
    is_parent: msg.ts === args.thread_ts
  })));

  return {
    content: [{
      type: "text",
      text: JSON.stringify({
        channel: args.channel_id,
        thread_ts: args.thread_ts,
        message_count: messages.length,
        messages
      }, null, 2)
    }]
  };
}

/**
 * List users handler (with pagination support)
 */
export async function handleListUsers(args) {
  const maxUsers = args.limit || 500;
  const allUsers = [];
  let cursor;

  do {
    const result = await slackAPI("users.list", {
      limit: Math.min(200, maxUsers - allUsers.length),
      cursor
    });

    const users = (result.members || [])
      .filter(u => !u.deleted && !u.is_bot)
      .map(u => ({
        id: u.id,
        name: u.name,
        real_name: u.real_name,
        display_name: u.profile?.display_name,
        email: u.profile?.email,
        is_admin: u.is_admin
      }));

    allUsers.push(...users);
    cursor = result.response_metadata?.next_cursor;

    // Small delay between pagination requests
    if (cursor && allUsers.length < maxUsers) {
      await sleep(100);
    }
  } while (cursor && allUsers.length < maxUsers);

  return {
    content: [{
      type: "text",
      text: JSON.stringify({ count: allUsers.length, users: allUsers }, null, 2)
    }]
  };
}

/**
 * Add reaction handler
 */
export async function handleAddReaction(args) {
  await slackAPI("reactions.add", {
    channel: args.channel_id,
    timestamp: args.timestamp,
    name: args.reaction
  });

  return {
    content: [{
      type: "text",
      text: JSON.stringify({
        status: "added",
        channel: args.channel_id,
        timestamp: args.timestamp,
        reaction: args.reaction
      }, null, 2)
    }]
  };
}

/**
 * Remove reaction handler
 */
export async function handleRemoveReaction(args) {
  await slackAPI("reactions.remove", {
    channel: args.channel_id,
    timestamp: args.timestamp,
    name: args.reaction
  });

  return {
    content: [{
      type: "text",
      text: JSON.stringify({
        status: "removed",
        channel: args.channel_id,
        timestamp: args.timestamp,
        reaction: args.reaction
      }, null, 2)
    }]
  };
}

/**
 * Mark conversation as read handler
 */
export async function handleConversationsMark(args) {
  await slackAPI("conversations.mark", {
    channel: args.channel_id,
    ts: args.timestamp
  });

  return asMcpJson({
    status: "marked",
    channel: args.channel_id,
    read_up_to: args.timestamp
  });
}

/**
 * Unread conversations handler - returns channels/DMs with unread messages
 */
export async function handleConversationsUnreads(args) {
  const types = args.types || "im,mpim,public_channel,private_channel";
  const limit = args.limit || 50;

  const result = await slackAPI("conversations.list", {
    types,
    limit: 200,
    exclude_archived: true
  });

  // Filter to conversations with unreads and resolve names
  const unreads = [];
  for (const c of (result.channels || [])) {
    const unreadCount = c.unread_count_display || c.unread_count || 0;
    if (unreadCount === 0) continue;

    let displayName = c.name;
    if (c.is_im && c.user) {
      displayName = await resolveUser(c.user);
    }

    unreads.push({
      id: c.id,
      name: displayName,
      type: c.is_im ? "dm" : c.is_mpim ? "group_dm" : c.is_private ? "private_channel" : "public_channel",
      unread_count: unreadCount,
      latest_ts: c.latest?.ts || null
    });
  }

  // Sort by unread count descending
  unreads.sort((a, b) => b.unread_count - a.unread_count);

  return asMcpJson({
    total_unread_conversations: unreads.length,
    conversations: unreads.slice(0, limit)
  });
}

/**
 * Search users handler - client-side filter on users.list
 */
export async function handleUsersSearch(args) {
  const query = (args.query || "").toLowerCase();
  const limit = args.limit || 20;

  // Fetch all users (paginated)
  const allUsers = [];
  let cursor;

  do {
    const result = await slackAPI("users.list", {
      limit: 200,
      cursor
    });

    for (const u of (result.members || [])) {
      if (u.deleted || u.is_bot || u.id === "USLACKBOT") continue;

      const searchFields = [
        u.name,
        u.real_name,
        u.profile?.display_name,
        u.profile?.email
      ].filter(Boolean).map(s => s.toLowerCase());

      if (searchFields.some(f => f.includes(query))) {
        allUsers.push({
          id: u.id,
          name: u.name,
          real_name: u.real_name,
          display_name: u.profile?.display_name,
          email: u.profile?.email,
          title: u.profile?.title,
          is_admin: u.is_admin
        });
      }
    }

    cursor = result.response_metadata?.next_cursor;
    if (cursor) await sleep(100);
  } while (cursor && allUsers.length < 500);

  return asMcpJson({
    query: args.query,
    count: Math.min(allUsers.length, limit),
    total_matches: allUsers.length,
    users: allUsers.slice(0, limit)
  });
}
