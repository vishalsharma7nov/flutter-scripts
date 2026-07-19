#!/usr/bin/env bash
# Shared release engine for Flutter git packages.
# Loaded by release_package.sh — do not run directly.

if [[ -n "${PACKAGE_RELEASE_LIB_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
PACKAGE_RELEASE_LIB_LOADED=1

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bash_compat.sh
source "$_lib_dir/bash_compat.sh"
unset _lib_dir

pr_log_step() { echo ""; echo "== $1 =="; }
pr_log_ok() { echo "  [OK]   $1"; }
pr_log_fail() { echo "  [FAIL] $1" >&2; }
pr_log_skip() { echo "  [SKIP] $1"; }
pr_log_plan() { echo "  [PLAN] $1"; }

pr_confirm_or_abort() {
  local prompt="$1"
  if [[ "${PR_ASSUME_YES:-false}" == "true" ]] || [[ "${PR_DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    pr_log_fail "Non-interactive shell — pass -y to confirm: $prompt"
    exit 1
  fi
  printf '%s [y/N] ' "$prompt"
  local answer
  read -r answer
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) echo "Aborted."; exit 1 ;;
  esac
}

pr_has_dirty_tree() {
  ! git diff --quiet || ! git diff --cached --quiet
}

pr_has_untracked() {
  [[ -n "$(git ls-files --others --exclude-standard)" ]]
}

pr_flutter_cmd() {
  local root="${PR_REPO_ROOT:?}"
  if command -v fvm >/dev/null 2>&1 && [[ -f "$root/.fvmrc" || -f "$root/.fvm/fvm_config.json" ]]; then
    (cd "$root" && fvm flutter "$@")
  else
    (cd "$root" && flutter "$@")
  fi
}

pr_dart_cmd() {
  local root="${PR_REPO_ROOT:?}"
  if command -v fvm >/dev/null 2>&1 && [[ -f "$root/.fvmrc" || -f "$root/.fvm/fvm_config.json" ]]; then
    (cd "$root" && fvm dart "$@")
  else
    (cd "$root" && dart "$@")
  fi
}

pr_read_pubspec_version() {
  awk '/^version: / { print $2; exit }' "${PR_REPO_ROOT}/${PR_VERSION_FILE_PUBSPEC:-pubspec.yaml}"
}

pr_bump_semver() {
  local current="$1" bump="${PR_BUMP:-patch}"
  if [[ ! "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    pr_log_fail "Invalid semver in pubspec: $current"
    exit 1
  fi
  local major minor patch
  IFS='.' read -r major minor patch <<< "$current"
  case "$bump" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    *) pr_log_fail "Unknown bump: $bump"; exit 1 ;;
  esac
  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

pr_release_tag() {
  printf '%s%s\n' "${PR_TAG_PREFIX:-v}" "$1"
}

pr_apply_version_to_pubspec() {
  local file="${PR_REPO_ROOT}/${PR_VERSION_FILE_PUBSPEC:-pubspec.yaml}"
  local version="$1"
  sed -i.bak "s/^version: .*/version: ${version}/" "$file" && rm -f "${file}.bak"
}

pr_apply_version_extra_file() {
  local rel="$1" kind="$2" version="$3"
  local file="${PR_REPO_ROOT}/${rel}"
  [[ -f "$file" ]] || return 0
  case "$kind" in
    podspec_ruby)
      sed -i.bak "s/s.version[[:space:]]*=.*/s.version          = '${version}'/" "$file" && rm -f "${file}.bak"
      ;;
    *)
      pr_log_skip "Unknown version file kind '$kind' for $rel"
      ;;
  esac
}

pr_read_podspec_version() {
  awk -F"'" '/s\.version/ { print $2; exit }' "$1"
}

pr_prepend_changelog() {
  local section="$1"
  local file="${PR_REPO_ROOT}/${PR_CHANGELOG_FILE:-CHANGELOG.md}"
  if [[ -f "$file" ]]; then
    printf '%s%s' "$section" "$(cat "$file")" > "${file}.tmp"
    mv "${file}.tmp" "$file"
  else
    printf '%s' "$section" > "$file"
  fi
}

pr_verify_versions() {
  local expected="$1"
  local pubspec_ver
  pubspec_ver="$(pr_read_pubspec_version)"
  if [[ "$pubspec_ver" != "$expected" ]]; then
    pr_log_fail "pubspec version mismatch (expected $expected, got $pubspec_ver)"
    exit 1
  fi
  pr_log_ok "pubspec.yaml: $pubspec_ver"

  if array_not_empty PR_VERSION_EXTRA_FILES; then
    local entry rel kind path pod_ver
    for entry in "${PR_VERSION_EXTRA_FILES[@]}"; do
      rel="${entry%%|*}"
      kind="${entry#*|}"
      path="${PR_REPO_ROOT}/${rel}"
      [[ -f "$path" ]] || continue
      case "$kind" in
        podspec_ruby)
          pod_ver="$(pr_read_podspec_version "$path")"
          if [[ "$pod_ver" != "$expected" ]]; then
            pr_log_fail "$rel version mismatch (expected $expected, got $pod_ver)"
            exit 1
          fi
          pr_log_ok "$rel: $pod_ver"
          ;;
      esac
    done
  fi

  local changelog="${PR_REPO_ROOT}/${PR_CHANGELOG_FILE:-CHANGELOG.md}"
  if [[ -f "$changelog" ]]; then
    local head
    head="$(awk '/^## / { sub(/^## /,""); print; exit }' "$changelog")"
    if [[ "$head" != "$expected" ]]; then
      pr_log_fail "CHANGELOG top section mismatch (expected $expected, got $head)"
      exit 1
    fi
    pr_log_ok "CHANGELOG: $head"
  fi
}

pr_build_changelog_bullets() {
  PR_RELEASE_BULLETS=()
  local last_tag="${PR_LAST_TAG:-}"

  if [[ -n "${PR_NOTES_FILE:-}" ]]; then
    [[ -f "$PR_NOTES_FILE" ]] || { pr_log_fail "Notes file not found: $PR_NOTES_FILE"; exit 1; }
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line#- }"
      line="${line#"${line%%[![:space:]]*}"}"
      [[ -z "$line" ]] && continue
      PR_RELEASE_BULLETS+=("$line")
    done < "$PR_NOTES_FILE"
  elif [[ -n "${PR_NOTES:-}" ]]; then
    local part
    IFS=';' read -ra parts <<< "$PR_NOTES"
    for part in "${parts[@]}"; do
      part="${part#"${part%%[![:space:]]*}"}"
      part="${part%"${part##*[![:space:]]}"}"
      [[ -n "$part" ]] && PR_RELEASE_BULLETS+=("$part")
    done
  elif [[ -n "$last_tag" ]]; then
    local subject
    while IFS= read -r subject; do
      [[ -z "$subject" ]] && continue
      [[ "$subject" =~ ^[Rr]elease[[:space:]]v ]] && continue
      PR_RELEASE_BULLETS+=("$subject")
    done < <(git -C "$PR_REPO_ROOT" log "${last_tag}..HEAD" --pretty=format:'%s' --no-merges)
  fi

  if ! array_not_empty PR_RELEASE_BULLETS; then
    PR_RELEASE_BULLETS+=("${PR_RELEASE_TITLE:-${PR_PACKAGE_TITLE} release}")
  fi
}

pr_resolve_release_title() {
  local new_version="$1"
  local last_tag="${PR_LAST_TAG:-}"
  if [[ -n "${PR_TITLE:-}" ]]; then
    PR_RELEASE_TITLE="$PR_TITLE"
    return
  fi
  if [[ -n "$last_tag" ]]; then
    PR_RELEASE_TITLE="$(git -C "$PR_REPO_ROOT" log "${last_tag}..HEAD" --pretty=format:'%s' --no-merges | grep -vi '^release v' | head -n 1 || true)"
  fi
  if [[ -z "${PR_RELEASE_TITLE:-}" ]]; then
    PR_RELEASE_TITLE="${PR_PACKAGE_TITLE:-package} ${new_version}"
  fi
}

pr_resolve_code_commit_message() {
  if [[ -n "${PR_CODE_MESSAGE:-}" ]]; then
    printf '%s\n' "$PR_CODE_MESSAGE"
    return
  fi
  if [[ -n "${PR_TITLE:-}" ]]; then
    printf '%s\n' "$PR_TITLE"
    return
  fi
  printf '%s\n' "Update ${PR_PACKAGE_TITLE:-package} before release."
}

pr_preflight() {
  pr_log_step "Preflight — ${PR_PACKAGE_ID}"

  if [[ "${PR_BRANCH:-}" == "HEAD" || -z "${PR_BRANCH:-}" ]]; then
    pr_log_fail "Detached HEAD — checkout a branch before releasing."
    exit 1
  fi
  pr_log_ok "Branch: ${PR_BRANCH}"

  local git_name git_email
  git_name="$(git -C "$PR_REPO_ROOT" config --get user.name 2>/dev/null || true)"
  git_email="$(git -C "$PR_REPO_ROOT" config --get user.email 2>/dev/null || true)"
  if [[ -z "$git_name" || -z "$git_email" ]]; then
    pr_log_fail "git user.name and user.email must be set."
    exit 1
  fi
  pr_log_ok "Commit identity: $git_name <$git_email>"

  if ! git -C "$PR_REPO_ROOT" remote get-url "${PR_REMOTE:-origin}" >/dev/null 2>&1; then
    pr_log_fail "Remote '${PR_REMOTE:-origin}' is not configured."
    exit 1
  fi
  pr_log_ok "Remote ${PR_REMOTE:-origin}: $(git -C "$PR_REPO_ROOT" remote get-url "${PR_REMOTE:-origin}")"

  if git -C "$PR_REPO_ROOT" rev-parse --verify "${PR_REMOTE:-origin}/${PR_BRANCH}" >/dev/null 2>&1; then
    pr_log_ok "Upstream ${PR_REMOTE:-origin}/${PR_BRANCH} exists"
  else
    pr_log_skip "No upstream ${PR_REMOTE:-origin}/${PR_BRANCH} yet (first push will use -u)"
  fi

  if command -v gh >/dev/null 2>&1 && gh auth status -h github.com >/dev/null 2>&1; then
    pr_log_ok "gh CLI authenticated"
  else
    pr_log_skip "gh CLI not authenticated (git push still works with SSH/HTTPS)"
  fi

  if declare -F pr_package_preflight_extra >/dev/null 2>&1; then
    pr_package_preflight_extra
  fi
}

pr_commit_dirty_code() {
  pr_log_step "Code commit"
  if ! pr_has_dirty_tree && ! pr_has_untracked; then
    pr_log_ok "Working tree clean"
    return
  fi
  if [[ "${PR_AUTO_COMMIT_CODE:-true}" != "true" ]]; then
    pr_log_fail "Working tree is not clean. Commit or stash, or omit --no-auto-commit."
    git -C "$PR_REPO_ROOT" status --short
    exit 1
  fi
  local msg
  msg="$(pr_resolve_code_commit_message)"
  pr_log_plan "Commit all changes: $msg"
  git -C "$PR_REPO_ROOT" status --short
  if [[ "${PR_DRY_RUN:-false}" == "true" ]]; then
    pr_log_skip "Dry run — code commit skipped"
    return
  fi
  pr_confirm_or_abort "Create code commit?"
  git -C "$PR_REPO_ROOT" add -A
  git -C "$PR_REPO_ROOT" commit -m "$msg"
  pr_log_ok "Code commit created"
}

pr_run_checks() {
  pr_log_step "Quality checks"
  if [[ "${PR_SKIP_CHECKS:-false}" == "true" ]]; then
    pr_log_skip "Checks disabled (--skip-checks)"
    return
  fi
  if [[ "${PR_DRY_RUN:-false}" == "true" ]]; then
    [[ -n "${PR_DART_ANALYZE_PATHS:-}" ]] && pr_log_plan "dart analyze --fatal-warnings $PR_DART_ANALYZE_PATHS"
    [[ -n "${PR_CHANNEL_CONTRACT_TOOL:-}" ]] && pr_log_plan "dart run $PR_CHANNEL_CONTRACT_TOOL"
    [[ "${PR_FLUTTER_TEST:-false}" == "true" ]] && pr_log_plan "flutter test"
    [[ -n "${PR_ANDROID_GRADLE_TASK:-}" ]] && pr_log_plan "cd ${PR_ANDROID_GRADLE_DIR:-android} && ./gradlew $PR_ANDROID_GRADLE_TASK"
    return
  fi
  if ! command -v flutter >/dev/null 2>&1 && ! command -v fvm >/dev/null 2>&1; then
    pr_log_fail "flutter/fvm not found — install or pass --skip-checks"
    exit 1
  fi

  pr_log_ok "flutter pub get"
  pr_flutter_cmd pub get

  if [[ -n "${PR_DART_FORMAT_PATHS:-}" ]]; then
    pr_log_ok "dart format"
    # shellcheck disable=SC2086
    pr_dart_cmd format $PR_DART_FORMAT_PATHS
  fi

  if [[ -n "${PR_DART_ANALYZE_PATHS:-}" ]]; then
    pr_log_ok "dart analyze"
    # shellcheck disable=SC2086
    pr_dart_cmd analyze --fatal-warnings $PR_DART_ANALYZE_PATHS
  fi

  if [[ -n "${PR_CHANNEL_CONTRACT_TOOL:-}" && -f "${PR_REPO_ROOT}/${PR_CHANNEL_CONTRACT_TOOL}" ]]; then
    pr_log_ok "channel contract"
    pr_dart_cmd run "$PR_CHANNEL_CONTRACT_TOOL"
  fi

  if [[ "${PR_FLUTTER_TEST:-false}" == "true" ]]; then
    pr_log_ok "flutter test"
    pr_flutter_cmd test
  fi

  local gradle_dir="${PR_ANDROID_GRADLE_DIR:-android}"
  if [[ -n "${PR_ANDROID_GRADLE_TASK:-}" && -f "${PR_REPO_ROOT}/${gradle_dir}/gradlew" ]]; then
    pr_log_ok "Android: ./gradlew ${PR_ANDROID_GRADLE_TASK}"
    (cd "${PR_REPO_ROOT}/${gradle_dir}" && ./gradlew "$PR_ANDROID_GRADLE_TASK")
  fi

  if declare -F pr_package_run_checks_extra >/dev/null 2>&1; then
    pr_package_run_checks_extra
  fi

  pr_log_ok "All checks passed"
}

pr_apply_version_bump() {
  local version="$1"
  pr_apply_version_to_pubspec "$version"
  if array_not_empty PR_VERSION_EXTRA_FILES; then
    local entry rel kind
    for entry in "${PR_VERSION_EXTRA_FILES[@]}"; do
      rel="${entry%%|*}"
      kind="${entry#*|}"
      pr_apply_version_extra_file "$rel" "$kind" "$version"
    done
  fi
  pr_prepend_changelog "${PR_CHANGELOG_SECTION}"
}

pr_git_add_version_files() {
  git -C "$PR_REPO_ROOT" add "${PR_VERSION_FILE_PUBSPEC:-pubspec.yaml}"
  [[ -f "${PR_REPO_ROOT}/${PR_CHANGELOG_FILE:-CHANGELOG.md}" ]] && \
    git -C "$PR_REPO_ROOT" add "${PR_CHANGELOG_FILE:-CHANGELOG.md}"
  if array_not_empty PR_VERSION_EXTRA_FILES; then
    local entry rel
    for entry in "${PR_VERSION_EXTRA_FILES[@]}"; do
      rel="${entry%%|*}"
      [[ -f "${PR_REPO_ROOT}/${rel}" ]] && git -C "$PR_REPO_ROOT" add "$rel"
    done
  fi
}

pr_create_release_commit_and_tag() {
  pr_git_add_version_files
  git -C "$PR_REPO_ROOT" commit -m "$(cat <<EOF
${PR_RELEASE_SUBJECT}

${PR_RELEASE_BODY}
EOF
)"
  git -C "$PR_REPO_ROOT" tag -a "${PR_RELEASE_TAG}" -m "${PR_RELEASE_SUBJECT}"
  pr_log_ok "Release commit + tag ${PR_RELEASE_TAG}"
}

pr_push_release() {
  pr_log_step "Push"
  local remote="${PR_REMOTE:-origin}" branch="${PR_BRANCH}"
  if [[ "${PR_NO_PUSH:-false}" == "true" ]]; then
    pr_log_skip "Push disabled (--no-push)"
    echo "  git -C \"$PR_REPO_ROOT\" push -u ${remote} ${branch}"
    echo "  git -C \"$PR_REPO_ROOT\" push ${remote} ${PR_RELEASE_TAG}"
    return
  fi
  if [[ "${PR_DRY_RUN:-false}" == "true" ]]; then
    pr_log_plan "git push ${remote} ${branch}"
    pr_log_plan "git push ${remote} ${PR_RELEASE_TAG}"
    return
  fi
  if git -C "$PR_REPO_ROOT" rev-parse --verify "${remote}/${branch}" >/dev/null 2>&1; then
    git -C "$PR_REPO_ROOT" push "$remote" "$branch"
  else
    git -C "$PR_REPO_ROOT" push -u "$remote" "$branch"
  fi
  git -C "$PR_REPO_ROOT" push "$remote" "${PR_RELEASE_TAG}"
  if git -C "$PR_REPO_ROOT" ls-remote --tags "$remote" "refs/tags/${PR_RELEASE_TAG}" | grep -q "${PR_RELEASE_TAG}"; then
    pr_log_ok "Tag ${PR_RELEASE_TAG} verified on ${remote}"
  else
    pr_log_fail "Tag ${PR_RELEASE_TAG} not found on ${remote} after push"
    exit 1
  fi
  pr_log_ok "Pushed ${branch} and ${PR_RELEASE_TAG}"
}

pr_print_host_snippet() {
  [[ "${PR_DRY_RUN:-false}" == "true" || "${PR_NO_PUSH:-false}" == "true" ]] && return
  local key="${PR_HOST_PUBSPEC_KEY:-${PR_PACKAGE_ID}}"
  local url="${PR_GITHUB_GIT_URL:-}"
  cat <<EOF

Update host pubspec.yaml:

  ${key}:
    git:
      url: ${url}
      ref: ${PR_RELEASE_TAG}

Host follow-up: ${PR_HOST_APP_HINT:-fvm flutter pub get}
EOF
}

pr_print_plan_summary() {
  pr_log_step "Release plan — ${PR_PACKAGE_ID}"
  echo "  Repo:     ${PR_REPO_ROOT}"
  echo "  Branch:   ${PR_BRANCH}"
  echo "  Remote:   ${PR_REMOTE:-origin}"
  echo "  Version:  ${PR_OLD_VERSION} → ${PR_NEW_VERSION}"
  echo "  Tag:      ${PR_RELEASE_TAG}"
  [[ -n "${PR_LAST_TAG:-}" ]] && echo "  Since:    ${PR_LAST_TAG}"
  echo "  Subject:  ${PR_RELEASE_SUBJECT}"
  echo ""
  echo "CHANGELOG:"
  printf '%s' "${PR_CHANGELOG_SECTION}"
}

pr_run_release_pipeline() {
  local root="${PR_REPO_ROOT:?}"
  [[ -d "$root/.git" ]] || { pr_log_fail "Not a git repo: $root"; exit 1; }

  PR_BRANCH="${PR_BRANCH:-$(git -C "$root" rev-parse --abbrev-ref HEAD)}"
  PR_LAST_TAG="$(git -C "$root" describe --tags --abbrev=0 2>/dev/null || true)"

  pr_preflight
  pr_commit_dirty_code
  pr_run_checks

  PR_OLD_VERSION="$(pr_read_pubspec_version)"
  PR_NEW_VERSION="$(pr_bump_semver "$PR_OLD_VERSION")"
  PR_RELEASE_TAG="$(pr_release_tag "$PR_NEW_VERSION")"

  if [[ -n "$PR_LAST_TAG" && "$PR_LAST_TAG" == "$PR_RELEASE_TAG" ]]; then
    pr_log_fail "Tag $PR_RELEASE_TAG already exists"
    exit 1
  fi
  if git -C "$root" rev-parse "$PR_RELEASE_TAG" >/dev/null 2>&1; then
    pr_log_fail "Local tag $PR_RELEASE_TAG already exists"
    exit 1
  fi

  pr_resolve_release_title "$PR_NEW_VERSION"
  pr_build_changelog_bullets
  PR_RELEASE_SUBJECT="Release ${PR_RELEASE_TAG}: ${PR_RELEASE_TITLE}"
  PR_RELEASE_BODY=""
  local bullet
  for bullet in "${PR_RELEASE_BULLETS[@]}"; do
    PR_RELEASE_BODY+="- ${bullet}"$'\n'
  done
  PR_CHANGELOG_SECTION="## ${PR_NEW_VERSION}"$'\n\n'
  for bullet in "${PR_RELEASE_BULLETS[@]}"; do
    PR_CHANGELOG_SECTION+="- ${bullet}"$'\n'
  done
  PR_CHANGELOG_SECTION+=$'\n'

  pr_print_plan_summary

  if [[ "${PR_DRY_RUN:-false}" == "true" ]]; then
    echo ""
    pr_log_skip "Dry run complete."
    return 0
  fi

  pr_confirm_or_abort "Release ${PR_OLD_VERSION} → ${PR_NEW_VERSION} as ${PR_RELEASE_TAG}?"

  pr_log_step "Version bump"
  pr_apply_version_bump "$PR_NEW_VERSION"
  pr_verify_versions "$PR_NEW_VERSION"

  pr_log_step "Release commit"
  pr_create_release_commit_and_tag

  pr_push_release
  pr_print_host_snippet
}
