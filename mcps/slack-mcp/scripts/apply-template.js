#!/usr/bin/env node
/**
 * Apply a workflow profile template to ~/.slack-mcp-workflows.json
 *
 * Usage:
 *   slack-mcp --apply-template <template-name>
 *   slack-mcp --apply-template <template-name> --channels C012,C067 [--priority-people U0PRIME]
 *
 * Templates ship in templates/workflow-profiles/. Available templates:
 *   oncall-handoff, support-triage, exec-monday, sprint-tracker,
 *   customer-feedback, incident-room
 *
 * If --channels is not provided, the template is applied with empty
 * channels — you can add them later via slack_workflow_save.
 */

import { readFileSync, existsSync, readdirSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { saveProfile } from "../lib/workflow-store.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const TEMPLATES_DIR = join(__dirname, "..", "templates", "workflow-profiles");

const args = process.argv.slice(2);

function listTemplates() {
  if (!existsSync(TEMPLATES_DIR)) return [];
  return readdirSync(TEMPLATES_DIR)
    .filter((f) => f.endsWith(".json"))
    .map((f) => f.replace(/\.json$/, ""));
}

function printUsage() {
  console.log("Usage: slack-mcp --apply-template <template-name> [--channels C012,C067] [--priority-people U0PRIME,U0SECONDARY] [--profile-name custom-name]");
  console.log("");
  console.log("Available templates:");
  for (const t of listTemplates()) {
    console.log("  " + t);
  }
  console.log("");
  console.log("Example:");
  console.log("  slack-mcp --apply-template support-triage --channels C012345,C067890");
  console.log("");
  console.log("Templates write to ~/.slack-mcp-workflows.json. slack_catch_me_up reads a");
  console.log("profile by name and returns structured evidence shaped by its workflow_kind,");
  console.log("locally, against your own session.");
}

function parseFlag(flag) {
  const idx = args.indexOf(flag);
  if (idx === -1) return null;
  return args[idx + 1];
}

const templateName = args[0];
if (!templateName || templateName === "--help" || templateName === "-h") {
  printUsage();
  process.exit(templateName ? 0 : 1);
}

if (templateName.startsWith("--") || templateName.startsWith("-")) {
  console.error(`Missing template name. Got "${templateName}" as the first positional argument.`);
  console.error("");
  printUsage();
  process.exit(1);
}

const templatePath = join(TEMPLATES_DIR, `${templateName}.json`);
if (!existsSync(templatePath)) {
  console.error(`Template "${templateName}" not found at ${templatePath}`);
  console.error("");
  console.error("Available templates: " + listTemplates().join(", "));
  process.exit(1);
}

let template;
try {
  template = JSON.parse(readFileSync(templatePath, "utf-8"));
} catch (err) {
  console.error(`Failed to parse template "${templateName}": ${err.message}`);
  process.exit(1);
}

const channelsArg = parseFlag("--channels");
const priorityArg = parseFlag("--priority-people");
const profileNameOverride = parseFlag("--profile-name");

const profile = {
  profile_name: profileNameOverride || template.profile_name,
  workflow_kind: template.workflow_kind,
  channels: channelsArg ? channelsArg.split(",").map((s) => s.trim()).filter(Boolean) : (template.channels || []),
  priority_people: priorityArg ? priorityArg.split(",").map((s) => s.trim()).filter(Boolean) : (template.priority_people || []),
  retention_mode: template.retention_mode || "ephemeral",
  summary_cadence: template.summary_cadence || "on_demand",
};

const result = saveProfile(profile);
if (!result.ok) {
  console.error("Failed to save profile:");
  for (const err of result.errors) console.error("  " + err);
  process.exit(1);
}

console.log(`Saved workflow profile "${result.profile_name}" to ~/.slack-mcp-workflows.json`);
console.log(JSON.stringify(result.profile, null, 2));
console.log("");
if (!profile.channels.length) {
  console.log("Note: no channels set. Add channels with:");
  console.log(`  slack-mcp --apply-template ${templateName} --channels C012345,C067890`);
  console.log("Or call slack_workflow_save from your MCP client to update.");
} else {
  console.log("Profile is ready. Run slack_catch_me_up against it from your MCP client.");
  console.log(`(Free tier: 25 AI tool calls/month. Pro $19/mo unlocks unlimited.)`);
}
