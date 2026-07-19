# Example release.config.sh for a Flutter git package.
# Copy this folder (or just this file) to:
#   <flutter-scripts-root>/<your_package_id>/release.config.sh
# Then edit IDs, paths, and URLs for your package.
#
# See docs/PACKAGE_RELEASE.md

PR_PACKAGE_ID="my_package"
PR_PACKAGE_TITLE="My Package"
PR_PACKAGE_DESCRIPTION="Example Flutter git package release config"

PR_REPO_ENV_VAR="MY_PACKAGE_REPO"
PR_DEFAULT_REPO="${MY_PACKAGE_REPO:-$HOME/Documents/flutter-packages/my_package}"

PR_GITHUB_GIT_URL="https://github.com/your-org/my_package.git"
PR_HOST_PUBSPEC_KEY="my_package"
PR_HOST_APP_HINT="flutter pub get"

PR_TAG_PREFIX="v"
PR_VERSION_FILE_PUBSPEC="pubspec.yaml"
PR_CHANGELOG_FILE="CHANGELOG.md"

PR_VERSION_EXTRA_FILES=(
  "ios/my_package.podspec|podspec_ruby"
)

PR_DART_ANALYZE_PATHS="lib test"
PR_DART_FORMAT_PATHS="lib test"
PR_CHANNEL_CONTRACT_TOOL=""
PR_FLUTTER_TEST="true"
PR_ANDROID_GRADLE_TASK=""
PR_ANDROID_GRADLE_DIR="android"
