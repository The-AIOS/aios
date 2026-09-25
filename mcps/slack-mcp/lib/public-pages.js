import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { PUBLIC_METADATA } from "./public-metadata.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");
const TEMPLATE_DIR = resolve(ROOT, "templates", "public-pages");

const GITHUB_PAGES_ROOT = "https://jtalk22.github.io/slack-mcp-server";

// One token vocabulary for every generated page. Byte-identical on all six
// surfaces — check-public-surface-integrity.js asserts this exact block.
// Estate register lives OUTSIDE the app-window fiction; the system register
// (sys-green / sys-blue / clay / traffic lights) belongs INSIDE app chrome.
export const DESIGN_TOKENS = `:root {
      color-scheme: dark;
      /* estate — outside the window */
      --ink: #0b0b0c;
      --surface: #131315;
      --surface-2: #18181b;
      --rule: #2b2b30;
      --paper: #eeebe3;
      --paper-2: #e3e0d6;
      --muted: #9a978e;
      --stamp: #e5482f;
      --signal: #ffb224;
      --desk-1: #1a1a2e;
      --desk-2: #16213e;
      --desk-3: #0f3460;
      /* system register — inside app chrome only */
      --sys-green: #28c840;
      --sys-blue: #6eb5ff;
      --clay: #da7756;
      --traffic-red: #ff5f57;
      --traffic-yellow: #febc2e;
      --traffic-green: #28c840;
      /* type */
      --display: "Nyght Serif", Georgia, "Times New Roman", serif;
      --body: "Roobert", system-ui, sans-serif;
      --mono: "Roobert Mono", ui-monospace, SFMono-Regular, Menlo, monospace;
    }`;

function fontFaces(base) {
  return `@font-face { font-family: "Nyght Serif"; src: url("${base}nyght-serif-medium.woff2") format("woff2"); font-display: swap; font-weight: 500; }
    @font-face { font-family: "Nyght Serif"; src: url("${base}nyght-serif-medium-italic.woff2") format("woff2"); font-display: swap; font-weight: 500; font-style: italic; }
    @font-face { font-family: "Roobert"; src: url("${base}roobert-regular.woff2") format("woff2"); font-display: swap; font-weight: 400; }
    @font-face { font-family: "Roobert"; src: url("${base}roobert-semibold.woff2") format("woff2"); font-display: swap; font-weight: 600; }
    @font-face { font-family: "Roobert Mono"; src: url("${base}roobert-mono.woff2") format("woff2"); font-display: swap; font-weight: 400 600; }`;
}
const GITHUB_DOCS_ROOT = `${PUBLIC_METADATA.canonicalRepoUrl}/blob/main/docs`;
const SOCIAL_IMAGE_URL = `${GITHUB_PAGES_ROOT}/docs/images/social-preview-v3.png`;
const ICON_URL = `${GITHUB_PAGES_ROOT}/docs/assets/icon-512.png`;
const NPM_URL = "https://www.npmjs.com/package/@jtalk22/slack-mcp";
const RELEASES_URL = `${PUBLIC_METADATA.canonicalRepoUrl}/releases/latest`;
const SETUP_URL = `${PUBLIC_METADATA.canonicalRepoUrl}/blob/main/docs/SETUP.md`;
const DEMO_VIDEO_URL = `${GITHUB_PAGES_ROOT}/docs/videos/slack-mcp-proof-20s-vertical.mp4`;

function template(name) {
  return readFileSync(resolve(TEMPLATE_DIR, name), "utf8");
}

function replaceTokens(source, replacements) {
  return source.replace(/\{\{([A-Z0-9_]+)\}\}/g, (_match, key) => {
    if (!(key in replacements)) {
      throw new Error(`Missing template token: ${key}`);
    }
    return replacements[key];
  });
}

function rootDecisionPanel() {
  return `
    <section class="stage" style="padding-top:0">
      <div class="decision-grid" aria-label="Self-host info">
        <article class="decision-card">
          <span class="decision-label">Self-host</span>
          <h2>Catch up on Slack—free, local, and yours.</h2>
          <p>The current ${PUBLIC_METADATA.selfHostedToolCount}-tool surface turns DMs, search, threads, unread triage, actions, and workflows into agent-readable context without an app/admin queue.</p>
          <ul>
            <li>stdio, web, and Docker paths stay fully under your control</li>
            <li>No OAuth app registration or admin approval needed</li>
            <li>Token persistence with automatic refresh on macOS</li>
          </ul>
          <p class="decision-links"><a href="${SETUP_URL}">Setup guide</a> · <a href="${RELEASES_URL}">Latest release</a> · <a href="${NPM_URL}">npm</a></p>
        </article>
      </div>
    </section>
  `.trim();
}

function shareLinks() {
  return `
      <a href="${SETUP_URL}" rel="noopener">Install (\`--setup\`)</a>
      <a href="${SETUP_URL}" rel="noopener">Verify (\`--version/--doctor/--status\`)</a>
      <a href="${RELEASES_URL}" rel="noopener">Latest Release</a>
      <a href="${GITHUB_PAGES_ROOT}/" rel="noopener">Autoplay Demo Landing</a>
      <a href="${DEMO_VIDEO_URL}" rel="noopener">20s Mobile Clip</a>
      <a href="${NPM_URL}" rel="noopener">npm Package</a>
      <a href="${PUBLIC_METADATA.canonicalSiteUrl}" rel="noopener" style="background:rgba(255,178,36,0.18);border-color:rgba(255,178,36,0.45);color:var(--signal)">Hosted</a>
    `.trim();
}

function shareNote() {
  return `<strong>Ask what happened. Get receipts. Close the loop.</strong> The free local path gives you the current ${PUBLIC_METADATA.selfHostedToolCount}-tool surface without an app/admin queue. <a href="${PUBLIC_METADATA.canonicalSiteUrl}">Hosted</a> adds permanent OAuth, indexing, scheduled intelligence, and team continuity when the workflow must run without you.`;
}

function demoLinks() {
  return `
      <a href="${PUBLIC_METADATA.canonicalSiteUrl}" target="_blank" rel="noopener noreferrer" style="background:rgba(229,72,47,0.18);border-color:rgba(229,72,47,0.45);color:var(--stamp)">Hosted</a>
      <a href="${NPM_URL}" target="_blank" rel="noopener noreferrer">npm Install</a>
      <a href="${SETUP_URL}" target="_blank" rel="noopener noreferrer">Setup Guide</a>
    `.trim();
}

function demoNote() {
  return `The free local path ships the current ${PUBLIC_METADATA.selfHostedToolCount}-tool surface with session-based auth and no app/admin queue. <a href="${PUBLIC_METADATA.canonicalSiteUrl}" target="_blank" rel="noopener noreferrer">Hosted</a> adds permanent OAuth, indexed retrieval, scheduled intelligence, and team continuity when the workflow must run without you.`;
}

function demoFooterLinks() {
  return `<a href="${PUBLIC_METADATA.canonicalRepoUrl}">GitHub</a> · <a href="${NPM_URL}" style="color:var(--muted);text-decoration:none;font-size:0.875rem">npm</a> · <a href="${PUBLIC_METADATA.canonicalSiteUrl}" style="color:var(--stamp);text-decoration:none;font-size:0.875rem">Hosted</a>`;
}

function commonTokens() {
  return {
    DESIGN_TOKENS,
    CANONICAL_SITE_URL: PUBLIC_METADATA.canonicalSiteUrl,
    CLOUD_PRICING_URL: PUBLIC_METADATA.cloudPricingUrl,
    CLOUD_WORKFLOWS_URL: PUBLIC_METADATA.canonicalSiteUrl + "/workflows",
    CLOUD_OFFICIAL_COMPARISON_URL: PUBLIC_METADATA.canonicalSiteUrl + "/official-slack-mcp-vs-managed",
    CLOUD_GEMINI_CLI_URL: PUBLIC_METADATA.canonicalSiteUrl + "/gemini-cli",
    CLOUD_READINESS_URL: PUBLIC_METADATA.canonicalSiteUrl + "/readiness",
    CLOUD_DOCS_URL: PUBLIC_METADATA.cloudDocsUrl,
    CLOUD_SECURITY_URL: PUBLIC_METADATA.cloudSecurityUrl,
    CLOUD_PROCUREMENT_URL: PUBLIC_METADATA.canonicalSiteUrl + "/procurement",
    CLOUD_MARKETPLACE_READINESS_URL: PUBLIC_METADATA.canonicalSiteUrl + "/marketplace-readiness",
    CLOUD_SUPPORT_URL: PUBLIC_METADATA.cloudSupportUrl,
    CLOUD_DEPLOYMENT_URL: PUBLIC_METADATA.canonicalSiteUrl + "/deployment",
    CLOUD_STATUS_URL: PUBLIC_METADATA.cloudStatusUrl,
    CLOUD_SELF_HOST_URL: PUBLIC_METADATA.canonicalSiteUrl + "/self-host",
    CLOUD_ACCOUNT_URL: PUBLIC_METADATA.canonicalSiteUrl + "/account",
    GITHUB_REPO_URL: PUBLIC_METADATA.canonicalRepoUrl,
    GITHUB_PAGES_ROOT,
    GITHUB_DOCS_ROOT,
    ICON_URL,
    SOCIAL_IMAGE_URL,
    NPM_URL,
    RELEASES_URL,
    SETUP_URL,
    RELEASE_HEALTH_URL: RELEASES_URL,
    VERSION_PARITY_URL: RELEASES_URL,
    RUNBOOK_URL: SETUP_URL,
    SELF_HOSTED_TOOL_COUNT: String(PUBLIC_METADATA.selfHostedToolCount),
    CLOUD_MANAGED_TOOL_COUNT: "15",
    TEAM_AI_WORKFLOW_COUNT: "3",
    CLOUD_SOLO_PRICE: "$19/mo",
    CLOUD_TEAM_PRICE: "$49/mo",
    CLOUD_TURNKEY_LAUNCH_PRICE: "contact us",
    CLOUD_MANAGED_RELIABILITY_PRICE: "contact us",
    SUPPORT_EMAIL: PUBLIC_METADATA.supportEmail,
    ROOT_DECISION_PANEL: rootDecisionPanel(),
    SHARE_LINKS: shareLinks(),
    SHARE_NOTE: shareNote(),
    DEMO_LINKS: demoLinks(),
    DEMO_NOTE: demoNote(),
    DEMO_FOOTER_LINKS: demoFooterLinks(),
  };
}

export function buildPublicPages() {
  const tokens = commonTokens();
  // index.html lives at the repo root; every other page lives in public/
  // next to the fonts directory, so the @font-face base path differs.
  const rootTokens = { ...tokens, FONT_FACES: fontFaces("public/fonts/") };
  const publicTokens = { ...tokens, FONT_FACES: fontFaces("fonts/") };
  return {
    "index.html": replaceTokens(template("index.html.tpl"), rootTokens),
    "public/share.html": replaceTokens(template("share.html.tpl"), publicTokens),
    "public/demo.html": replaceTokens(template("demo.html.tpl"), publicTokens),
    "public/demo-video.html": replaceTokens(template("demo-video.html.tpl"), publicTokens),
    "public/proof-reel.html": replaceTokens(template("proof-reel.html.tpl"), publicTokens),
    "public/demo-slack-mcp.html": replaceTokens(template("demo-slack-mcp.html.tpl"), publicTokens),
  };
}
