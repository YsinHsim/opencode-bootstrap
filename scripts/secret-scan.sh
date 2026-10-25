#!/usr/bin/env bash
# Secret scan — run before every commit and before every push.
#
# Usage:
#   ./scripts/secret-scan.sh            # working tree + index + full history
#   ./scripts/secret-scan.sh --staged   # fast pre-commit check only
#
# Exit 0 = clean. Exit 1 = secret found (do not commit/push).
set -euo pipefail

PATTERN='ya29\.[A-Za-z0-9_-]+'
PATTERN="$PATTERN|sk-[A-Za-z0-9]{16,}"
PATTERN="$PATTERN|Bearer [a-f0-9]{32,}"
PATTERN="$PATTERN|(api[_-]?key|password|secret|token|client_secret)\"?[[:space:]]*[:=][[:space:]]*\"[^\"]{12,}\""
PATTERN="$PATTERN|BEGIN [A-Z ]*PRIVATE KEY"

MODE="${1:-all}"
HITS=0

report() {
  HITS=1
  printf '\033[0;31m[x]\033[0m %s\n' "$1"
}

# Skip the scanner itself and binary files; the pattern text lives in here.
scan_text() {
  grep -vE 'scripts/secret-scan\.sh|package-lock\.json|\.lock$' || true
}

# ---------- 1. Staged content ----------
if git rev-parse --git-dir >/dev/null 2>&1; then
  if ! git diff --cached -U0 --no-color | scan_text |
       grep -nE "$PATTERN" >/dev/null 2>&1; then :; else
    report "Secret pattern found in staged changes:"
    git diff --cached -U0 --no-color | scan_text | grep -nE "$PATTERN" | head -20
  fi
fi

[ "$MODE" = "--staged" ] && { [ "$HITS" -eq 0 ] && echo "[+] Staged content clean."; exit "$HITS"; }

# ---------- 2. Tracked working-tree files ----------
# Catches a secret sitting in a tracked file that is not yet staged — the case
# `git diff --cached` alone misses.
if git rev-parse --git-dir >/dev/null 2>&1; then
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    case "$f" in scripts/secret-scan.sh) continue ;; esac
    if grep -qIE "$PATTERN" "$f" 2>/dev/null; then
      report "Tracked file contains a secret-looking value: $f"
      grep -nIE "$PATTERN" "$f" 2>/dev/null | head -5
    fi
  done < <(git ls-files)
fi

# ---------- 3. Entire history ----------
# A secret deleted in a later commit is still in history and becomes public
# the moment the repo does. This is the check that catches it.
if git rev-parse --git-dir >/dev/null 2>&1; then
  HIST="$(git rev-list --all 2>/dev/null | while read -r c; do
            git grep -lIE "$PATTERN" "$c" -- 2>/dev/null || true
          done | sort -u)"
  if [ -n "$HIST" ]; then
    report "Secret pattern found in git history (reachable from any ref):"
    echo "$HIST" | head -20
    echo
    echo "    Deleting the secret in a new commit does NOT remove it."
    echo "    Rewrite history (git filter-repo) or re-init before pushing."
  fi
fi

echo
if [ "$HITS" -eq 0 ]; then
  echo "[+] Clean: no secret patterns found."
else
  printf '\033[0;31m[x]\033[0m Do not commit or push until the above is resolved.\n'
fi
exit "$HITS"
