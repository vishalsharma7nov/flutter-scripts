#!/usr/bin/env bash
# Helpers for listing and selecting connected Android devices via adb.

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bash_compat.sh
source "$_lib_dir/bash_compat.sh"
unset _lib_dir

list_adb_device_serials() {
  if ! command -v adb >/dev/null 2>&1; then
    echo "adb not found. Install Android platform-tools and ensure adb is on PATH." >&2
    return 1
  fi

  adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { print $1 }'
}

adb_device_label() {
  local serial="$1"
  local model kind

  if [[ "$serial" == emulator-* ]]; then
    kind="emulator"
  else
    kind="device"
  fi

  model="$(adb -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
  if [[ -z "$model" ]]; then
    model="unknown"
  fi

  printf '%s (%s, %s)' "$serial" "$model" "$kind"
}

# Prints the chosen serial on stdout. Pass an existing serial to skip the menu.
pick_adb_device() {
  local requested="${1:-}"
  local -a devices=()
  local choice=""
  local index=1
  local serial=""

  if [[ -n "$requested" ]]; then
    echo "$requested"
    return 0
  fi

  while IFS= read -r serial; do
    [[ -n "$serial" ]] && devices+=("$serial")
  done < <(list_adb_device_serials || true)

  if ((${#devices[@]} == 0)); then
    echo "No Android device/emulator connected. Run: adb devices" >&2
    return 1
  fi

  if ((${#devices[@]} == 1)); then
    echo "${devices[0]}"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    echo "Multiple Android devices connected. Pass -d <serial> (adb devices)." >&2
    return 1
  fi

  echo "" >&2
  echo "Connected Android devices:" >&2
  for serial in "${devices[@]}"; do
    printf '  %2d) %s\n' "$index" "$(adb_device_label "$serial")" >&2
    index=$((index + 1))
  done
  echo "  q) Quit" >&2
  echo "" >&2

  printf 'Select device [1-%d]: ' "${#devices[@]}" >&2
  if ! read -r choice; then
    echo "No device selected." >&2
    return 1
  fi

  if [[ "$choice" == "q" || "$choice" == "Q" || -z "$choice" ]]; then
    echo "Cancelled." >&2
    return 1
  fi

  if ! [[ "$choice" =~ ^[0-9]+$ ]] ||
    ((choice < 1 || choice > ${#devices[@]})); then
    echo "Invalid selection: $choice (choose 1-${#devices[@]})." >&2
    return 1
  fi

  serial="${devices[$((choice - 1))]}"
  echo "Selected device: $(adb_device_label "$serial")" >&2
  echo "$serial"
}
