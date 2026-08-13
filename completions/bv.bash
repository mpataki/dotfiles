# bv shell completion. Candidates come from `bv __complete`, which reads the
# binary's own protobuf registry — services, methods, request fields and enum
# values can never drift from the API.
#
# Install:
#   bv completion bash > ~/.bv-completion.bash
#   echo 'source ~/.bv-completion.bash' >> ~/.bashrc
_bv() {
  local line out cur head typed IFS
  line="${COMP_LINE:0:${COMP_POINT}}"
  read -r -a typed <<< "$line"
  [[ "$line" == *" " ]] && typed+=("")
  # Call with the default IFS (bash 3.2 folds "${array[@]}" into one argument
  # otherwise), then split the candidates on newlines.
  out="$(bv __complete "${typed[@]:1}" 2>/dev/null)"
  IFS=$'\n'
  COMPREPLY=($out)
  # bash splits words on '=', so strip the part the shell already holds.
  cur="${typed[${#typed[@]}-1]}"
  if [[ "$cur" == *=* ]]; then
    head="${cur%=*}="
    COMPREPLY=("${COMPREPLY[@]#"$head"}")
  fi
  compopt -o nospace 2>/dev/null
}
complete -F _bv bv
