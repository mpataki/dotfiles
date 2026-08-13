# Shell completions

Generated completion shims, one file per tool per shell. They are loaded by:

- zsh — `zsh/zshrc` sources `completions/*.zsh` after `compinit`
- bash — `bash/bashrc` sources `completions/*.bash`

Both loaders are glob-guarded: a missing file, or a tool that isn't installed,
means no completion for that tool — never a shell error.

## Why the shims are checked in

Each shim is thin: it shells out to the tool at keystroke time for candidates,
so the completion data can't go stale. Checking the shim in avoids paying a
subprocess on every shell start just to regenerate the same few lines.

## Regenerating

Only needed when a tool changes the *shim interface* itself (rare) — not when
its commands, flags or API surface grow.

```shell
bv completion zsh  > completions/bv.zsh
bv completion bash > completions/bv.bash
```

`bv` lives in the band-van repo; `task cli:install` builds and installs it.
