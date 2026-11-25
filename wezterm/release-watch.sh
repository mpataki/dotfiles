#!/bin/bash
# Watches for a WezTerm stable release newer than the one that forced the tmux
# margins workaround (tmux/tmux.conf: "Disable DECSLRM margins"). WezTerm
# 20240203 mis-clamps DECSLRM left margins; the fix (wezterm#5871) is only in
# nightly. Any stable release after BASELINE carries it.
#
# Notifies once per state change (new release out / newer one installed) via
# terminal-notifier. Run daily by com.mpataki.wezterm-release-watch.plist.
#
# Env: WATCH_BASELINE (default below), WATCH_DRY_RUN=1 prints instead of
# notifying and skips the state write, WATCH_LATEST / WATCH_INSTALLED override
# the lookups (testing).
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

BASELINE="${WATCH_BASELINE:-20240203-110809-5046fc22}"
STATE_DIR="$HOME/.local/state/wezterm-release-watch"
STATE_FILE="$STATE_DIR/last-notified"
OVERRIDE_HINT="drop the DECSLRM margins override in ~/dotfiles/tmux/tmux.conf"

latest="${WATCH_LATEST:-$(curl -fsSL https://api.github.com/repos/wezterm/wezterm/releases/latest | jq -r .tag_name)}"
installed="${WATCH_INSTALLED:-$(wezterm --version 2>/dev/null | awk '{print $2}')}"

if [[ -z "$latest" || "$latest" == "null" ]]; then
  echo "release-watch: could not read latest release" >&2
  exit 1
fi

# Tags are YYYYMMDD-HHMMSS-sha, so lexical order on the date prefix is release order.
newer_than_baseline() { [[ "${1:0:15}" > "${BASELINE:0:15}" ]]; }

key=""
if [[ -n "$installed" ]] && newer_than_baseline "$installed"; then
  key="installed:$installed"
  title="WezTerm $installed installed"
  msg="Margins fix is in — $OVERRIDE_HINT."
elif newer_than_baseline "$latest"; then
  key="released:$latest"
  title="WezTerm $latest released"
  msg="brew upgrade --cask wezterm, then $OVERRIDE_HINT."
else
  exit 0
fi

if [[ "${WATCH_DRY_RUN:-}" == 1 ]]; then
  echo "$key | $title | $msg"
  exit 0
fi

[[ -f "$STATE_FILE" && "$(cat "$STATE_FILE")" == "$key" ]] && exit 0

terminal-notifier -title "$title" -message "$msg" -group wezterm-release-watch \
  -open "https://github.com/wezterm/wezterm/releases/tag/$latest"
mkdir -p "$STATE_DIR"
echo "$key" > "$STATE_FILE"
