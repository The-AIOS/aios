#!/usr/bin/env bash
# secret-scan.sh — block a commit carrying an obvious secret. Shared by BOTH the
# pre-commit hook (raw human commits) AND aios-commit's self-scan (its plumbing path
# bypasses the hook). With paths as args it scans those files; with none it scans the
# staged diff. Exit 0 = clean · 1 = a secret was found (the commit is blocked).
set -uo pipefail

PATTERNS=(
  'sk-ant-[A-Za-z0-9_-]{20,}'            # Anthropic API key
  'AKIA[0-9A-Z]{16}'                     # AWS access key id
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'   # any private key
  'ghp_[A-Za-z0-9]{36}'                  # GitHub PAT (classic)
  'github_pat_[A-Za-z0-9_]{60,}'         # GitHub PAT (fine-grained)
  'xox[baprs]-[A-Za-z0-9-]{10,}'         # Slack token
  'AIza[0-9A-Za-z_-]{35}'                # Google API key
  'glpat-[A-Za-z0-9_-]{20,}'             # GitLab PAT
)

files=()
if [ $# -gt 0 ]; then
  for p in "$@"; do [ -f "$p" ] && files+=("$p"); done
else
  while IFS= read -r f; do [ -f "$f" ] && files+=("$f"); done < <(git diff --cached --name-only 2>/dev/null)
fi
[ ${#files[@]} -eq 0 ] && exit 0

hit=0
for pat in "${PATTERNS[@]}"; do
  match=$(grep -InE "$pat" "${files[@]}" 2>/dev/null | head -3 || true)
  if [ -n "$match" ]; then
    [ "$hit" = 0 ] && echo "secret-scan: BLOCKED — secret-shaped string(s) found:" >&2
    printf '%s\n' "$match" | sed 's/^/  /' >&2
    hit=1
  fi
done
if [ "$hit" = 1 ]; then
  echo "secret-scan: remove the secret (store it in a gitignored .template) and retry." >&2
  exit 1
fi
exit 0
