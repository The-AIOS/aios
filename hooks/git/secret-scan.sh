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
  'gh[osur]_[A-Za-z0-9]{36}'             # GitHub OAuth / server / user / refresh token (gho_ is what `gh auth login` mints)
  'xox[baprs]-[A-Za-z0-9-]{10,}'         # Slack token
  'AIza[0-9A-Za-z_-]{35}'                # Google API key
  'glpat-[A-Za-z0-9_-]{20,}'             # GitLab PAT
  'GOCSPX-[A-Za-z0-9_-]{20,}'            # Google OAuth client secret
  '<string>[0-9a-f]{40}</string>'        # 40-hex token in a launchd plist
)

files=()
list=""; links=""; nlinks=0; link_paths=()
trap 'rm -f "$list" "$links"' EXIT      # the temp files below must not outlive an interrupted run
# add_entry <path> — route one enumerated path. A SYMLINK is committed by git as its link
# TEXT (mode 120000), never as the content behind it, so the thing to scan is what
# `readlink` returns: a token in a link target lands in the repo verbatim. `-f` follows
# links, so testing it first would scan the wrong bytes for a link to a file and drop a
# link to a directory entirely. Only the TARGET text goes into the `links` temp file, one
# per line -- the link's own path is not what git stores, and a checkout living under a
# token-shaped directory must not trip the scan. Line N maps back to link_paths[N] so a
# hit is reported against the link, not the temp file.
add_entry() {
  local f="$1" target
  case "$f" in -*) f="./$f" ;; esac        # a leading '-' would read as a readlink/grep option
  if [ -L "$f" ]; then
    if ! target=$(readlink "$f"); then
      # Fail CLOSED: a link whose text could not be read is not a clean link.
      echo "secret-scan: FAILED to read symlink $f — refusing to pass." >&2; exit 1
    fi
    [ -n "$links" ] || links=$(mktemp "${TMPDIR:-/tmp}/secret-scan-links.XXXXXX") || { echo "secret-scan: cannot create a temp file — refusing to pass." >&2; exit 1; }
    # One physical line per link, or line N stops meaning link N: a target carrying a
    # newline is flattened (no pattern spans a newline, so nothing is hidden by it).
    printf '%s\n' "${target//$'\n'/ }" >> "$links"
    nlinks=$((nlinks+1)); link_paths[$nlinks]="$f"
  elif [ -f "$f" ]; then
    files+=("$f")
  fi
}
# enumerate_dir <dir> — every entry a commit of that directory would carry, NUL-terminated.
# Inside a repo that is exactly what `git add --all -- <dir>` stages: tracked entries plus
# untracked ones that are not ignored (an ignored `.env` under the directory must neither
# block nor be scanned -- it is never entering the commit). Outside a repo (the test
# harness, a plain folder) fall back to walking the tree, files and symlinks alike.
# NUL delimiting is load-bearing: a filename with a newline in it would otherwise split
# into two paths that fail `-f` and get silently dropped -- while git adds the file.
enumerate_dir() {
  local d="$1"
  if git -C "$d" rev-parse --show-toplevel >/dev/null 2>&1; then
    git ls-files -z --cached --others --exclude-standard -- "$d"
  else
    find "$d" \( -type f -o -type l \) -not -path '*/.git/*' -print0
  fi
}
if [ $# -gt 0 ]; then
  # A path that names a DIRECTORY is expanded to the entries under it. The caller
  # (aios-commit) hands its paths to `git add --all`, which stages a directory's entire
  # subtree -- so a scanner that silently skipped anything failing `-f` let a whole tree
  # of files into the commit unscanned, while the same file passed by name was blocked.
  # Measured 2026-09-21: `aios-commit -- vault/dir` with a token inside committed it.
  # A symlink to a directory is NOT expanded: git commits the link, not the tree behind it.
  for p in "$@"; do
    if [ -d "$p" ] && [ ! -L "$p" ]; then
      case "$p" in -*) p="./$p" ;; esac      # a leading '-' would read as a find/git option
      list=$(mktemp "${TMPDIR:-/tmp}/secret-scan-list.XXXXXX") || { echo "secret-scan: cannot create a temp file — refusing to pass." >&2; exit 1; }
      if ! enumerate_dir "$p" > "$list" 2>/dev/null; then
        # Fail CLOSED: an enumeration that errored is not an empty directory.
        echo "secret-scan: FAILED to enumerate $p — refusing to pass." >&2; exit 1
      fi
      while IFS= read -r -d '' f; do add_entry "$f"; done < "$list"
      rm -f "$list"; list=""
    else
      add_entry "$p"
    fi
  done
else
  while IFS= read -r f; do add_entry "$f"; done < <(git diff --cached --name-only 2>/dev/null)
fi
[ -n "$links" ] && files+=("$links")
[ ${#files[@]} -eq 0 ] && exit 0

hit=0
for pat in "${PATTERNS[@]}"; do
  # -e is load-bearing: a pattern beginning with '-' (the private-key header) is otherwise
  # parsed by grep as an OPTION BUNDLE. grep then exits 2 (TROUBLE, not "no match"), writes
  # its usage to stderr — which this call discards — and leaves $match empty, which reads
  # here as "clean". That pattern therefore never fired. A failed measurement must never be
  # read as a substantive result.
  # -H: name the file even when only one is scanned, so a blocked directory run says WHICH one.
  match=$(grep -HInE -e "$pat" "${files[@]}" 2>/dev/null | head -3); rc=$?
  # rc: 0 = matched · 1 = no match · >1 = grep itself failed. Fail CLOSED on >1 rather than
  # silently treating an unusable scan as a pass.
  if [ "$rc" -gt 1 ]; then
    echo "secret-scan: FAILED to scan for pattern: $pat (grep exit $rc) — refusing to pass." >&2
    exit 1
  fi
  if [ -n "$match" ]; then
    [ "$hit" = 0 ] && echo "secret-scan: BLOCKED — secret-shaped string(s) found:" >&2
    # A hit in the links temp file is reported against the symlink it came from.
    printf '%s\n' "$match" | while IFS= read -r line; do
      case "$line" in
        "$links:"*) n=${line#"$links:"}; n=${n%%:*}; printf '  symlink %s -> %s\n' "${link_paths[$n]}" "${line#"$links:$n:"}" ;;
        *)          printf '  %s\n' "$line" ;;
      esac
    done >&2
    hit=1
  fi
done
if [ "$hit" = 1 ]; then
  echo "secret-scan: remove the secret (store it in a gitignored .template) and retry." >&2
  exit 1
fi
exit 0
