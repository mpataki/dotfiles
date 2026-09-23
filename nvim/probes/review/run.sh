#!/usr/bin/env bash
# Runs every review probe headless; exits non-zero if any fails.
#
# Keys on the harness's "probe: N passed, M failed" summary line, not on the
# exit status: capture_probe.lua calls P.done() inside VimLeavePre, where
# :cquit can no longer set nvim's exit code. A probe that crashes before the
# summary prints counts as a failure too (no summary line at all).
set -u
cd "$(dirname "$0")/../.." || exit 1

fail=0
out=$(mktemp) || exit 1
trap 'rm -f "$out"' EXIT

for p in probes/review/*_probe.lua; do
  echo "== $p"
  nvim --headless -c "luafile $p" -c 'qa' >"$out" 2>&1
  summary=$(grep -E '^probe: [0-9]+ passed, [0-9]+ failed' "$out" | tail -1)
  if [ -z "$summary" ]; then
    echo "   no probe summary (crashed?); last output:"
    tail -20 "$out" | sed 's/^/   /'
    fail=1
    continue
  fi
  echo "   $summary"
  case "$summary" in
    *', 0 failed') ;;
    *)
      grep '^FAIL' "$out" | sed 's/^/   /'
      fail=1
      ;;
  esac
done

exit $fail
