#!/usr/bin/env bash
# Discover package release configs under flutter-scripts/<package>/release.config.sh

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bash_compat.sh
source "$_lib_dir/bash_compat.sh"
unset _lib_dir

declare -a PR_CONFIG_FILES=()
declare -a PR_PACKAGE_IDS=()
declare -a PR_PACKAGE_TITLES=()
declare -a PR_PACKAGE_DESCRIPTIONS=()

_pr_config_field() {
  local file="$1" field="$2"
  # shellcheck disable=SC1090
  source "$file"
  case "$field" in
    id) printf '%s\n' "${PR_PACKAGE_ID:-}" ;;
    title) printf '%s\n' "${PR_PACKAGE_TITLE:-${PR_PACKAGE_ID:-}}" ;;
    description) printf '%s\n' "${PR_PACKAGE_DESCRIPTION:-Release ${PR_PACKAGE_TITLE:-package}}" ;;
  esac
  # Unset config variables so the next config load starts clean.
  unset PR_PACKAGE_ID PR_PACKAGE_TITLE PR_PACKAGE_DESCRIPTION PR_DEFAULT_REPO \
    PR_REPO_ENV_VAR PR_GITHUB_GIT_URL PR_HOST_PUBSPEC_KEY PR_HOST_APP_HINT \
    PR_TAG_PREFIX PR_VERSION_FILE_PUBSPEC PR_CHANGELOG_FILE \
    PR_VERSION_EXTRA_FILES PR_DART_ANALYZE_PATHS PR_DART_FORMAT_PATHS \
    PR_CHANNEL_CONTRACT_TOOL PR_FLUTTER_TEST PR_ANDROID_GRADLE_TASK PR_ANDROID_GRADLE_DIR
}

discover_release_packages() {
  local scripts_dir="$1"
  local path dir base id title desc

  PR_CONFIG_FILES=()
  PR_PACKAGE_IDS=()
  PR_PACKAGE_TITLES=()
  PR_PACKAGE_DESCRIPTIONS=()

  [[ -d "$scripts_dir" ]] || return 1

  while IFS= read -r path; do
    dir="$(dirname "$path")"
    base="$(basename "$dir")"
    id="$(_pr_config_field "$path" id)"
    [[ -n "$id" ]] || continue
    title="$(_pr_config_field "$path" title)"
    desc="$(_pr_config_field "$path" description)"

    PR_CONFIG_FILES+=("$path")
    PR_PACKAGE_IDS+=("$id")
    PR_PACKAGE_TITLES+=("$title")
    PR_PACKAGE_DESCRIPTIONS+=("$desc")
  done < <(
    {
      find "$scripts_dir/packages" -mindepth 2 -maxdepth 2 -name 'release.config.sh' -type f 2>/dev/null
      # Legacy layouts (repo-root package folders) — skip tooling trees.
      find "$scripts_dir" -mindepth 2 -maxdepth 2 -name 'release.config.sh' -type f 2>/dev/null \
        | grep -Ev '/(scripts|tools|lib|docs|examples|config)/' || true
    } | LC_ALL=C sort -u
  )

  if ! array_not_empty PR_PACKAGE_IDS; then
    echo "No release.config.sh files found under: $scripts_dir" >&2
    return 1
  fi
}

_pr_print_release_menu() {
  local index=1
  local i

  echo "" >&2
  echo "Available packages:" >&2
  for i in "${!PR_PACKAGE_IDS[@]}"; do
    printf '  %2d) %-36s %s\n' "$index" "${PR_PACKAGE_IDS[$i]}" "${PR_PACKAGE_TITLES[$i]}" >&2
    printf '      %s\n' "${PR_PACKAGE_DESCRIPTIONS[$i]}" >&2
    index=$((index + 1))
  done
  echo "  q) Quit" >&2
  echo "" >&2
}

list_release_packages_and_exit() {
  local index=1
  local i

  for i in "${!PR_PACKAGE_IDS[@]}"; do
    printf '%2d) %s — %s\n' "$index" "${PR_PACKAGE_IDS[$i]}" "${PR_PACKAGE_TITLES[$i]}"
    printf '    %s\n' "${PR_PACKAGE_DESCRIPTIONS[$i]}"
    printf '    config: %s\n' "${PR_CONFIG_FILES[$i]}"
    index=$((index + 1))
  done
  exit 0
}

_resolve_release_package_index() {
  local query="$1"
  local i

  for i in "${!PR_PACKAGE_IDS[@]}"; do
    if [[ "$query" == "${PR_PACKAGE_IDS[$i]}" || "$query" == "${PR_PACKAGE_TITLES[$i]}" ]]; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

select_release_package() {
  local scripts_dir="$1"
  local choice="${RELEASE_PACKAGE_SELECT:-${RELEASE_PACKAGE_ID:-}}"

  if ! discover_release_packages "$scripts_dir"; then
    return 1
  fi

  if [[ -n "$choice" ]]; then
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#PR_PACKAGE_IDS[@]})); then
      echo "${PR_CONFIG_FILES[$((choice - 1))]}"
      return 0
    fi
    local idx
    if idx="$(_resolve_release_package_index "$choice" || true)" && [[ -n "$idx" ]]; then
      echo "${PR_CONFIG_FILES[$idx]}"
      return 0
    fi
    echo "Unknown package: $choice" >&2
    return 1
  fi

  _pr_print_release_menu

  if [[ ! -t 0 ]]; then
    echo "Pass --package <id> or run interactively in a terminal." >&2
    return 1
  fi

  printf 'Select package to release [1-%d]: ' "${#PR_PACKAGE_IDS[@]}" >&2
  if ! read -r choice; then
    echo "No package selected." >&2
    return 1
  fi

  if [[ "$choice" == "q" || "$choice" == "Q" || -z "$choice" ]]; then
    echo "Cancelled." >&2
    return 1
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#PR_PACKAGE_IDS[@]})); then
    echo "${PR_CONFIG_FILES[$((choice - 1))]}"
    return 0
  fi

  local idx
  if idx="$(_resolve_release_package_index "$choice" || true)" && [[ -n "$idx" ]]; then
    echo "${PR_CONFIG_FILES[$idx]}"
    return 0
  fi

  echo "Invalid selection: $choice" >&2
  return 1
}
