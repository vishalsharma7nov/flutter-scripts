# Replaces script positional parameters from remaining_args[].
# Must be sourced at script scope (not called as a function) for Bash 3.2 on macOS.
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f array_not_empty >/dev/null 2>&1; then
  # shellcheck source=bash_compat.sh
  source "$_lib_dir/bash_compat.sh"
fi
unset _lib_dir

if array_not_empty remaining_args; then
  set -- "${remaining_args[@]}"
else
  set -- "_"
  shift
fi
