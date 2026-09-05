#!/usr/bin/env bash
# Build the VictoriaMetrics / VictoriaLogs MCP servers as native binaries into
# ~/.local/bin. Native beats the upstream Docker images: each container idles
# at ~500 MB inside the Docker VM and one pair spawns per Claude session.
# `go install` is not usable — upstream go.mod carries replace directives.
set -euo pipefail

VM_TAG="${VM_TAG:-v1.20.2}"
VL_TAG="${VL_TAG:-v1.9.0}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

build() {
  local repo="$1" tag="$2"
  local stamp="$BIN_DIR/.$repo.version"
  if [ -x "$BIN_DIR/$repo" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$tag" ]; then
    echo "$repo $tag already built"
    return
  fi
  git clone -q --depth 1 --branch "$tag" "https://github.com/VictoriaMetrics/$repo.git" "$WORK/$repo"
  (cd "$WORK/$repo" && go build -ldflags "-X main.version=$tag" -o "$BIN_DIR/$repo" "./cmd/$repo")
  echo "$tag" > "$stamp"
  echo "built $repo $tag -> $BIN_DIR/$repo"
}

mkdir -p "$BIN_DIR"
build mcp-victoriametrics "$VM_TAG"
build mcp-victorialogs "$VL_TAG"
