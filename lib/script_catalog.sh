#!/usr/bin/env bash
# Dynamic discovery of runnable shell scripts for the CLI launcher.

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bash_compat.sh
source "$_lib_dir/bash_compat.sh"
unset _lib_dir

declare -a SCRIPT_FILES=()
declare -a SCRIPT_LABELS=()
declare -a SCRIPT_DESCRIPTIONS=()

_launcher_basename() {
  basename "${FLUTTER_SCRIPTS_LAUNCHER:-flutter-scripts.sh}"
}

# Wrappers and internal helpers — runnable directly, hidden from the menu.
_is_internal_script() {
  case "$1" in
    build-android.sh|build-ios-ipa.sh|build_android_apk.sh|build_ios_ipa.sh|classify-version-bump.sh|rtk-locate.sh)
      return 0
      ;;
  esac
  return 1
}

_script_menu_label() {
  case "$1" in
    build_android.sh) echo "flutter-build-android" ;;
    build_ios.sh) echo "flutter-build-ios" ;;
    clear_pub_cache.sh) echo "flutter-clear-pub-cache" ;;
    get_iam_token.sh) echo "flutter-get-iam-token" ;;
    inspect_apk_environment.sh) echo "flutter-inspect-apk" ;;
    classify_version_bump.sh) echo "flutter-classify-version-bump" ;;
    build_mobile_release.sh) echo "flutter-build-mobile" ;;
    setup_packages.sh) echo "flutter-setup-packages" ;;
    device-logs.sh) echo "device-logs" ;;
    android-logcat.sh) echo "android-logcat" ;;
    ios-device-logs.sh) echo "ios-device-logs" ;;
    open-isolate-monitor.sh) echo "isolate-monitor" ;;
    release_package.sh) echo "release-package" ;;
    build_both_release_apks.sh) echo "flutter-build-both-release-apks" ;;
    check_git_identity.sh) echo "check-git-identity" ;;
    check_localization.sh) echo "check-localization" ;;
    install_global.sh) echo "install-global" ;;
    install-device-logs-global.sh) echo "install-device-logs-global" ;;
    setup.sh) echo "setup (first-time)" ;;
    *)
      local base="${1%.sh}"
      base="${base//_/ }"
      base="${base//-/ }"
      printf '%s\n' "$base" | awk '{
        for (i = 1; i <= NF; i++) {
          word = $i
          $i = toupper(substr(word, 1, 1)) substr(word, 2)
        }
        print
      }'
      ;;
  esac
}

_script_menu_description() {
  case "$1" in
    android-logcat.sh)
      echo "Stream Android logcat for the app package on a connected device"
      ;;
    build_android.sh)
      echo "Build a release Android APK or App Bundle with env checks"
      ;;
    build_both_release_apks.sh)
      echo "Build release APKs for two Flutter apps in one run"
      ;;
    build_ios.sh)
      echo "Build a release iOS IPA with env checks"
      ;;
    build_mobile_release.sh)
      echo "Build apk or ipa for prod/dev with a single command"
      ;;
    check_git_identity.sh)
      echo "Show git commit author vs GitHub account used by gh"
      ;;
    check_localization.sh)
      echo "Check ARB key parity and hardcoded UI strings in lib/"
      ;;
    classify_version_bump.sh)
      echo "Classify semver bump (major/minor/patch) for a release"
      ;;
    clear_pub_cache.sh)
      echo "Clear or repair Dart/Flutter pub cache entries"
      ;;
    device-logs.sh)
      echo "Stream device logs for android or ios (wrapper)"
      ;;
    get_iam_token.sh)
      echo "Run tool/get_iam_token.dart OTP helper in the project"
      ;;
    inspect_apk_environment.sh)
      echo "Guess prod vs dev build from host strings inside an APK"
      ;;
    install-device-logs-global.sh)
      echo "Install device-log commands to ~/.local/bin"
      ;;
    install_global.sh)
      echo "Install or relink all script commands to ~/.local/bin"
      ;;
    ios-device-logs.sh)
      echo "Stream iOS simulator or device logs for the app bundle id"
      ;;
    open-isolate-monitor.sh)
      echo "Deploy debug/release to device; isolates (debug) or device logs (release)"
      ;;
    release_package.sh)
      echo "Config-driven release for any Flutter git package (see release.config.sh per package)"
      ;;
    setup.sh)
      echo "One-time bootstrap after clone (chmod, setup.env, global install)"
      ;;
    setup_packages.sh)
      echo "Clone shared git packages listed in packages.list"
      ;;
    *)
      echo "Run $(basename "${1%.sh}") helper script"
      ;;
  esac
}

_should_include_script() {
  local base="$1"
  local rel="${2:-$1}"
  local launcher
  launcher="$(_launcher_basename)"

  [[ "$base" == "$launcher" ]] && return 1
  [[ "$base" == flutter-scripts.sh ]] && return 1
  [[ "$base" == open-flutter-scripts-gui.sh ]] && return 1
  # Root stubs (repo-root wrappers) — prefer scripts/... paths
  if [[ "$rel" == "$base" ]]; then
    case "$base" in
      open-isolate-monitor.sh|setup.sh|install_global.sh)
        return 1
        ;;
    esac
  fi
  if _is_internal_script "$base"; then
    return 1
  fi
  return 0
}

discover_scripts() {
  local scripts_dir="$1"
  local path base rel

  SCRIPT_FILES=()
  SCRIPT_LABELS=()
  SCRIPT_DESCRIPTIONS=()

  [[ -d "$scripts_dir" ]] || return 1

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    base="$(basename "$path")"
    rel="${path#"$scripts_dir"/}"
    if ! _should_include_script "$base" "$rel"; then
      continue
    fi
    SCRIPT_FILES+=("$rel")
    SCRIPT_LABELS+=("$(_script_menu_label "$base")")
    SCRIPT_DESCRIPTIONS+=("$(_script_menu_description "$base")")
  done < <(
    {
      find "$scripts_dir/scripts" -mindepth 2 -maxdepth 2 -name '*.sh' -type f 2>/dev/null
      find "$scripts_dir" -maxdepth 1 -name '*.sh' -type f 2>/dev/null
    } | LC_ALL=C sort -u
  )

  if ((${#SCRIPT_FILES[@]} == 0)); then
    echo "No runnable scripts found in: $scripts_dir" >&2
    return 1
  fi
}

_load_script_catalog() {
  local scripts_dir="${1:-}"
  if [[ -z "$scripts_dir" ]]; then
    echo "discover_scripts: missing scripts directory" >&2
    return 1
  fi
  discover_scripts "$scripts_dir"
}

_print_script_menu() {
  local index=1
  local i

  echo "" >&2
  echo "Available scripts:" >&2
  if array_not_empty SCRIPT_FILES; then
    for i in "${!SCRIPT_FILES[@]}"; do
      printf '  %2d) %-28s %s\n' "$index" "${SCRIPT_LABELS[$i]}" "${SCRIPT_FILES[$i]}" >&2
      printf '      %s\n' "${SCRIPT_DESCRIPTIONS[$i]}" >&2
      index=$((index + 1))
    done
  fi
  echo "  q) Quit" >&2
  echo "" >&2
}

_list_scripts_and_exit() {
  local index=1
  local i

  if array_not_empty SCRIPT_FILES; then
    for i in "${!SCRIPT_FILES[@]}"; do
      printf '%2d) %s — %s\n' "$index" "${SCRIPT_LABELS[$i]}" "${SCRIPT_FILES[$i]}"
      printf '    %s\n' "${SCRIPT_DESCRIPTIONS[$i]}"
      index=$((index + 1))
    done
  fi
  exit 0
}

_resolve_script_by_label() {
  local query="$1"
  local i

  for i in "${!SCRIPT_FILES[@]}"; do
    if [[ "$query" == "${SCRIPT_LABELS[$i]}" ]]; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

_resolve_script_by_name() {
  local query="$1"
  local i
  local base

  if selected_index="$(_resolve_script_by_label "$query" || true)" && [[ -n "$selected_index" ]]; then
    echo "$selected_index"
    return 0
  fi

  for i in "${!SCRIPT_FILES[@]}"; do
    base="$(basename "${SCRIPT_FILES[$i]}")"
    stem="${base%.sh}"
    if [[ "$query" == "${SCRIPT_FILES[$i]}" || "$query" == "$base" || "$query" == "$stem" ]]; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

select_script_cli() {
  local scripts_dir="$1"
  local choice="${SCRIPT_SELECT:-}"
  local selected_index=""

  if ! _load_script_catalog "$scripts_dir"; then
    return 1
  fi

  if [[ -n "$choice" ]]; then
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#SCRIPT_FILES[@]})); then
      echo "${SCRIPT_FILES[$((choice - 1))]}"
      return 0
    fi
    if selected_index="$(_resolve_script_by_name "$choice" || true)" && [[ -n "$selected_index" ]]; then
      echo "${SCRIPT_FILES[$selected_index]}"
      return 0
    fi
    echo "Invalid script selection: $choice" >&2
    return 1
  fi

  _print_script_menu

  if [[ ! -t 0 ]]; then
    echo "Pass --select N, a script name, or run interactively in a terminal." >&2
    return 1
  fi

  printf 'Select script to run [1-%d]: ' "${#SCRIPT_FILES[@]}" >&2
  if ! read -r choice; then
    echo "No script selected." >&2
    return 1
  fi

  if [[ "$choice" == "q" || "$choice" == "Q" || -z "$choice" ]]; then
    echo "Cancelled." >&2
    return 1
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#SCRIPT_FILES[@]})); then
    selected_index=$((choice - 1))
    echo "Selected: ${SCRIPT_LABELS[$selected_index]} (${SCRIPT_FILES[$selected_index]})" >&2
    echo "${SCRIPT_FILES[$selected_index]}"
    return 0
  fi

  if selected_index="$(_resolve_script_by_name "$choice" || true)" && [[ -n "$selected_index" ]]; then
    echo "Selected: ${SCRIPT_LABELS[$selected_index]} (${SCRIPT_FILES[$selected_index]})" >&2
    echo "${SCRIPT_FILES[$selected_index]}"
    return 0
  fi

  echo "Invalid selection: $choice (choose 1-${#SCRIPT_FILES[@]} or a script name)." >&2
  return 1
}
