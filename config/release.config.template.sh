# Copy to <package_id>/release.config.sh next to this repo root and edit.
# Used by release_package.sh — do not run this template directly.
#
# Example layout:
#   flutter-scripts/
#     release_package.sh
#     my_maps/release.config.sh   ← discovered automatically

PR_PACKAGE_ID="my_package"
PR_PACKAGE_TITLE="my_package"
PR_PACKAGE_DESCRIPTION="Short description for the release menu"

# Checkout path: export MY_PACKAGE_REPO to override the default below.
PR_REPO_ENV_VAR="MY_PACKAGE_REPO"
PR_DEFAULT_REPO="${MY_PACKAGE_REPO:-$HOME/Documents/flutter-packages/my_package}"

PR_GITHUB_GIT_URL="https://github.com/your-org/my_package.git"
PR_HOST_PUBSPEC_KEY="my_package"
PR_HOST_APP_HINT="fvm flutter pub get && cd ios && pod install && full rebuild"

PR_TAG_PREFIX="v"
PR_VERSION_FILE_PUBSPEC="pubspec.yaml"
PR_CHANGELOG_FILE="CHANGELOG.md"

# Extra files to bump with the same semver: "path|kind"
# Supported kinds: podspec_ruby
PR_VERSION_EXTRA_FILES=(
  "ios/my_package.podspec|podspec_ruby"
)

# Quality checks (omit or leave empty to skip)
PR_DART_ANALYZE_PATHS="lib test"
PR_DART_FORMAT_PATHS="lib test"
PR_CHANNEL_CONTRACT_TOOL="tool/check_channel_contract.dart"
PR_FLUTTER_TEST="true"
PR_ANDROID_GRADLE_TASK=""
PR_ANDROID_GRADLE_DIR="android"

# Optional hooks (define in this file if needed):
# pr_package_preflight_extra() { ... }
# pr_package_run_checks_extra() { ... }
