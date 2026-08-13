#compdef bv
# bv shell completion. Candidates come from `bv __complete`, which reads the
# binary's own protobuf registry — services, methods, request fields and enum
# values can never drift from the API.
#
# Install:
#   bv completion zsh > "${fpath[1]}/_bv" && exec zsh
_bv() {
  local -a candidates
  candidates=(${(f)"$(bv __complete "${words[@]:1:$((CURRENT-1))}" 2>/dev/null)"})
  compadd -S '' -- $candidates
}
compdef _bv bv
