#!/usr/bin/env bash
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f array_not_empty >/dev/null 2>&1; then
  # shellcheck source=bash_compat.sh
  source "$_lib_dir/bash_compat.sh"
fi
unset _lib_dir

# Shared build helpers for Flutter release scripts.

MAIN_DART=""
APP_PROFILE="generic"
RESOLVED_CONFIG_ENV=""
RESOLVED_APP_ENV=""
RESOLVED_ENV_FILE=""
RESOLVED_TARGET_ENV=""
RELEASE_CHECKLIST_FAILED="false"
FLUTTER=()
FLUTTER_VERSION=""

detect_app_profile() {
  if [[ -f "$ROOT/lib/main.dart" ]] &&
    grep -q 'ConfigEnvironment' "$ROOT/lib/main.dart" &&
    [[ -f "$ROOT/test/environment_configuration_test.dart" ]]; then
    APP_PROFILE="configured"
  else
    APP_PROFILE="generic"
  fi
}

_find_secrets_file() {
  local suffix="$1"
  local basename="${SECRETS_BASENAME:-}"

  if [[ -n "$basename" ]]; then
    local candidate="$ROOT/.secrets/${basename}.${suffix}.env"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
    echo "Missing secrets file: $candidate" >&2
    return 1
  fi

  local matches=()
  local path
  while IFS= read -r -d '' path; do
    matches+=("$path")
  done < <(find "$ROOT/.secrets" -maxdepth 1 -name "*.${suffix}.env" -print0 2>/dev/null | sort -z)

  if [[ ${#matches[@]} -eq 1 ]]; then
    echo "${matches[0]}"
    return 0
  fi
  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "Multiple .secrets/*.${suffix}.env files found; set SECRETS_BASENAME or ENV_FILE" >&2
    return 1
  fi
  return 1
}

resolve_env_from_main() {
  MAIN_DART="$ROOT/lib/main.dart"
  if [[ ! -f "$MAIN_DART" ]]; then
    echo "Missing lib/main.dart" >&2
    return 1
  fi

  if grep -Fq 'const env = ConfigEnvironment.production;' "$MAIN_DART"; then
    RESOLVED_CONFIG_ENV="ConfigEnvironment.production"
    RESOLVED_APP_ENV="production"
    RESOLVED_TARGET_ENV="prod"
    RESOLVED_ENV_FILE="$(_find_secrets_file prod || true)"
    return 0
  fi

  if grep -Fq 'const env = ConfigEnvironment.dev;' "$MAIN_DART"; then
    RESOLVED_CONFIG_ENV="ConfigEnvironment.dev"
    RESOLVED_APP_ENV="development"
    RESOLVED_TARGET_ENV="dev"
    RESOLVED_ENV_FILE="$(_find_secrets_file local || true)"
    return 0
  fi

  if grep -Fq 'const env = ConfigEnvironment.staging;' "$MAIN_DART"; then
    RESOLVED_CONFIG_ENV="ConfigEnvironment.staging"
    RESOLVED_APP_ENV="staging"
    RESOLVED_TARGET_ENV="dev"
    RESOLVED_ENV_FILE="$(_find_secrets_file local || true)"
    return 0
  fi

  if grep -Fq 'const env = ConfigEnvironment.local;' "$MAIN_DART"; then
    RESOLVED_CONFIG_ENV="ConfigEnvironment.local"
    RESOLVED_APP_ENV="local"
    RESOLVED_TARGET_ENV="dev"
    RESOLVED_ENV_FILE="$(_find_secrets_file local || true)"
    return 0
  fi

  echo "Could not detect const env from lib/main.dart." >&2
  return 1
}

setup_flutter() {
  if command -v fvm >/dev/null 2>&1; then
    FLUTTER=(fvm flutter)
  else
    FLUTTER=(flutter)
  fi
  FLUTTER_VERSION="$("${FLUTTER[@]}" --version 2>/dev/null | head -n 1 || true)"
}

run_env_checks() {
  if [[ "${SKIP_CHECKS:-false}" == "true" ]]; then
    echo "Skipping environment checks (--skip-checks)."
    return 0
  fi
  if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
    return 0
  fi
  if [[ "$APP_PROFILE" != "configured" ]]; then
    return 0
  fi
  if [[ ! -f "$ROOT/test/environment_configuration_test.dart" ]]; then
    return 0
  fi

  local target_env="${RESOLVED_TARGET_ENV:-}"
  if [[ -z "$target_env" ]] && [[ -n "${ENV_FILE:-}" || -n "${RESOLVED_ENV_FILE:-}" ]]; then
    resolve_env_from_main || true
    target_env="${RESOLVED_TARGET_ENV:-prod}"
  fi
  if [[ -z "$target_env" ]]; then
    target_env="prod"
  fi

  echo "Running environment checks (TARGET_ENV=$target_env)..."
  flutter_cmd test test/environment_configuration_test.dart \
    --dart-define=TARGET_ENV="$target_env" 2>&1 | sed '/: loading /d'
}


run_ios_pod_install() {
  if [[ ! -d "$ROOT/ios" ]]; then
    echo "Skipping pod install — ios/ not found"
    return 0
  fi
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Skipping pod install — not macOS"
    return 0
  fi
  if ! command -v pod >/dev/null 2>&1; then
    echo "CocoaPods (pod) not found; install via: brew install cocoapods" >&2
    exit 1
  fi

  local ios_dir="$ROOT/ios"
  local pod_log pod_update_targets attempt
  pod_log="$(mktemp)"
  trap "rm -f '$pod_log'" RETURN
  pod_update_targets=(
    GoogleUtilities
    GoogleUtilities/Logger
    Firebase
    Firebase/CoreOnly
    FirebaseCore
    FirebaseCoreInternal
    FirebaseInstallations
    FirebaseMessaging
    TOCropViewController
  )

  run_pod() {
    (cd "$ios_dir" && "$@") >"$pod_log" 2>&1
  }

  show_pod_log() {
    cat "$pod_log"
  }

  is_cdn_error() {
    grep -qE 'CDN:|HTTP2 framing layer|Couldn\x27t download' "$pod_log"
  }

  retry_pod_install() {
    local max_attempts="${1:-3}"
    local attempt
    for attempt in $(seq 1 "$max_attempts"); do
      if run_pod pod install; then
        show_pod_log
        return 0
      fi
      show_pod_log >&2
      if is_cdn_error && [[ "$attempt" -lt "$max_attempts" ]]; then
        echo "CocoaPods CDN/network error (attempt ${attempt}/${max_attempts}) — retrying pod install..."
        sleep $((attempt * 5))
        continue
      fi
      return 1
    done
    return 1
  }

  # Prefer plain install — uses Podfile.lock and avoids CDN spec refreshes.
  if retry_pod_install 3; then
    echo "==> CocoaPods install completed."
    return 0
  fi

  if is_cdn_error; then
    echo "CocoaPods CDN still failing — skipping pod update (also hits CDN)." >&2
  else
    echo "pod install failed (often stale Podfile.lock after flutter pub get) — updating iOS pods..."
    if run_pod pod update "${pod_update_targets[@]}"; then
      show_pod_log
      echo "==> CocoaPods install completed."
      return 0
    fi
    show_pod_log >&2
    if retry_pod_install 2; then
      echo "==> CocoaPods install completed."
      return 0
    fi
  fi

  echo "Last resort: pod install --repo-update (refreshes CocoaPods spec repos)..."
  for attempt in 1 2 3; do
    if run_pod pod install --repo-update; then
      show_pod_log
      echo "==> CocoaPods install completed."
      return 0
    fi
    show_pod_log >&2
    if is_cdn_error && [[ "$attempt" -lt 3 ]]; then
      echo "CocoaPods CDN error (attempt ${attempt}/3) — retrying..."
      sleep $((attempt * 10))
      continue
    fi
    break
  done

  echo "CocoaPods install failed. Transient CDN errors often clear on retry: cd ios && pod install" >&2
  exit 1
}

run_clean_and_analyze() {
  local total_steps=3
  local analyze_step=3
  if [[ "${RUN_IOS_POD_INSTALL:-false}" == "true" ]]; then
    total_steps=4
    analyze_step=4
  fi

  echo "==> [1/${total_steps}] Cleaning project (flutter clean)..."
  flutter_cmd clean
  echo "==> Project cleaned successfully."

  echo "==> [2/${total_steps}] Resolving dependencies (flutter pub get)..."
  flutter_cmd pub get
  if [[ ! -f "$ROOT/.dart_tool/package_config.json" ]]; then
    echo "pub get did not produce .dart_tool/package_config.json — dependency resolution failed." >&2
    exit 1
  fi
  echo "==> Dependencies resolved successfully."

  if [[ "${RUN_IOS_POD_INSTALL:-false}" == "true" ]]; then
    echo "==> [3/${total_steps}] Running CocoaPods (pod install)..."
    run_ios_pod_install
  fi

  echo "==> [${analyze_step}/${total_steps}] Running analysis (dart analyze --no-fatal-warnings lib test)..."
  # Warnings must not fail the build (dart analyze defaults --fatal-warnings on).
  dart_cmd analyze --no-fatal-warnings lib test
  echo "==> Analysis passed successfully."
}

confirm_build() {
  if [[ "${SKIP_CONFIRM:-false}" == "true" ]]; then
    echo "SKIP_CONFIRM=true — continuing without prompt."
    return 0
  fi
  if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "CI environment detected — continuing without prompt."
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "Non-interactive shell — continuing without prompt."
    return 0
  fi

  while true; do
    if [[ "${RELEASE_CHECKLIST_FAILED:-false}" == "true" ]]; then
      read -r -p "Release checklist has failures. Continue anyway? [y/N]: " reply
    else
      read -r -p "Continue with this build? [y/N]: " reply
    fi
    case "$reply" in
      y|Y|yes|YES)
        echo "Starting build..."
        return 0
        ;;
      n|N|no|NO|"")
        echo "Build cancelled."
        exit 0
        ;;
      *)
        echo "Please answer y (yes) or n (no)."
        ;;
    esac
  done
}

print_secrets_summary() {
  local title="${1:-Flutter release build parameters}"
  echo ""
  echo "========== $title =========="
  echo "Project root:     $ROOT"
  echo "App profile:      $APP_PROFILE"
  if [[ -n "${RESOLVED_CONFIG_ENV:-}" ]]; then
    echo "main.dart env:    $RESOLVED_CONFIG_ENV"
  fi
  echo "Flutter:          ${FLUTTER[*]}"
  echo "Flutter version:  ${FLUTTER_VERSION:-unknown}"
  if [[ -n "${ENV_FILE:-}" ]]; then
    echo "Secrets file:     $ENV_FILE"
    echo ""
    echo "Dart defines from $ENV_FILE:"
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -z "$line" ]] && continue
      [[ "$line" != *"="* ]] && continue
      key="${line%%=*}"
      value="${line#*=}"
      printf '  %-24s %s\n' "$key" "$value"
    done < "$ENV_FILE"
  fi
  echo "=========================================================="
  _preflight=""
  if [[ -n "${_REPO_ROOT:-}" && -f "$_REPO_ROOT/lib/release_preflight_checklist.sh" ]]; then
    _preflight="$_REPO_ROOT/lib/release_preflight_checklist.sh"
  elif [[ -f "$ROOT/scripts/lib/release_preflight_checklist.sh" ]]; then
    _preflight="$ROOT/scripts/lib/release_preflight_checklist.sh"
  fi
  if [[ -n "$_preflight" ]]; then
    # shellcheck source=/dev/null
    source "$_preflight"
    print_release_preflight_checklist
  else
    _print_legacy_swipe_guide_checklist
  fi
  echo ""
}

_is_prod_release_build() {
  if [[ "${RESOLVED_TARGET_ENV:-}" == "prod" ]]; then
    return 0
  fi
  if [[ "${RESOLVED_CONFIG_ENV:-}" == "ConfigEnvironment.production" ]]; then
    return 0
  fi
  if [[ "${ENV_FILE:-}" == *".prod.env" ]]; then
    return 0
  fi
  return 1
}

_print_legacy_swipe_guide_checklist() {
  local prefs_file="$ROOT/lib/features/home-view-feature/presentation/pages/bottom-navigation-ui/home-view/view/bottom-sheet/home_sheet_swipe_guide_prefs.dart"
  local prefs_value
  if [[ ! -f "$prefs_file" ]]; then
    return 0
  fi
  prefs_value="$(grep -E 'const bool kHomeSheetSwipeGuideUseSharedPrefs = (true|false);' "$prefs_file" | head -1 | sed -E 's/.*= (true|false);/\1/')"
  [[ -z "$prefs_value" ]] && return 0
  echo "Release checklist:"
  if [[ "$prefs_value" == "true" ]]; then
    echo "  [OK]   kHomeSheetSwipeGuideUseSharedPrefs = true"
    return 0
  fi
  if _is_prod_release_build; then
    echo "  [FAIL] kHomeSheetSwipeGuideUseSharedPrefs = false — change to true before store release"
    RELEASE_CHECKLIST_FAILED="true"
    return 0
  fi
  echo "  [QA]   kHomeSheetSwipeGuideUseSharedPrefs = false — OK for local QA; set true before store release"
}

resolve_build_env() {
  detect_app_profile
  ENV_FILE="${ENV_FILE:-}"
  APP_ENV="${APP_ENV:-}"

  if [[ -z "$ENV_FILE" && "$APP_PROFILE" == "configured" ]]; then
    if ! resolve_env_from_main; then
      exit 1
    fi
    ENV_FILE="${RESOLVED_ENV_FILE:-}"
    APP_ENV="${APP_ENV:-$RESOLVED_APP_ENV}"
  fi

  if [[ -n "$ENV_FILE" && ! -f "$ENV_FILE" ]]; then
    echo "Missing env file: $ENV_FILE" >&2
    exit 1
  fi
}

build_args_with_secrets() {
  local array_name="$1"
  local -a tmp_args=(--release)

  if [[ -n "${ENV_FILE:-}" ]]; then
    tmp_args+=(--dart-define-from-file="$ENV_FILE")
    if [[ -n "${APP_ENV:-}" ]]; then
      tmp_args+=(--dart-define="APP_ENV=$APP_ENV")
    fi
  fi

  # Bash 3.2 (macOS) has no nameref (local -n); assign by array name.
  eval "${array_name}=(\"\${tmp_args[@]}\")"
}
