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
# ONE pass with every pattern (`-e` each). The old loop read every file once per pattern, and
# `-a` (below) makes a binary a full read — measured 11 passes over a 200 MB attachment at ~12 s.
# -e is load-bearing: a pattern beginning with '-' (the private-key header) is otherwise parsed
# as an OPTION BUNDLE; grep then exits 2 and an empty result read as "clean".
# -H: name the file even when only one is scanned. -a, not -I: `-I` skips a file with one NUL
# byte, so a token next to a NUL passed as clean; git commits those bytes all the same.
# `cut` reads ALL of grep's output: a `head` here exits early, grep dies of SIGPIPE (141) under
# pipefail, and a real hit read as "grep failed". It also caps each reported line, so a match in
# a multi-megabyte binary "line" does not flood the terminal.
EARGS=(); for pat in "${PATTERNS[@]}"; do EARGS+=(-e "$pat"); done
# -a reads a binary in full (~60 ms/MB measured), so it applies up to a size cap; anything larger
# is scanned the way it always was (-I: text files in full, binaries skipped) and is NAMED, so the
# gap is visible rather than silent. A token sitting beside a NUL inside a >CAP binary is the one
# case this gives up; a vault's large files are attachments, and the cap keeps every commit fast.
CAP_MB="${AIOS_SECRET_SCAN_CAP_MB:-20}"; small=(); large=()
for f in "${files[@]}"; do
  sz=$(wc -c < "$f" 2>/dev/null | tr -d ' '); [ -n "$sz" ] || sz=0
  if [ "$sz" -gt $((CAP_MB * 1048576)) ]; then large+=("$f"); else small+=("$f"); fi
done
out=""; rc=1
if [ ${#small[@]} -gt 0 ]; then out=$(grep -HanE "${EARGS[@]}" "${small[@]}" 2>/dev/null | tr -d '\000' | cut -c1-200); rc=$?; fi
if [ ${#large[@]} -gt 0 ] && [ "$rc" -le 1 ]; then
  printf 'secret-scan: %s file(s) over %s MB scanned as text only (binary content skipped): %s\n' "${#large[@]}" "$CAP_MB" "${large[*]}" >&2
  o2=$(grep -HInE "${EARGS[@]}" "${large[@]}" 2>/dev/null | tr -d '\000' | cut -c1-200); r2=$?
  [ -n "$o2" ] && out="${out:+$out
}$o2"
  [ "$r2" -gt 1 ] && rc=$r2 || { [ "$r2" -eq 0 ] && rc=0; }
fi
# rc: 0 = matched · 1 = no match · >1 = grep itself failed. Fail CLOSED on >1.
if [ "$rc" -gt 1 ]; then
  echo "secret-scan: FAILED to scan (grep exit $rc) — refusing to pass." >&2
  exit 1
fi
match=$(printf '%s\n' "$out" | sed -n '1,10p')
if [ -n "$out" ]; then
  echo "secret-scan: BLOCKED — secret-shaped string(s) found:" >&2
  # A hit in the links temp file is reported against the symlink it came from.
  printf '%s\n' "$match" | while IFS= read -r line; do
    case "$line" in
      "$links:"*) n=${line#"$links:"}; n=${n%%:*}; printf '  symlink %s -> %s\n' "${link_paths[$n]}" "${line#"$links:$n:"}" ;;
      *)          printf '  %s\n' "$line" ;;
    esac
  done >&2
  hit=1
fi
if [ "$hit" = 1 ]; then
  echo "secret-scan: remove the secret (store it in a gitignored .template) and retry." >&2
  exit 1
fi
exit 0
