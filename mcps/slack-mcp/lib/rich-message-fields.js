/**
 * Rich Slack message fields (opt-in).
 *
 * Slack stores a lot of message content outside the plain `text` field:
 * attachments, Block Kit `blocks`, `metadata`, `files`, and `reactions` — plus
 * `subtype`/`bot_id`/`app_id` (which flag bot / app messages) and `team` (the
 * workspace id, present on every message). An attachment-only or block-only alert
 * looks empty when you read `text` alone; surfacing these fields closes that blind spot.
 *
 * These are fields Slack already returns on the message object, so this is an
 * output-shape opt-in only — independent of Slack's `include_all_metadata` request
 * flag (which separately adds the `event_payload` inside `metadata`). They can be
 * large (especially `blocks`), so callers opt in per request.
 */

export const RICH_MESSAGE_KEYS = [
  "attachments", "blocks", "metadata", "files", "reactions",
  "subtype", "bot_id", "app_id", "team"
];

/**
 * Merge present rich fields from a raw Slack message onto a formatted output.
 *
 * Mutates and returns `output`. No-op when disabled or `msg` is falsy. Only keys
 * actually present on `msg` are copied; `undefined` keys are skipped (a present
 * falsy value such as `[]` is still copied).
 */
export function withRichMessageFields(output, msg, includeRichMessageFields) {
  if (!includeRichMessageFields || !msg) return output;

  for (const key of RICH_MESSAGE_KEYS) {
    if (msg[key] !== undefined) {
      output[key] = msg[key];
    }
  }

  return output;
}
