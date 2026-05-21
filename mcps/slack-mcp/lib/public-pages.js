import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { PUBLIC_METADATA } from "./public-metadata.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");
const TEMPLATE_DIR = resolve(ROOT, "templates", "public-pages");

const GITHUB_PAGES_ROOT = "https://jtalk22.github.io/slack-mcp-server";
const GITHUB_DOCS_ROOT = `${PUBLIC_METADATA.canonicalRepoUrl}/blob/main/docs`;
const SOCIAL_IMAGE_URL = `${GITHUB_PAGES_ROOT}/docs/images/social-preview-v3.png`;
const ICON_URL = `${GITHUB_PAGES_ROOT}/docs/assets/icon-512.png`;
const NPM_URL = "https://www.npmjs.com/package/@jtalk22/slack-mcp";
const RELEASES_URL = `${PUBLIC_METADATA.canonicalRepoUrl}/releases/latest`;
const SETUP_URL = `${PUBLIC_METADATA.canonicalRepoUrl}/blob/main/docs/SETUP.md`;
const RELEASE_HEALTH_URL = `${GITHUB_DOCS_ROOT}/release-health/latest.md`;
const VERSION_PARITY_URL = `${GITHUB_DOCS_ROOT}/release-health/version-parity.md`;
const RUNBOOK_URL = `${GITHUB_DOCS_ROOT}/LAUNCH-OPS.md`;
const DEMO_VIDEO_URL = `${GITHUB_PAGES_ROOT}/docs/videos/demo-claude-mobile-20s.mp4`;

function template(name) {
  return readFileSync(resolve(TEMPLATE_DIR, name), "utf8");
}

function replaceTokens(source, replacements) {
  return source.replace(/\{\{([A-Z0-9_]+)\}\}/g, (match, key) => {
    if (!(key in replacements)) {
      throw new Error(`Missing template token: ${key}`);
    }
    return replacements[key];
  });
}

function rootDecisionPanel() {
  return `
    <section class="stage" style="padding-top:0">
      <div class="decision-grid" aria-label="Cloud versus self-host decision guide">
        <article class="decision-card">
          <span class="decision-label">Self-host</span>
          <h2>16 tools and full operator control.</h2>
          <p>Choose the open-source path if you want npm or Docker, local-first transport control, and direct ownership of token extraction, storage, and process management.</p>
          <ul>
            <li>stdio, web, and Docker paths stay fully under your control</li>
            <li>Best fit for local development, custom transport, or internal operator ownership</li>
            <li>Proof surfaces: install guide, release health, and version parity remain public</li>
          </ul>
          <p class="decision-links"><a href="${SETUP_URL}">Setup guide</a> · <a href="${VERSION_PARITY_URL}">Version parity</a> · <a href="${RELEASE_HEALTH_URL}">Release health</a></p>
        </article>
        <article class="decision-card accent">
          <span class="decision-label">Cloud</span>
          <h2>${PUBLIC_METADATA.cloudManagedToolCount} managed tools, ${PUBLIC_METADATA.teamAiWorkflowCount} Team AI workflows.</h2>
          <p>Choose Cloud if you want one remote endpoint, hosted credential handling, deployment review, and an operational support path instead of running the transport yourself. ${PUBLIC_METADATA.primaryClient} stays primary; ${PUBLIC_METADATA.secondaryClient} is supported as the second client path.</p>
          <ul>
            <li>Solo: ${PUBLIC_METADATA.cloudSoloPrice} for the managed endpoint and hosted credential handling</li>
            <li>Team: ${PUBLIC_METADATA.cloudTeamPrice} and adds ${PUBLIC_METADATA.teamAiWorkflowCount} AI workflows</li>
            <li>Turnkey Team Launch: from ${PUBLIC_METADATA.cloudTurnkeyLaunchPrice}; Managed Reliability: from ${PUBLIC_METADATA.cloudManagedReliabilityPrice}</li>
          </ul>
          <p class="decision-links"><a href="${PUBLIC_METADATA.tracked.pages.pricing}">Pricing</a> · <a href="${PUBLIC_METADATA.tracked.pages.workflows}">Workflows</a> · <a href="${PUBLIC_METADATA.tracked.pages.geminiCli}">Gemini CLI</a> · <a href="${PUBLIC_METADATA.tracked.pages.deployment}">Deployment review</a> · <a href="${PUBLIC_METADATA.tracked.pages.security}">Security</a></p>
        </article>
        <article class="decision-card">
          <span class="decision-label">Buyer proof</span>
          <h2>Technical trust surfaces stay public.</h2>
          <p>The static Pages root shows npm, GitHub release, and hosted status together. The hosted site publishes <code>/status</code>, <code>/pricing</code>, <code>/docs</code>, <code>/security</code>, <code>/deployment</code>, <code>/support</code>, and <code>/account</code> as the operator-facing Cloud surface.</p>
          <ul>
            <li>GitHub Pages reads the hosted <code>/status</code> contract live</li>
            <li>Registry, npm, runtime parity, and hosted funnel reporting are tracked in the public reports</li>
            <li>Rollout and security questions route to hosted review surfaces instead of ad hoc GitHub issues</li>
          </ul>
          <p class="decision-links"><a href="${RUNBOOK_URL}">Runbook</a> · <a href="${PUBLIC_METADATA.cloudStatusUrl}">Raw status JSON</a> · <a href="${PUBLIC_METADATA.tracked.pages.procurement}">Procurement</a> · <a href="${PUBLIC_METADATA.tracked.pages.readiness}">Readiness</a> · <a href="${PUBLIC_METADATA.tracked.pages.pricing}">Plans & offers</a></p>
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
      <a href="${PUBLIC_METADATA.tracked.pages.pricing}" rel="noopener">Pricing</a>
      <a href="${PUBLIC_METADATA.tracked.pages.workflows}" rel="noopener">Workflows</a>
      <a href="${PUBLIC_METADATA.tracked.pages.geminiCli}" rel="noopener">Gemini CLI</a>
      <a href="${PUBLIC_METADATA.tracked.pages.docs}" rel="noopener">Cloud Docs</a>
      <a href="${PUBLIC_METADATA.tracked.pages.security}" rel="noopener">Security</a>
      <a href="${PUBLIC_METADATA.tracked.pages.procurement}" rel="noopener">Procurement</a>
      <a href="${PUBLIC_METADATA.tracked.pages.deployment}" rel="noopener">Deployment Review</a>
      <a href="${PUBLIC_METADATA.tracked.pages.support}" rel="noopener">Cloud Support</a>
      <a href="${PUBLIC_METADATA.cloudUseCasesRootUrl}/support-triage?utm_source=github&utm_medium=pages&utm_campaign=slack_mcp_cloud" rel="noopener">Support Triage Use Case</a>
      <a href="${GITHUB_PAGES_ROOT}/" rel="noopener">Autoplay Demo Landing</a>
      <a href="${DEMO_VIDEO_URL}" rel="noopener">20s Mobile Clip</a>
      <a href="${NPM_URL}" rel="noopener">npm Package</a>
      <a href="${PUBLIC_METADATA.canonicalSiteUrl}" rel="noopener" style="background:rgba(240,194,70,0.18);border-color:rgba(240,194,70,0.45);color:#f0c246">Cloud</a>
    `.trim();
}

function shareNote() {
  return `<strong>Verify in 30 seconds:</strong> <code>--version</code>, <code>--doctor</code>, <code>--status</code>. Self-host gives ${PUBLIC_METADATA.selfHostedToolCount} tools and full operator control. Cloud starts at ${PUBLIC_METADATA.cloudSoloPrice} for ${PUBLIC_METADATA.cloudManagedToolCount} managed tools, deployment review, procurement-ready security, readiness guidance, and support. Team at ${PUBLIC_METADATA.cloudTeamPrice} adds ${PUBLIC_METADATA.teamAiWorkflowCount} AI workflows. ${PUBLIC_METADATA.primaryClient} is the primary path; ${PUBLIC_METADATA.secondaryClient} is supported on the hosted endpoint.`;
}

function demoLinks() {
  return `
      <a href="${PUBLIC_METADATA.canonicalSiteUrl}" target="_blank" rel="noopener noreferrer" style="background:rgba(240,194,70,0.18);border-color:rgba(240,194,70,0.45);color:#f0c246">Cloud</a>
      <a href="${NPM_URL}" target="_blank" rel="noopener noreferrer">npm Install</a>
      <a href="${PUBLIC_METADATA.tracked.pages.pricing}" target="_blank" rel="noopener noreferrer">Pricing</a>
      <a href="${PUBLIC_METADATA.tracked.pages.workflows}" target="_blank" rel="noopener noreferrer">Workflows</a>
      <a href="${PUBLIC_METADATA.tracked.pages.geminiCli}" target="_blank" rel="noopener noreferrer">Gemini CLI</a>
      <a href="${SETUP_URL}" target="_blank" rel="noopener noreferrer">Setup Guide</a>
      <a href="${PUBLIC_METADATA.tracked.pages.docs}" target="_blank" rel="noopener noreferrer">Cloud Docs</a>
      <a href="${PUBLIC_METADATA.tracked.pages.security}" target="_blank" rel="noopener noreferrer">Security</a>
      <a href="${PUBLIC_METADATA.tracked.pages.procurement}" target="_blank" rel="noopener noreferrer">Procurement</a>
      <a href="${PUBLIC_METADATA.tracked.pages.deployment}" target="_blank" rel="noopener noreferrer">Deployment Review</a>
      <a href="${PUBLIC_METADATA.tracked.pages.support}" target="_blank" rel="noopener noreferrer">Cloud Support</a>
    `.trim();
}

function demoNote() {
  return `Self-host free for ${PUBLIC_METADATA.selfHostedToolCount} tools and full transport control, or use <a href="${PUBLIC_METADATA.tracked.pages.pricing}" target="_blank" rel="noopener noreferrer">Cloud</a> for ${PUBLIC_METADATA.cloudManagedToolCount} managed tools, deployment review, procurement-ready security, and support. Solo starts at ${PUBLIC_METADATA.cloudSoloPrice}; Team at ${PUBLIC_METADATA.cloudTeamPrice} adds ${PUBLIC_METADATA.teamAiWorkflowCount} AI workflows. Turnkey Team Launch starts at ${PUBLIC_METADATA.cloudTurnkeyLaunchPrice}; Managed Reliability starts at ${PUBLIC_METADATA.cloudManagedReliabilityPrice}.`;
}

function demoFooterLinks() {
  return `<a href="${PUBLIC_METADATA.canonicalRepoUrl}">GitHub</a> · <a href="${PUBLIC_METADATA.tracked.pages.pricing}" style="color:#f0c246;text-decoration:none;font-size:0.875rem">Cloud Plans</a> · <a href="${PUBLIC_METADATA.tracked.pages.workflows}" style="color:#94a3b8;text-decoration:none;font-size:0.875rem">Workflows</a> · <a href="${PUBLIC_METADATA.tracked.pages.geminiCli}" style="color:#94a3b8;text-decoration:none;font-size:0.875rem">Gemini CLI</a> · <a href="${PUBLIC_METADATA.tracked.pages.security}" style="color:#94a3b8;text-decoration:none;font-size:0.875rem">Security</a> · <a href="${PUBLIC_METADATA.tracked.pages.deployment}" style="color:#94a3b8;text-decoration:none;font-size:0.875rem">Deployment Review</a> · <a href="${PUBLIC_METADATA.tracked.pages.support}" style="color:#94a3b8;text-decoration:none;font-size:0.875rem">Cloud Support</a> · <a href="${NPM_URL}" style="color:#94a3b8;text-decoration:none;font-size:0.875rem">npm</a>`;
}

function commonTokens() {
  return {
    CANONICAL_SITE_URL: PUBLIC_METADATA.canonicalSiteUrl,
    CLOUD_PRICING_URL: PUBLIC_METADATA.tracked.pages.pricing,
    CLOUD_WORKFLOWS_URL: PUBLIC_METADATA.tracked.pages.workflows,
    CLOUD_GEMINI_CLI_URL: PUBLIC_METADATA.tracked.pages.geminiCli,
    CLOUD_READINESS_URL: PUBLIC_METADATA.tracked.pages.readiness,
    CLOUD_DOCS_URL: PUBLIC_METADATA.tracked.pages.docs,
    CLOUD_SECURITY_URL: PUBLIC_METADATA.tracked.pages.security,
    CLOUD_PROCUREMENT_URL: PUBLIC_METADATA.tracked.pages.procurement,
    CLOUD_SUPPORT_URL: PUBLIC_METADATA.tracked.pages.support,
    CLOUD_DEPLOYMENT_URL: PUBLIC_METADATA.tracked.pages.deployment,
    CLOUD_STATUS_URL: PUBLIC_METADATA.cloudStatusUrl,
    CLOUD_SELF_HOST_URL: PUBLIC_METADATA.cloudSelfHostUrl,
    CLOUD_ACCOUNT_URL: PUBLIC_METADATA.cloudAccountUrl,
    GITHUB_REPO_URL: PUBLIC_METADATA.canonicalRepoUrl,
    GITHUB_PAGES_ROOT,
    GITHUB_DOCS_ROOT,
    ICON_URL,
    SOCIAL_IMAGE_URL,
    NPM_URL,
    RELEASES_URL,
    SETUP_URL,
    RELEASE_HEALTH_URL,
    VERSION_PARITY_URL,
    RUNBOOK_URL,
    SELF_HOSTED_TOOL_COUNT: String(PUBLIC_METADATA.selfHostedToolCount),
    CLOUD_MANAGED_TOOL_COUNT: String(PUBLIC_METADATA.cloudManagedToolCount),
    TEAM_AI_WORKFLOW_COUNT: String(PUBLIC_METADATA.teamAiWorkflowCount),
    CLOUD_SOLO_PRICE: PUBLIC_METADATA.cloudSoloPrice,
    CLOUD_TEAM_PRICE: PUBLIC_METADATA.cloudTeamPrice,
    CLOUD_TURNKEY_LAUNCH_PRICE: PUBLIC_METADATA.cloudTurnkeyLaunchPrice,
    CLOUD_MANAGED_RELIABILITY_PRICE: PUBLIC_METADATA.cloudManagedReliabilityPrice,
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
  return {
    "index.html": replaceTokens(template("index.html.tpl"), tokens),
    "public/share.html": replaceTokens(template("share.html.tpl"), tokens),
    "public/demo.html": replaceTokens(template("demo.html.tpl"), tokens),
    "public/demo-video.html": replaceTokens(template("demo-video.html.tpl"), tokens),
    "public/demo-claude.html": replaceTokens(template("demo-claude.html.tpl"), tokens),
  };
}
