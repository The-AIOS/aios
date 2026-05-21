import { readFileSync } from "node:fs";

const packageJson = JSON.parse(
  readFileSync(new URL("../package.json", import.meta.url), "utf8")
);

export const RELEASE_VERSION = packageJson.version;

function withTrackedUrl(url, medium) {
  const tracked = new URL(url);
  tracked.searchParams.set("utm_source", "github");
  tracked.searchParams.set("utm_medium", medium);
  tracked.searchParams.set("utm_campaign", "slack_mcp_cloud");
  return tracked.toString();
}

export const PUBLIC_METADATA = Object.freeze({
  projectName: "slack-mcp-server",
  packageName: packageJson.name,
  canonicalShortDescription: packageJson.description,
  canonicalRepoUrl: "https://github.com/jtalk22/slack-mcp-server",
  canonicalSiteUrl: "https://mcp.revasserlabs.com",
  cloudPricingUrl: "https://mcp.revasserlabs.com/pricing",
  cloudWorkflowsUrl: "https://mcp.revasserlabs.com/workflows",
  cloudGeminiCliUrl: "https://mcp.revasserlabs.com/gemini-cli",
  cloudReadinessUrl: "https://mcp.revasserlabs.com/readiness",
  cloudDocsUrl: "https://mcp.revasserlabs.com/docs",
  cloudSecurityUrl: "https://mcp.revasserlabs.com/security",
  cloudProcurementUrl: "https://mcp.revasserlabs.com/procurement",
  cloudSupportUrl: "https://mcp.revasserlabs.com/support",
  cloudDeploymentUrl: "https://mcp.revasserlabs.com/deployment",
  cloudSelfHostUrl: "https://mcp.revasserlabs.com/self-host",
  cloudAccountUrl: "https://mcp.revasserlabs.com/account",
  cloudUseCasesRootUrl: "https://mcp.revasserlabs.com/use-cases",
  cloudStatusUrl: "https://mcp.revasserlabs.com/status",
  supportEmail: "support@revasserlabs.com",
  privacyEmail: "privacy@revasserlabs.com",
  primaryClient: "Claude",
  secondaryClient: "Gemini CLI",
  selfHostedToolCount: 16,
  cloudManagedToolCount: 15,
  teamAiWorkflowCount: 3,
  cloudSoloPrice: "$19/mo",
  cloudTeamPrice: "$49/mo",
  cloudTurnkeyLaunchPrice: "$2.5k+",
  cloudManagedReliabilityPrice: "$800/mo+",
  tracked: Object.freeze({
    pages: Object.freeze({
      pricing: withTrackedUrl("https://mcp.revasserlabs.com/pricing", "pages"),
      workflows: withTrackedUrl("https://mcp.revasserlabs.com/workflows", "pages"),
      geminiCli: withTrackedUrl("https://mcp.revasserlabs.com/gemini-cli", "pages"),
      readiness: withTrackedUrl("https://mcp.revasserlabs.com/readiness", "pages"),
      docs: withTrackedUrl("https://mcp.revasserlabs.com/docs", "pages"),
      security: withTrackedUrl("https://mcp.revasserlabs.com/security", "pages"),
      procurement: withTrackedUrl("https://mcp.revasserlabs.com/procurement", "pages"),
      deployment: withTrackedUrl("https://mcp.revasserlabs.com/deployment", "pages"),
      support: withTrackedUrl("https://mcp.revasserlabs.com/support", "pages"),
      account: withTrackedUrl("https://mcp.revasserlabs.com/account", "pages"),
      privacy: withTrackedUrl("https://mcp.revasserlabs.com/privacy", "pages"),
    }),
    readme: Object.freeze({
      pricing: withTrackedUrl("https://mcp.revasserlabs.com/pricing", "readme"),
      workflows: withTrackedUrl("https://mcp.revasserlabs.com/workflows", "readme"),
      geminiCli: withTrackedUrl("https://mcp.revasserlabs.com/gemini-cli", "readme"),
      readiness: withTrackedUrl("https://mcp.revasserlabs.com/readiness", "readme"),
      docs: withTrackedUrl("https://mcp.revasserlabs.com/docs", "readme"),
      security: withTrackedUrl("https://mcp.revasserlabs.com/security", "readme"),
      procurement: withTrackedUrl("https://mcp.revasserlabs.com/procurement", "readme"),
      deployment: withTrackedUrl("https://mcp.revasserlabs.com/deployment", "readme"),
      support: withTrackedUrl("https://mcp.revasserlabs.com/support", "readme"),
      account: withTrackedUrl("https://mcp.revasserlabs.com/account", "readme"),
      privacy: withTrackedUrl("https://mcp.revasserlabs.com/privacy", "readme"),
    }),
    docs: Object.freeze({
      pricing: withTrackedUrl("https://mcp.revasserlabs.com/pricing", "docs"),
      workflows: withTrackedUrl("https://mcp.revasserlabs.com/workflows", "docs"),
      geminiCli: withTrackedUrl("https://mcp.revasserlabs.com/gemini-cli", "docs"),
      readiness: withTrackedUrl("https://mcp.revasserlabs.com/readiness", "docs"),
      security: withTrackedUrl("https://mcp.revasserlabs.com/security", "docs"),
      procurement: withTrackedUrl("https://mcp.revasserlabs.com/procurement", "docs"),
      deployment: withTrackedUrl("https://mcp.revasserlabs.com/deployment", "docs"),
      support: withTrackedUrl("https://mcp.revasserlabs.com/support", "docs"),
      account: withTrackedUrl("https://mcp.revasserlabs.com/account", "docs"),
      privacy: withTrackedUrl("https://mcp.revasserlabs.com/privacy", "docs"),
    }),
  }),
});
