/**
 * Shared script meta for the GUI (when / help / git links / failure hints).
 * Keep descriptions aligned with tools/flutter_scripts_gui/shared/script_catalog.json
 * and Go catalog when editing.
 */

export type GitDeepLink = {
  tab: 'howto' | 'troubleshoot'
  id: string
  label: string
}

export type ScriptExtraMeta = {
  /** Short flag / usage tip in the run panel */
  help?: string
  gitLinks?: GitDeepLink[]
  /** Shown after non-zero exit */
  onFail?: {
    message: string
    gitLinks?: GitDeepLink[]
    workflowId?: string
  }
}

export const SCRIPT_EXTRA: Record<string, ScriptExtraMeta> = {
  'setup.sh': {
    help: 'Optional --project PATH · --no-global to skip ~/.local/bin',
  },
  'install_global.sh': {
    help: 'Default --in-place relinks without copying the repo',
  },
  'setup_packages.sh': {
    help: 'Reads packages.list · use --update to git pull existing clones',
  },
  'device-logs.sh': {
    help: 'Positional: android | ios · optional -d DEVICE, -p PACKAGE, --wait, --clear',
    onFail: {
      message: 'Check device connection and that the app package/bundle is running.',
      workflowId: 'debug',
    },
  },
  'android-logcat.sh': {
    help: 'Optional -d SERIAL, -p PACKAGE, --clear, --wait',
  },
  'ios-device-logs.sh': {
    help: 'Optional -d DEVICE, -b BUNDLE_ID, --release, --clear',
  },
  'open-isolate-monitor.sh': {
    help: '--debug / --profile / --release-build · -d DEVICE · --no-deploy · --uri WS',
    onFail: {
      message: 'Confirm flutter devices and that deploy/VM service URI is reachable.',
      workflowId: 'debug',
    },
  },
  'build_mobile_release.sh': {
    help: '--env prod|dev · positional apk|ipa · optional --skip-checks',
    onFail: {
      message: 'Check secrets/env files and Flutter/Xcode toolchain for the target.',
      workflowId: 'build-app',
    },
  },
  'build_android.sh': {
    help: 'Optional --aab · --rtk · --skip-checks',
    onFail: {
      message: 'Check Android signing/env and run with verbose Flutter output if needed.',
      workflowId: 'build-app',
    },
  },
  'build_ios.sh': {
    help: 'Optional --rtk · --skip-checks (needs macOS + Xcode)',
    onFail: {
      message: 'Check Xcode signing, provisioning, and iOS env/secrets.',
      workflowId: 'build-app',
    },
  },
  'build_both_release_apks.sh': {
    help: 'Set FLUTTER_APP_A_DIR / FLUTTER_APP_B_DIR · --app-a-only / --app-b-only',
  },
  'inspect_apk_environment.sh': {
    help: 'Requires positional APK path',
  },
  'classify_version_bump.sh': {
    help: 'Optional --apply-env --env prod|dev · --verbose · --yes',
  },
  'clear_pub_cache.sh': {
    help: 'Prefer --repair before --full · --git-pattern · --yes',
    onFail: {
      message: 'Retry with --repair, or check disk permissions on the pub cache.',
      workflowId: 'deps',
    },
  },
  'release_package.sh': {
    help: 'Requires */release.config.sh · --list · --dry-run · --package ID · patch|minor|major',
    gitLinks: [
      { tab: 'howto', id: 'tags', label: 'Create and push tags' },
      { tab: 'howto', id: 'pr-create', label: 'Create a pull request' },
    ],
    onFail: {
      message: 'Use --dry-run first. Check git clean state and remote auth.',
      gitLinks: [
        { tab: 'howto', id: 'status', label: 'Check status' },
        { tab: 'howto', id: 'config-user', label: 'Configure user.name / email' },
        { tab: 'troubleshoot', id: 'auth-failed', label: 'Auth failure' },
        { tab: 'troubleshoot', id: 'push-rejected', label: 'Push rejected' },
      ],
    },
  },
  'check_localization.sh': {
    help: '--mode hardcoded|full|suggestions · --json · optional --path under lib/',
  },
  'check_git_identity.sh': {
    help: 'No args — compares git author vs gh account',
    gitLinks: [
      { tab: 'howto', id: 'config-user', label: 'Configure user.name / email' },
      { tab: 'troubleshoot', id: 'auth-failed', label: 'Auth / SSH failure' },
    ],
  },
  'get_iam_token.sh': {
    help: 'Runs tool/get_iam_token.dart in the active project (if present)',
  },
  'install-device-logs-global.sh': {
    help: 'Installs only device-log wrappers to ~/.local/bin',
  },
}

export function extraFor(file: string): ScriptExtraMeta | undefined {
  const base = file.replace(/\\/g, '/').split('/').pop() || file
  return SCRIPT_EXTRA[base]
}
