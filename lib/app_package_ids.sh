#!/usr/bin/env bash
#
# Resolve Android applicationId and iOS bundle identifier from this repo.
# Override with PACKAGE_NAME / BUNDLE_ID environment variables or CLI flags.

resolve_android_package_id() {
  local root="$1"
  local override="${2:-${PACKAGE_NAME:-}}"

  if [[ -n "$override" ]]; then
    echo "$override"
    return 0
  fi

  local gradle_file="$root/android/app/build.gradle"
  if [[ ! -f "$gradle_file" ]]; then
    echo "android/app/build.gradle not found under $root" >&2
    return 1
  fi

  local package_id
  package_id="$(
    grep -E 'applicationId\s*=' "$gradle_file" \
      | head -1 \
      | sed -E 's/.*"([^"]+)".*/\1/'
  )"

  if [[ -z "$package_id" ]]; then
    echo "Could not read applicationId from $gradle_file" >&2
    return 1
  fi

  echo "$package_id"
}

resolve_ios_bundle_id() {
  local root="$1"
  local override="${2:-${BUNDLE_ID:-}}"
  local build_mode="${3:-${BUILD_MODE:-debug}}"

  if [[ -n "$override" ]]; then
    echo "$override"
    return 0
  fi

  if [[ "$build_mode" == "release" ]]; then
    local release_cfg="$root/ios/Flutter/Release.xcconfig"
    if [[ -f "$release_cfg" ]]; then
      local release_id
      release_id="$(
        grep -E '^PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=' "$release_cfg" \
          | head -1 \
          | sed -E 's/^[^=]*=[[:space:]]*([^[:space:]]+).*/\1/'
      )"
      if [[ -n "$release_id" ]]; then
        echo "$release_id"
        return 0
      fi
    fi
  fi

  local pbxproj=""
  for candidate in \
    "$root/ios/Runner.xcodeproj/project.pbxproj" \
    "$root/ios"/*.xcodeproj/project.pbxproj
  do
    if [[ -f "$candidate" ]]; then
      pbxproj="$candidate"
      break
    fi
  done

  if [[ -z "$pbxproj" || ! -f "$pbxproj" ]]; then
    echo "No ios/*.xcodeproj/project.pbxproj found under $root" >&2
    return 1
  fi

  local bundle_id
  bundle_id="$(
    grep 'PRODUCT_BUNDLE_IDENTIFIER = ' "$pbxproj" \
      | grep -v RunnerTests \
      | head -1 \
      | sed -E 's/^[^=]*=[[:space:]]*([^;]+);/\1/' \
      | tr -d ' '
  )"

  if [[ -z "$bundle_id" ]]; then
    echo "Could not read PRODUCT_BUNDLE_IDENTIFIER from $pbxproj" >&2
    return 1
  fi

  echo "$bundle_id"
}
