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

const args = process.argv.slice(2);
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
} else if (WIZARD_ARGS.has(firstArg)) {
  scriptPath = join(__dirname, "../scripts/setup-wizard.js");
  scriptArgs = args;
}

const child = spawn(process.execPath, [scriptPath, ...scriptArgs], {
  stdio: "inherit",
  env: process.env,
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
