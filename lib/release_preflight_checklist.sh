#!/usr/bin/env bash
# Release preflight checks — sourced by build scripts.
#
# Expects ROOT; optional ENV_FILE, ENV_NAME, RESOLVED_CONFIG_ENV, RESOLVED_TARGET_ENV.
# Sets RELEASE_CHECKLIST_FAILED=true when a prod-bound check fails.

_release_preflight_fail() {
  echo "  [FAIL] $1"
  RELEASE_CHECKLIST_FAILED="true"
}

_release_preflight_ok() {
  echo "  [OK]   $1"
}

_release_preflight_qa() {
  echo "  [QA]   $1"
}

_is_prod_release_build() {
  case "${ENV_NAME:-}" in
    prod|production) return 0 ;;
  esac
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

_resolve_config_env_from_main() {
  local main_dart="$ROOT/lib/main.dart"
  if [[ ! -f "$main_dart" ]]; then
    return 1
  fi
  if grep -Fq 'const env = ConfigEnvironment.production;' "$main_dart"; then
    echo "ConfigEnvironment.production"
    return 0
  fi
  if grep -Fq 'const env = ConfigEnvironment.dev;' "$main_dart"; then
    echo "ConfigEnvironment.dev"
    return 0
  fi
  if grep -Fq 'const env = ConfigEnvironment.staging;' "$main_dart"; then
    echo "ConfigEnvironment.staging"
    return 0
  fi
  if grep -Fq 'const env = ConfigEnvironment.local;' "$main_dart"; then
    echo "ConfigEnvironment.local"
    return 0
  fi
  return 1
}

_read_env_file_value() {
  local key="$1"
  local line
  if [[ -z "${ENV_FILE:-}" || ! -f "$ENV_FILE" ]]; then
    return 1
  fi
  line="$(grep -E "^${key}=" "$ENV_FILE" | head -1 || true)"
  [[ -z "$line" ]] && return 1
  echo "${line#*=}"
}

_read_dart_bool_const() {
  local file="$1"
  local const_name="$2"
  if [[ ! -f "$file" ]]; then
    return 1
  fi
  grep -E "const bool ${const_name} = (true|false);" "$file" \
    | head -1 \
    | sed -E "s/.*= (true|false);/\\1/"
}

_check_main_dart_env() {
  local config_env="${RESOLVED_CONFIG_ENV:-}"
  if [[ -z "$config_env" ]]; then
    config_env="$(_resolve_config_env_from_main || true)"
  fi
  if [[ -z "$config_env" ]]; then
    _release_preflight_fail "Could not read const env from lib/main.dart"
    return
  fi

  if _is_prod_release_build; then
    if [[ "$config_env" == "ConfigEnvironment.production" ]]; then
      _release_preflight_ok "main.dart const env = ConfigEnvironment.production"
    else
      _release_preflight_fail "main.dart const env must be ConfigEnvironment.production for store release (currently $config_env)"
    fi
    return
  fi

  _release_preflight_ok "main.dart const env = $config_env"
}

_check_secrets_file() {
  if [[ -z "${ENV_FILE:-}" ]]; then
    return
  fi

  if _is_prod_release_build; then
    if [[ "$ENV_FILE" == *".prod.env" ]]; then
      _release_preflight_ok "Secrets file uses .prod.env"
    else
      _release_preflight_fail "Secrets file must be .secrets/*.prod.env for store release (currently $ENV_FILE)"
    fi
    return
  fi

  if [[ "$ENV_FILE" == *".local.env" ]]; then
    _release_preflight_ok "Secrets file uses .local.env"
  else
    _release_preflight_qa "Secrets file is not .local.env ($ENV_FILE)"
  fi
}

_check_app_env_in_secrets() {
  local app_env
  app_env="$(_read_env_file_value APP_ENV || true)"
  [[ -z "$app_env" ]] && return

  if _is_prod_release_build; then
    if [[ "$app_env" == "production" ]]; then
      _release_preflight_ok "APP_ENV = production"
    else
      _release_preflight_fail "APP_ENV in secrets must be production for store release (currently $app_env)"
    fi
    return
  fi

  if [[ "$app_env" == "development" ]]; then
    _release_preflight_ok "APP_ENV = development"
  else
    _release_preflight_qa "APP_ENV = $app_env (expected development for local QA)"
  fi
}

_check_adyen_client_key() {
  local key
  key="$(_read_env_file_value ADYEN_CLIENT_KEY || true)"
  [[ -z "$key" ]] && return

  if _is_prod_release_build; then
    if [[ "$key" == live_* ]]; then
      _release_preflight_ok "ADYEN_CLIENT_KEY uses live_ prefix"
    else
      _release_preflight_fail "ADYEN_CLIENT_KEY must start with live_ for store release"
    fi
    return
  fi

  if [[ "$key" == test_* ]]; then
    _release_preflight_ok "ADYEN_CLIENT_KEY uses test_ prefix"
  else
    _release_preflight_qa "ADYEN_CLIENT_KEY does not use test_ prefix"
  fi
}

_check_home_sheet_swipe_guide_prefs() {
  local prefs_file="$ROOT/lib/features/home-view-feature/presentation/pages/bottom-navigation-ui/home-view/view/bottom-sheet/home_sheet_swipe_guide_prefs.dart"
  local enabled_value use_shared_prefs_value

  enabled_value="$(_read_dart_bool_const "$prefs_file" kHomeSheetSwipeGuideEnabled || true)"
  use_shared_prefs_value="$(_read_dart_bool_const "$prefs_file" kHomeSheetSwipeGuideUseSharedPrefs || true)"
  if [[ -z "$enabled_value" && -z "$use_shared_prefs_value" ]]; then
    return
  fi

  if [[ "$enabled_value" == "true" ]]; then
    _release_preflight_ok "kHomeSheetSwipeGuideEnabled = true"
  elif _is_prod_release_build; then
    _release_preflight_fail "kHomeSheetSwipeGuideEnabled must be true for store release"
  else
    _release_preflight_qa "kHomeSheetSwipeGuideEnabled = false — coach mark hidden"
  fi

  if [[ "$use_shared_prefs_value" == "true" ]]; then
    _release_preflight_ok "kHomeSheetSwipeGuideUseSharedPrefs = true"
  elif _is_prod_release_build; then
    _release_preflight_fail "kHomeSheetSwipeGuideUseSharedPrefs must be true for store release"
  else
    _release_preflight_qa "kHomeSheetSwipeGuideUseSharedPrefs = false — OK for local QA; set true before store release"
  fi
}

print_release_preflight_checklist() {
  RELEASE_CHECKLIST_FAILED="false"
  echo "Release checklist:"
  _check_main_dart_env
  _check_secrets_file
  _check_app_env_in_secrets
  _check_adyen_client_key
  _check_home_sheet_swipe_guide_prefs
}
