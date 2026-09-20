# Mat Pataki's Dotfiles (linux + mac)

These dotfiles come with an idempotent install script that will ask before doing anything crazy.

```shell
git clone --recurse-submodules git@github.com:mpataki/dotfiles.git ~/dotfiles
cd ~/dotfiles
echo work > ~/.dotfiles-profile   # work machine only; enables the work plugin + allows
./install.sh
```

Agent config (Claude Code + Codex) lives in the `agent-config` submodule; check it with
`agent/check_agent_config.sh`.
