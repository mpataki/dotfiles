#!/usr/bin/env bash
# Runs every spelunk probe headless; exits non-zero if any fails.
#
# Keys on the harness's "probe: N passed, M failed" summary line, not the exit
# status (same contract as probes/review/run.sh). A probe that crashes before
# the summary prints counts as a failure. XDG_CONFIG_HOME passes through from
# the environment, so a worktree can point nvim at its own config.
set -u
cd "$(dirname "$0")/../.." || exit 1

fail=0
out=$(mktemp) || exit 1
trap 'rm -f "$out"' EXIT

for p in probes/spelunk/*_probe.lua; do
  echo "== $p"
  # noswapfile: two headless nvims opening the same corpus file would otherwise
  # block on the swap-file prompt (stdin) and hang the run.
  nvim --headless --cmd 'set noswapfile shortmess+=A' -c "luafile $p" -c 'qa' >"$out" 2>&1 </dev/null
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
