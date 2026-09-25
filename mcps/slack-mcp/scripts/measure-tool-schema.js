#!/usr/bin/env node
/**
 * Measure the tool-schema cost of each SLACK_MCP_TOOLS profile.
 *
 * An MCP client pays for the tools/list schema on every turn that carries it,
 * so a smaller advertised surface is a smaller per-turn tax. This prints the
 * exact serialized size of the advertised payload for each profile and a token
 * estimate using the widely-used ~4-characters-per-token heuristic.
 *
 * The heuristic is an ESTIMATE, not a tokenizer-exact count, and is labelled as
 * such wherever the number is published. It is stable and reproducible, which is
 * what a before/after comparison needs.
 *
 *   node scripts/measure-tool-schema.js          # human-readable table
 *   node scripts/measure-tool-schema.js --json    # machine-readable
 */

import { resolveToolProfile } from "../lib/tools.js";

const PROFILES = ["all", "read", "essentials"];

// The tools/list payload each client receives: name, description, inputSchema,
// and annotations — the full advertised object, as it goes on the wire.
function advertisedPayload(tools) {
  return JSON.stringify(
    tools.map((t) => ({
      name: t.name,
      description: t.description,
      inputSchema: t.inputSchema,
      annotations: t.annotations,
    }))
  );
}

function estimateTokens(str) {
  return Math.round(str.length / 4);
}

function measure(profile) {
  const { tools } = resolveToolProfile(profile);
  const payload = advertisedPayload(tools);
  return {
    profile,
    tools: tools.length,
    chars: payload.length,
    est_tokens: estimateTokens(payload),
  };
}

function main() {
  const rows = PROFILES.map(measure);
  const asJson = process.argv.includes("--json");

  if (asJson) {
    const baseline = rows.find((r) => r.profile === "all")?.est_tokens ?? 0;
    const out = {
      method: "~4 chars/token estimate over the advertised tools/list payload (name+description+inputSchema+annotations)",
      baseline_tokens: baseline,
      profiles: rows,
    };
    console.log(JSON.stringify(out, null, 2));
    return;
  }

  const baseline = rows.find((r) => r.profile === "all")?.est_tokens ?? 0;
  console.log("Tool-schema cost per profile (est. tokens ≈ chars / 4):\n");
  console.log("  profile     tools   chars   est_tokens   vs all");
  console.log("  " + "-".repeat(52));
  for (const r of rows) {
    const delta = baseline ? `${Math.round((r.est_tokens / baseline) * 100)}%` : "n/a";
    console.log(
      `  ${r.profile.padEnd(10)}  ${String(r.tools).padStart(5)}   ${String(r.chars).padStart(5)}   ${String(r.est_tokens).padStart(10)}   ${delta.padStart(5)}`
    );
  }
  console.log("\n  Token counts are estimates (~4 chars per token), not tokenizer-exact.");
}

main();
