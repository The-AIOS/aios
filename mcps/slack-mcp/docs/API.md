# API Reference

## Tools

### slack_health_check

Check if Slack tokens are valid.

**Parameters:** None

**Returns:**
```json
{
  "status": "ok",
  "code": "ok",
  "message": "Slack auth valid",
  "user": "james",
  "team": "Rêvasser",
  "token_source": "environment",
  "token_updated": "2026-01-03T00:00:00Z"
}
```

---

### slack_token_status

Get detailed token health, age, and cache statistics.

**Parameters:** None

**Returns:**
```json
{
  "status": "healthy",
  "code": "ok",
  "message": "Token is healthy",
  "next_action": null,
  "token": {
    "status": "healthy",
    "age_hours": 2.5,
    "source": "file",
    "updated_at": "2026-01-08T12:00:00Z"
  },
  "auto_refresh": {
    "enabled": true,
    "interval": "4 hours",
    "requires": "Slack tab open in Chrome"
  },
  "cache": {
    "users": { "size": 25, "maxSize": 500, "ttlMs": 3600000 },
    "dms": { "count": 10, "age_hours": 1.2 }
  }
}
```

---

### slack_refresh_tokens

Force refresh tokens from Chrome.

**Prerequisites:** Chrome must be running with a Slack tab open (app.slack.com).

**Parameters:** None

**Returns:**
```json
{
  "status": "ok",
  "code": "refreshed",
  "message": "Tokens refreshed from Chrome.",
  "user": "james",
  "team": "Rêvasser"
}
```

---

### slack_list_conversations

List all DMs and channels.

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| types | string | "im,mpim" | Conversation types to include |
| limit | number | 100 | Maximum results |

**Types:**
- `im` - Direct messages
- `mpim` - Group DMs
- `public_channel` - Public channels
- `private_channel` - Private channels

**Returns:**
```json
{
  "count": 5,
  "conversations": [
    {
      "id": "D063M4403MW",
      "name": "Gwen Santos",
      "type": "dm",
      "user_id": "U05GPEVH7J9"
    }
  ]
}
```

---

### slack_conversations_history

Get messages from a channel or DM.

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| channel_id | string | *required* | Channel or DM ID |
| limit | number | 50 | Messages to fetch (max 100) |
| oldest | string | - | Unix timestamp, get messages after; matching boundary timestamp is included |
| latest | string | - | Unix timestamp, get messages before; matching boundary timestamp is included |
| resolve_users | boolean | true | Convert user IDs to names |
| include_rich_message_fields | boolean | false | Include Slack attachments, blocks, metadata, files, and reactions when present |
| include_all_metadata | boolean | false | Pass Slack's `include_all_metadata` option to `conversations.history` |

**Returns:**
```json
{
  "channel": "D063M4403MW",
  "message_count": 50,
  "has_more": true,
  "messages": [
    {
      "ts": "1767368030.607599",
      "user": "Gwen Santos",
      "user_id": "U05GPEVH7J9",
      "text": "Hello!",
      "datetime": "2026-01-02T15:33:50.000Z",
      "has_thread": false,
      "attachments": [
        {
          "text": "Additional message context"
        }
      ]
    }
  ]
}
```

`include_rich_message_fields` changes this tool's **output shape only** — it surfaces fields Slack
already returns on the message object: `attachments`, `blocks`, `files`, `reactions`, `metadata`,
plus `subtype`, `bot_id`, `app_id` (markers that flag automated / bot / app messages) and `team`
(the workspace id, present on all messages). Especially `blocks` can be large, so it's opt-in per
call to keep MCP client context lean.

`include_all_metadata` is a **separate, independent** Slack request flag: its only effect is to add
the full `event_payload` inside a message's developer `metadata` (without it you still get
`metadata.event_type`). The two are orthogonal — set `include_rich_message_fields` to see `metadata`
in the output at all; additionally set `include_all_metadata` for the full payload.

Note: `slack_search_messages` matches are thin — Slack's search API does not return these rich
fields on matches (only `team`). To read rich content for a search hit, call
`slack_conversations_history` or `slack_get_thread` on the match's channel/ts.

---

### slack_get_full_conversation

Export full conversation with threads.

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| channel_id | string | *required* | Channel or DM ID |
| oldest | string | - | Unix timestamp start; matching boundary timestamp is included |
| latest | string | - | Unix timestamp end; matching boundary timestamp is included |
| max_messages | number | 2000 | Max messages (up to 10000) |
| include_threads | boolean | true | Fetch thread replies |
| include_rich_message_fields | boolean | false | Include Slack attachments, blocks, metadata, files, and reactions when present |
| include_all_metadata | boolean | false | Pass Slack's `include_all_metadata` option to `conversations.history` and `conversations.replies` |
| output_file | string | - | Filename (saved to ~/.slack-mcp-exports/) |

**Timestamps:**
- Dec 1, 2025 = `1733011200`
- Jan 1, 2026 = `1735689600`

**Returns:**
```json
{
  "channel": "D063M4403MW",
  "exported_at": "2026-01-03T16:00:00Z",
  "total_messages": 150,
  "date_range": {
    "oldest": "2025-12-01T00:00:00Z",
    "latest": "now"
  },
  "saved_to": "/Users/james/export.json",
  "messages": [...]
}
```

---

### slack_search_messages

Search messages across the workspace.

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| query | string | *required* | Search query |
| count | number | 20 | Number of results (max 100) |
| include_rich_message_fields | boolean | false | Include Slack attachments, blocks, metadata, files, and reactions when present |

**Query Syntax:**
- `from:@username` - From specific user
- `in:#channel` - In specific channel
- `has:link` - Has links
- `before:2026-01-01` - Before date
- `after:2025-12-01` - After date

**Returns:**
```json
{
  "query": "project update",
  "total": 25,
  "matches": [
    {
      "ts": "1767368030.607599",
      "channel": "general",
      "channel_id": "C05GPEVH7J9",
      "user": "Example User",
      "text": "Here's the project update...",
      "datetime": "2026-01-02T15:33:50.000Z",
      "permalink": "https://..."
    }
  ]
}
```

---

### slack_send_message

Send a message.

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| channel_id | string | *required* | Channel or DM ID |
| text | string | *required* | Message text |
| thread_ts | string | - | Thread to reply to |

**Returns:**
```json
{
  "status": "sent",
  "channel": "D063M4403MW",
  "ts": "1767368030.607599",
  "message": "Hello!"
}
```

---

### slack_get_thread

Get all replies in a thread.

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| channel_id | string | *required* | Channel or DM ID |
| thread_ts | string | *required* | Thread parent timestamp |
| include_rich_message_fields | boolean | false | Include Slack attachments, blocks, metadata, files, and reactions when present |
| include_all_metadata | boolean | false | Pass Slack's `include_all_metadata` option to `conversations.replies` |

**Returns:**
```json
{
  "channel": "D063M4403MW",
  "thread_ts": "1767368030.607599",
  "message_count": 5,
  "messages": [
    {
      "ts": "1767368030.607599",
      "user": "Example User",
      "text": "Original message",
      "datetime": "2026-01-02T15:33:50.000Z",
      "is_parent": true
    }
  ]
}
```

---

### slack_users_info

Get user details.

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| user_id | string | *required* | Slack user ID |

**Returns:**
```json
{
  "id": "U05GPEVH7J9",
  "name": "gwen",
  "real_name": "Gwen Santos",
  "display_name": "Gwen",
  "email": "gwen@example.com",
  "title": "Assistant",
  "timezone": "America/New_York",
  "is_bot": false,
  "is_admin": false
}
```

---

### slack_list_users

List all workspace users.

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| limit | number | 100 | Maximum users to return |

**Returns:**
```json
{
  "count": 10,
  "users": [
    {
      "id": "U05GPEVH7J9",
      "name": "gwen",
      "real_name": "Gwen Santos",
      "display_name": "Gwen",
      "email": "gwen@example.com",
      "is_admin": false
    }
  ]
}
```

---

### slack_add_reaction

Add an emoji reaction to a message.

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| channel_id | string | *required* | Channel or DM ID |
| timestamp | string | *required* | Message timestamp to react to |
| reaction | string | *required* | Emoji name without colons (e.g. `thumbsup`, `heart`, `eyes`) |

**Returns:**
```json
{
  "status": "added",
  "channel": "D063M4403MW",
  "timestamp": "1767368030.607599",
  "reaction": "thumbsup"
}
```

---

### slack_remove_reaction

Remove an emoji reaction from a message.

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| channel_id | string | *required* | Channel or DM ID |
| timestamp | string | *required* | Message timestamp |
| reaction | string | *required* | Emoji name without colons |

**Returns:**
```json
{
  "status": "removed",
  "channel": "D063M4403MW",
  "timestamp": "1767368030.607599",
  "reaction": "thumbsup"
}
```

---

### slack_conversations_mark

Mark a conversation as read up to a specific message timestamp.

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| channel_id | string | *required* | Channel or DM ID to mark as read |
| timestamp | string | *required* | Message timestamp to mark as read up to |

**Returns:**
```json
{
  "status": "marked",
  "channel": "D063M4403MW",
  "read_up_to": "1767368030.607599"
}
```

---

### slack_conversations_unreads

Get channels and DMs with unread messages, sorted by unread count (highest first).

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| types | string | "im,mpim,public_channel,private_channel" | Comma-separated conversation types |
| limit | number | 50 | Maximum conversations to return |

**Returns:**
```json
{
  "total_unread_conversations": 3,
  "conversations": [
    {
      "id": "C05GPEVH7J9",
      "name": "engineering",
      "type": "public_channel",
      "unread_count": 12,
      "latest_ts": "1767368030.607599"
    },
    {
      "id": "D063M4403MW",
      "name": "Gwen Santos",
      "type": "dm",
      "unread_count": 5,
      "latest_ts": "1767368025.123456"
    }
  ]
}
```

---

### slack_users_search

Search workspace users by name, display name, or email. Case-insensitive partial match.

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| query | string | *required* | Search term to match against name, display name, real name, or email |
| limit | number | 20 | Maximum results to return |

**Returns:**
```json
{
  "query": "gwen",
  "count": 1,
  "total_matches": 1,
  "users": [
    {
      "id": "U05GPEVH7J9",
      "name": "gwen",
      "real_name": "Gwen Santos",
      "display_name": "Gwen",
      "email": "gwen@example.com",
      "title": "Assistant",
      "is_admin": false
    }
  ]
}
```
