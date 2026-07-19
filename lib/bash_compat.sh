#!/usr/bin/env bash
# Safe array helpers for Bash 3.2 with `set -u` (macOS /bin/bash).
#
# Empty arrays cannot be expanded as "${name[@]}" under `set -u` on Bash 3.2.
# Use these helpers for append, loops, printf, and command argument lists.

# True when the named array has one or more elements.
array_not_empty() {
  eval "(( \${#${1}[@]} > 0 ))"
}

# Append all elements from src into dest; no-op when src is empty.
array_append_all() {
  local dest_name="$1"
  local src_name="$2"
  eval "if (( \${#${src_name}[@]} > 0 )); then ${dest_name}+=(\"\${${src_name}[@]}\"); fi"
}

# Append array elements from src onto a command array dest.
array_append_cmd() {
  array_append_all "$1" "$2"
}

# Print array elements one per line; prints nothing when empty.
array_print_lines() {
  local name="$1"
  eval "if (( \${#${name}[@]} > 0 )); then printf '%s\\n' \"\${${name}[@]}\"; fi"
}
