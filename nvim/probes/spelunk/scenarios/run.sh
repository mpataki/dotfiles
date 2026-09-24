#!/usr/bin/env bash
# Runs every spelunk scenario headless against ~/code/k9s and dumps what the
# plugin showed into out/: <name>.tree.txt (the split), <name>.md (the export),
# <name>.log (the narrated run; .log.raw is nvim's unnormalized output).
# Exits non-zero if any scenario errors.
#
# Scenarios are narrated drives, not probes: they assert nothing, but they end
# in the probe harness's P.done(), so a scenario that errors never prints the
# "probe: N passed, M failed" summary and counts as a failure (same keying as
# probes/spelunk/run.sh). XDG_CONFIG_HOME passes through from the environment,
# so a worktree can point nvim at its own config.
set -u
cd "$(dirname "$0")" || exit 1
mkdir -p out

fail=0
for s in *_scenario.lua; do
  name=${s%_scenario.lua}
  log=out/$name.log
  echo "== $s"
  # noswapfile: a concurrent nvim on the same corpus file would otherwise
  # block on the swap-file prompt (stdin) and hang the run.
  nvim --headless --cmd 'set noswapfile shortmess+=A' -c "luafile $s" -c 'qa' >"$log.raw" 2>&1 </dev/null
  # nvim's own messages (errors) use bare CRs; normalize to lines.
  perl -pe "s/\r\n?/\n/g" "$log.raw" >"$log" && echo >>"$log"
  sed "s/^/   /" "$log"
  if ! grep -qE 'probe: [0-9]+ passed, 0 failed' "$log"; then
    echo "   FAILED: no clean summary (scenario errored?)"
    fail=1
  fi
done

exit $fail
