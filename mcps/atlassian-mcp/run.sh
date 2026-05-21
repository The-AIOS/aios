#!/bin/bash
# Atlassian MCP launcher — reads secrets from env, never from args/config.
# Required env vars (export from ~/.zshrc):
#   ATLASSIAN_URL         — e.g. https://your-domain.atlassian.net
#   ATLASSIAN_USERNAME    — your login email
#   ATLASSIAN_API_TOKEN   — from id.atlassian.com/manage-profile/security/api-tokens

set -e

for v in ATLASSIAN_URL ATLASSIAN_USERNAME ATLASSIAN_API_TOKEN; do
  if [ -z "${!v}" ]; then
    echo "ERROR: $v env var not set. See mcps/atlassian-mcp/README.md" >&2
    exit 1
  fi
done

exec uvx mcp-atlassian \
  --confluence-url "$ATLASSIAN_URL/wiki" \
  --jira-url "$ATLASSIAN_URL" \
  --confluence-username "$ATLASSIAN_USERNAME" \
  --jira-username "$ATLASSIAN_USERNAME" \
  --confluence-token "$ATLASSIAN_API_TOKEN" \
  --jira-token "$ATLASSIAN_API_TOKEN"
