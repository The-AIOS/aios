#!/usr/bin/env node
/**
 * slack-mcp package entrypoint dispatcher.
 *
 * Supports:
 * - default stdio server startup
 * - web/http server modes
 * - setup wizard and its status/help/version flags
 */

import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const rawArgs = process.argv.slice(2);

// `--profile <name>` / `--profile=<name>` anywhere on the command line maps
// to SLACK_MCP_PROFILE for the child (#164), so every mode — server, wizard,
// web, http, token refresh — honors the same workspace namespace.
// `--tools <profile>` / `--tools=<profile>` maps to SLACK_MCP_TOOLS the same
// way, so the advertised tool surface can be narrowed from the launch command.
// A separated operand (`--flag value`) must not swallow the following option:
// `--tools --setup` used to consume `--setup` as the value AND drop it from
// args, so the wizard silently never ran. Reject the missing value instead.
function takeOperand(flag, rawArgs, index) {
  const next = rawArgs[index + 1];
  if (next === undefined || next.startsWith("--")) {
    console.error(`${flag} requires a value.`);
    if (flag === "--tools") {
      console.error("  Use: --tools essentials | read | all | <comma-separated tool names>");
    } else {
      console.error("  Use: --profile <workspace-namespace-name>");
    }
    process.exit(1);
  }
  return next;
}

const args = [];
let cliProfile = null;
let cliTools = null;
for (let i = 0; i < rawArgs.length; i++) {
  const arg = rawArgs[i];
  if (arg === "--profile") {
    cliProfile = takeOperand("--profile", rawArgs, i);
    i++;
  } else if (arg.startsWith("--profile=")) {
    cliProfile = arg.slice("--profile=".length);
  } else if (arg === "--tools") {
    cliTools = takeOperand("--tools", rawArgs, i);
    i++;
  } else if (arg.startsWith("--tools=")) {
    cliTools = arg.slice("--tools=".length);
  } else {
    args.push(arg);
  }
}
const childEnv = {
  ...process.env,
  ...(cliProfile !== null ? { SLACK_MCP_PROFILE: cliProfile } : {}),
  ...(cliTools !== null ? { SLACK_MCP_TOOLS: cliTools } : {}),
};

const firstArg = args[0];

const WIZARD_ARGS = new Set([
  "--setup", "setup",
  "--status", "status",
  "--doctor", "doctor",
  "--version", "-v",
  "--help", "-h", "help",
]);

let scriptPath = join(__dirname, "server.js");
let scriptArgs = args;

if (firstArg === "web") {
  scriptPath = join(__dirname, "web-server.js");
  scriptArgs = args.slice(1);
} else if (firstArg === "http") {
  scriptPath = join(__dirname, "server-http.js");
  scriptArgs = args.slice(1);
} else if (firstArg === "--apply-template" || firstArg === "apply-template") {
  scriptPath = join(__dirname, "../scripts/apply-template.js");
  scriptArgs = args.slice(1);
} else if (firstArg === "--refresh-tokens" || firstArg === "refresh-tokens") {
  scriptPath = join(__dirname, "../scripts/token-cli.js");
  scriptArgs = ["auto"];
} else if (WIZARD_ARGS.has(firstArg)) {
  scriptPath = join(__dirname, "../scripts/setup-wizard.js");
  scriptArgs = args;
}

const child = spawn(process.execPath, [scriptPath, ...scriptArgs], {
  stdio: "inherit",
  env: childEnv,
});

child.on("error", (error) => {
  console.error(`Failed to start ${scriptPath}: ${error.message}`);
  process.exit(1);
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 0);
});
