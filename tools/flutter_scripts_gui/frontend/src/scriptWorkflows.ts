/** Groups scripts into “when to use” workflows for the Scripts page. */

export type WorkflowStep = {
  /** basename matching ScriptItem.file */
  file: string
  /** Short “use this when…” line */
  when: string
  tip?: string
  /** Prefer this script first within its workflow */
  recommended?: boolean
}

export type ScriptWorkflow = {
  id: string
  title: string
  /** Short chip label for the script list */
  chip: string
  /** When to follow this whole flow */
  when: string
  summary: string
  steps: WorkflowStep[]
}

export type ScriptRisk = {
  level: 'caution' | 'danger'
  message: string
}

/** Side-effect warnings shown in the list and run panel. */
export const SCRIPT_RISKS: Record<string, ScriptRisk> = {
  'clear_pub_cache.sh': {
    level: 'danger',
    message:
      'Can wipe or repair the global pub cache and matching git package clones.',
  },
  'release_package.sh': {
    level: 'danger',
    message: 'Commits, tags, and can push to the package remote. Prefer --dry-run first.',
  },
  'install_global.sh': {
    level: 'caution',
    message: 'Writes or updates command symlinks under ~/.local/bin.',
  },
  'install-device-logs-global.sh': {
    level: 'caution',
    message: 'Writes device-log command symlinks under ~/.local/bin.',
  },
  'setup.sh': {
    level: 'caution',
    message: 'One-time bootstrap: may write setup.env and install globals.',
  },
}

export const SCRIPT_WORKFLOWS: ScriptWorkflow[] = [
  {
    id: 'setup',
    title: 'First-time setup',
    chip: 'Setup',
    when: 'You just cloned flutter-scripts or moved to a new machine.',
    summary:
      'Bootstrap once, link commands into ~/.local/bin, then clone shared packages if your app needs them.',
    steps: [
      {
        file: 'setup.sh',
        when: 'After cloning this repo — creates setup.env and installs globals.',
        tip: 'Optional: set a default Flutter project path.',
        recommended: true,
      },
      {
        file: 'install_global.sh',
        when: 'Commands are missing from PATH or you updated the scripts repo.',
        tip: 'Re-run after pulling script changes.',
      },
      {
        file: 'setup_packages.sh',
        when: 'Your app depends on shared git packages listed in packages.list.',
        tip: 'Use --update to pull existing clones.',
      },
      {
        file: 'install-device-logs-global.sh',
        when: 'You only want the device-log wrappers on PATH (not the full catalog).',
      },
    ],
  },
  {
    id: 'debug',
    title: 'Debug on a device',
    chip: 'Debug',
    when: 'Something crashes or misbehaves on Android/iOS and you need live logs.',
    summary:
      'Prefer the device-logs wrapper. Use platform-specific scripts for finer control, or isolate-monitor for Dart isolates / deploy+watch.',
    steps: [
      {
        file: 'device-logs.sh',
        when: 'Default choice — pick android or ios and stream filtered app logs.',
        tip: 'Start here unless you already know you need Android- or iOS-only flags.',
        recommended: true,
      },
      {
        file: 'android-logcat.sh',
        when: 'You need Android logcat only (package filter, wait-for-process, clear).',
      },
      {
        file: 'ios-device-logs.sh',
        when: 'You need iOS simulator/device logs only (bundle id, release bundle).',
      },
      {
        file: 'open-isolate-monitor.sh',
        when: 'Debug Dart isolates, or deploy then open the monitor GUI on a connected device.',
        tip: 'Use --no-deploy if the app is already running with a VM service URI.',
      },
    ],
  },
  {
    id: 'build-app',
    title: 'Build a release app',
    chip: 'Build',
    when: 'You need an APK, AAB, or IPA for testing or store upload.',
    summary:
      'Classify the version bump if releasing, build for the target platform, then optionally inspect an APK’s env.',
    steps: [
      {
        file: 'classify_version_bump.sh',
        when: 'Before a release — decide major / minor / patch from recent changes.',
      },
      {
        file: 'build_mobile_release.sh',
        when: 'One command for apk or ipa with prod/dev env.',
        tip: 'Best default if you do not need Android- or iOS-specific extras.',
        recommended: true,
      },
      {
        file: 'build_android.sh',
        when: 'Android-only release; use --aab for Play Store bundles.',
      },
      {
        file: 'build_ios.sh',
        when: 'iOS-only release IPA with the usual env/secrets checks.',
      },
      {
        file: 'build_both_release_apks.sh',
        when: 'You maintain two Flutter apps and want both release APKs in one run.',
        tip: 'Needs FLUTTER_APP_A_DIR / FLUTTER_APP_B_DIR when building both.',
      },
      {
        file: 'inspect_apk_environment.sh',
        when: 'You have an APK and want to guess prod vs dev from embedded host strings.',
      },
    ],
  },
  {
    id: 'release-package',
    title: 'Release a shared package',
    chip: 'Package',
    when: 'You are tagging and pushing a Flutter git package (not the main app).',
    summary:
      'Use the config-driven releaser for any package that has release.config.sh under this repo.',
    steps: [
      {
        file: 'release_package.sh',
        when: 'Any package that has its own release.config.sh at the flutter-scripts root.',
        tip: 'Start with --list, then --dry-run before a real push. See docs/PACKAGE_RELEASE.md.',
        recommended: true,
      },
    ],
  },
  {
    id: 'deps',
    title: 'Fix dependencies / cache',
    chip: 'Deps',
    when: 'pub get fails, packages look stale, or git dependencies are corrupted.',
    summary: 'Clear or repair the pub cache, then re-clone shared packages if needed.',
    steps: [
      {
        file: 'clear_pub_cache.sh',
        when: 'Broken/corrupt pub cache, or you need to drop matching git package clones.',
        tip: 'Prefer --repair before --full when unsure.',
        recommended: true,
      },
      {
        file: 'setup_packages.sh',
        when: 'After cache cleanup — re-clone or --update packages.list entries.',
      },
    ],
  },
  {
    id: 'localization',
    title: 'Localize UI strings',
    chip: 'l10n',
    when: 'You need to find hardcoded copy and keep ARB locales in sync.',
    summary:
      'Scan hardcoded UI strings, run a full ARB/usage check, then apply suggested keys. Prefer the Localization tab for the guided 3-step flow.',
    steps: [
      {
        file: 'check_localization.sh',
        when: 'CLI scan of hardcoded strings, ARB parity, and missing l10n keys.',
        tip: 'GUI: open 4 · Localization for Step 1 → 2 → 3. Flags: --mode hardcoded|full|suggestions --json',
        recommended: true,
      },
    ],
  },
  {
    id: 'identity',
    title: 'Git / auth helpers',
    chip: 'Git',
    when: 'Commits or gh use the wrong identity, or you need a project OTP/IAM helper.',
    summary:
      'Check commit author vs GitHub login; use project-specific token helpers when the app provides them.',
    steps: [
      {
        file: 'check_git_identity.sh',
        when: 'Commits show the wrong name/email, or gh is logged into a different account.',
        tip: 'For deeper git how-tos, open the Git tool tab.',
        recommended: true,
      },
      {
        file: 'get_iam_token.sh',
        when: 'The active project has tool/get_iam_token.dart and you need an OTP/IAM token.',
      },
    ],
  },
]

export type ScriptGuideMeta = {
  category: string
  when: string
  tip?: string
  workflowIds: string[]
  recommended: boolean
}

/** Flatten step metadata for “selected script” panels and filters. */
export function guideMetaByFile(): Record<string, ScriptGuideMeta> {
  const out: Record<string, ScriptGuideMeta> = {}
  for (const wf of SCRIPT_WORKFLOWS) {
    for (const step of wf.steps) {
      const prev = out[step.file]
      if (!prev) {
        out[step.file] = {
          category: wf.title,
          when: step.when,
          tip: step.tip,
          workflowIds: [wf.id],
          recommended: !!step.recommended,
        }
      } else {
        prev.workflowIds = [...new Set([...prev.workflowIds, wf.id])]
        if (step.recommended) prev.recommended = true
      }
    }
  }
  return out
}

export const SCRIPT_GUIDE = guideMetaByFile()

function scriptBase(file: string): string {
  return file.replace(/\\/g, '/').split('/').pop() || file
}

/** Match workflow step file (often basename) to catalog ScriptItem.file (relative path). */
export function resolveScript<T extends { file: string }>(
  scripts: T[],
  file: string,
): T | undefined {
  const base = scriptBase(file)
  return scripts.find(
    (s) => s.file === file || scriptBase(s.file) === base,
  )
}

export function isRecommended(file: string): boolean {
  return SCRIPT_GUIDE[scriptBase(file)]?.recommended === true
}

export function riskFor(file: string): ScriptRisk | undefined {
  return SCRIPT_RISKS[scriptBase(file)]
}

export function workflowsForFile(file: string): ScriptWorkflow[] {
  const base = scriptBase(file)
  return SCRIPT_WORKFLOWS.filter((wf) =>
    wf.steps.some((s) => s.file === base),
  )
}

const GUIDE_OPEN_KEY = 'flutter-scripts.workflowGuideOpen'

/** Default collapsed to keep the run panel visible; remember last choice. */
export function readGuideOpen(): boolean {
  try {
    const raw = localStorage.getItem(GUIDE_OPEN_KEY)
    if (raw === null) return false
    return raw === '1' || raw === 'true'
  } catch {
    return false
  }
}

export function writeGuideOpen(open: boolean): void {
  try {
    localStorage.setItem(GUIDE_OPEN_KEY, open ? '1' : '0')
  } catch {
    // ignore quota / private mode
  }
}
