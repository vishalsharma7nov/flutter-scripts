#!/usr/bin/env bash
# List and pick Flutter run targets via `flutter devices --machine`.

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f array_not_empty >/dev/null 2>&1; then
  # shellcheck source=bash_compat.sh
  source "$_lib_dir/bash_compat.sh"
fi
unset _lib_dir

# Prints lines: id<TAB>name<TAB>platform
list_flutter_devices_tsv() {
  if ! declare -f flutter_cmd >/dev/null 2>&1; then
    echo "flutter_cmd is unavailable; source lib/flutter_project.sh first." >&2
    return 1
  fi

  flutter_cmd devices --machine 2>/dev/null | python3 -c '
import json
import sys

raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)

devices = json.loads(raw)
for device in devices:
    if device.get("isSupported") is False:
        continue
    device_id = device.get("id", "")
    name = device.get("name", device_id)
    platform = device.get("targetPlatform", "")
    if device_id:
        print(f"{device_id}\t{name}\t{platform}")
'
}

flutter_device_label() {
  local device_id="$1"
  local name="$2"
  local platform="$3"
  printf '%s — %s (%s)' "$name" "$device_id" "$platform"
}

# Prints chosen device id on stdout.
pick_flutter_device() {
  local requested="${1:-}"
  local -a device_ids=()
  local -a device_names=()
  local -a device_platforms=()
  local choice=""
  local index=1
  local line=""
  local id name platform

  if [[ -n "$requested" ]]; then
    echo "$requested"
    return 0
  fi

  while IFS=$'\t' read -r id name platform; do
    [[ -z "$id" ]] && continue
    device_ids+=("$id")
    device_names+=("$name")
    device_platforms+=("$platform")
  done < <(list_flutter_devices_tsv || true)

  if ((${#device_ids[@]} == 0)); then
    echo "No Flutter devices found. Connect a phone/emulator or start a simulator." >&2
    echo "Run: flutter devices" >&2
    return 1
  fi

  if ((${#device_ids[@]} == 1)); then
    echo "Using device: $(flutter_device_label "${device_ids[0]}" "${device_names[0]}" "${device_platforms[0]}")" >&2
    echo "${device_ids[0]}"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    echo "Multiple devices found. Pass -d <device-id> (flutter devices)." >&2
    return 1
  fi

  echo "" >&2
  echo "Connected Flutter devices:" >&2
  for ((index = 0; index < ${#device_ids[@]}; index++)); do
    printf '  %2d) %s\n' "$((index + 1))" \
      "$(flutter_device_label "${device_ids[$index]}" "${device_names[$index]}" "${device_platforms[$index]}")" >&2
  done
  echo "  q) Quit" >&2
  echo "" >&2

  printf 'Select device [1-%d]: ' "${#device_ids[@]}" >&2
  if ! read -r choice; then
    echo "No device selected." >&2
    return 1
  fi

  if [[ "$choice" == "q" || "$choice" == "Q" || -z "$choice" ]]; then
    echo "Cancelled." >&2
    return 1
  fi

  if ! [[ "$choice" =~ ^[0-9]+$ ]] ||
    ((choice < 1 || choice > ${#device_ids[@]})); then
    echo "Invalid selection: $choice (choose 1-${#device_ids[@]})." >&2
    return 1
  fi

  index=$((choice - 1))
  echo "Selected device: $(flutter_device_label "${device_ids[$index]}" "${device_names[$index]}" "${device_platforms[$index]}")" >&2
  echo "${device_ids[$index]}"
}

# Prints dart|go|typescript on stdout.
# $1 = explicit CLI choice (skips prompt when set)
# $2 = optional preference file (used as default hint / non-TTY fallback)
pick_backend_language() {
  local requested="${1:-}"
  local choice=""
  local pref_file="${2:-}"
  local last_pref=""

  case "$requested" in
    dart|go|typescript|ts)
      case "$requested" in
        ts) echo "typescript" ;;
        *) echo "$requested" ;;
      esac
      return 0
      ;;
  esac

  if [[ -n "$pref_file" && -f "$pref_file" ]]; then
    last_pref="$(tr -d '[:space:]' <"$pref_file" | tr '[:upper:]' '[:lower:]')"
    case "$last_pref" in
      dart|go|typescript) ;;
      *) last_pref="" ;;
    esac
  fi

  if [[ ! -t 0 ]]; then
    if [[ -n "$last_pref" ]]; then
      echo "$last_pref"
    else
      echo "dart"
    fi
    return 0
  fi

  echo "" >&2
  echo "Continue with which monitor server?" >&2
  echo "  1) dart        Active — Dart monitor server (bin/ + lib/)" >&2
  echo "  2) go          Active — Go monitor server (server/go)" >&2
  echo "  3) typescript  Scaffold — continue work in server/typescript" >&2
  echo "  q) Quit" >&2
  if [[ -n "$last_pref" ]]; then
    echo "" >&2
    echo "Last preference: $last_pref" >&2
  fi
  echo "" >&2

  local prompt="Select server [1-3]"
  if [[ -n "$last_pref" ]]; then
    prompt="Select server [1-3] (Enter = $last_pref)"
  fi
  printf '%s: ' "$prompt" >&2
  if ! read -r choice; then
    echo "No server selected." >&2
    return 1
  fi

  if [[ -z "$choice" && -n "$last_pref" ]]; then
    echo "$last_pref"
    return 0
  fi

  case "$choice" in
    1|dart|d|D)
      echo "dart"
      ;;
    2|go|g|G)
      echo "go"
      ;;
    3|typescript|ts|t|T)
      echo "typescript"
      ;;
    q|Q)
      echo "Cancelled." >&2
      return 1
      ;;
    *)
      echo "Invalid selection: $choice (choose 1, 2, or 3)." >&2
      return 1
      ;;
  esac
}

# Prints "debug", "release" (profile), or "release-build" (store --release) on stdout.
pick_build_mode() {
  local requested="${1:-}"
  local choice=""

  case "$requested" in
    debug|release|release-build|profile)
      case "$requested" in
        profile)
          echo "release"
          ;;
        *)
          echo "$requested"
          ;;
      esac
      return 0
      ;;
  esac

  if [[ ! -t 0 ]]; then
    echo "debug"
    return 0
  fi

  echo "" >&2
  echo "Build mode:" >&2
  echo "  1) debug          Dart isolates via VM service" >&2
  echo "  2) profile        profile run + isolates + device logs (near release)" >&2
  echo "  3) release        store build (--release, device logs only, no VM)" >&2
  echo "  q) Quit" >&2
  echo "" >&2

  printf 'Select build mode [1-3]: ' >&2
  if ! read -r choice; then
    echo "No build mode selected." >&2
    return 1
  fi

  case "$choice" in
    1|debug|d|D)
      echo "debug"
      ;;
    2|profile|release|r|R)
      echo "release"
      ;;
    3|release-build|store|s|S)
      echo "release-build"
      ;;
    q|Q)
      echo "Cancelled." >&2
      return 1
      ;;
    *)
      echo "Invalid selection: $choice (choose 1, 2, or 3)." >&2
      return 1
      ;;
  esac
}
