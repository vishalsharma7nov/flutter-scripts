export type FieldType = 'text' | 'checkbox' | 'select' | 'positional'

export type DynamicOptionsSource = 'release-packages'

export interface ScriptField {
  id: string
  /** CLI flag, e.g. --device. Empty for positional. */
  flag?: string
  label: string
  help?: string
  type: FieldType
  /** For select */
  options?: { value: string; label: string }[]
  /** Load select options from API (see App.tsx). */
  optionsSource?: DynamicOptionsSource
  /** Prefill */
  defaultValue?: string | boolean
  /** Positional args are ordered and often required */
  required?: boolean
  placeholder?: string
  /** Custom control UI (e.g. platform picker instead of a plain select). */
  control?: 'platform'
  /** Show only when another field equals value (or one of values). */
  visibleWhen?: { field: string; value: string | string[] | boolean }
  /** When checked, only this flag is sent (+ extra args). */
  exclusive?: boolean
}

export interface ScriptFormDef {
  /** basename of script file */
  file: string
  fields: ScriptField[]
  /** Extra free-text always available */
  allowExtra?: boolean
}

/** Known interactive options per top-level flutter-scripts script. */
export const SCRIPT_FORMS: Record<string, ScriptFormDef> = {

  'check_localization.sh': {
    file: 'check_localization.sh',
    allowExtra: true,
    fields: [
      {
        id: 'mode',
        flag: '--mode',
        type: 'select',
        label: 'Mode',
        required: true,
        defaultValue: 'full',
        options: [
          { value: 'hardcoded', label: 'hardcoded (step 1)' },
          { value: 'full', label: 'full project (step 2)' },
          { value: 'suggestions', label: 'suggestions (step 3)' },
        ],
        help: 'Prefer the Localization tab for the guided UI',
      },
      {
        id: 'path',
        flag: '--path',
        type: 'text',
        label: 'Path under lib/',
        placeholder: 'features/home-view-feature',
      },
      {
        id: 'json',
        flag: '--json',
        type: 'checkbox',
        label: 'JSON output',
        defaultValue: false,
      },
      {
        id: 'warnOnly',
        flag: '--warn-only',
        type: 'checkbox',
        label: 'Warn only (exit 0)',
        defaultValue: true,
      },
    ],
  },
  'device-logs.sh': {
    file: 'device-logs.sh',
    allowExtra: true,
    fields: [
      {
        id: 'platform',
        type: 'positional',
        label: 'Platform',
        control: 'platform',
        required: true,
        options: [
          { value: 'android', label: 'Android' },
          { value: 'ios', label: 'iOS' },
        ],
        defaultValue: 'android',
        help: 'Stream logs from a connected device or simulator',
      },
      {
        id: 'device',
        flag: '-d',
        type: 'text',
        label: 'Device',
        placeholder: 'emulator-5554 or iPhone name',
      },
      {
        id: 'package',
        flag: '-p',
        type: 'text',
        label: 'Package override (Android)',
        placeholder: 'com.example.app',
        visibleWhen: { field: 'platform', value: 'android' },
        help: 'Default: applicationId from the active Flutter project',
      },
      {
        id: 'wait',
        flag: '--wait',
        type: 'checkbox',
        label: 'Wait for app to start (Android)',
        defaultValue: true,
        visibleWhen: { field: 'platform', value: 'android' },
        help: 'Poll up to 30s — launch the app on device after Run',
      },
      {
        id: 'release',
        flag: '--release',
        type: 'checkbox',
        label: 'Release bundle (iOS)',
        defaultValue: false,
        visibleWhen: { field: 'platform', value: 'ios' },
      },
      {
        id: 'clear',
        flag: '--clear',
        type: 'checkbox',
        label: 'Clear logs first',
        defaultValue: false,
      },
    ],
  },
  'android-logcat.sh': {
    file: 'android-logcat.sh',
    allowExtra: true,
    fields: [
      {
        id: 'device',
        flag: '-d',
        type: 'text',
        label: 'adb serial',
        placeholder: 'emulator-5554',
      },
      {
        id: 'package',
        flag: '-p',
        type: 'text',
        label: 'Package override',
        placeholder: 'com.example.app',
      },
      {
        id: 'clear',
        flag: '--clear',
        type: 'checkbox',
        label: 'Clear logcat buffer',
        defaultValue: false,
      },
      {
        id: 'wait',
        flag: '--wait',
        type: 'checkbox',
        label: 'Wait for app process',
        defaultValue: false,
      },
    ],
  },
  'ios-device-logs.sh': {
    file: 'ios-device-logs.sh',
    allowExtra: true,
    fields: [
      {
        id: 'device',
        flag: '-d',
        type: 'text',
        label: 'Device / simulator',
        placeholder: 'iPhone 16 Pro or UDID',
        help: 'Leave empty for booted simulator / first connected device',
      },
      {
        id: 'bundle',
        flag: '-b',
        type: 'text',
        label: 'Bundle ID override',
      },
      {
        id: 'release',
        flag: '--release',
        type: 'checkbox',
        label: 'Release bundle id',
        defaultValue: false,
      },
      {
        id: 'clear',
        flag: '--clear',
        type: 'checkbox',
        label: 'Clear (simulator only)',
        defaultValue: false,
      },
    ],
  },
  'build_android.sh': {
    file: 'build_android.sh',
    fields: [
      {
        id: 'aab',
        flag: '--aab',
        type: 'checkbox',
        label: 'Build App Bundle (.aab)',
        defaultValue: false,
      },
      {
        id: 'rtk',
        flag: '--rtk',
        type: 'checkbox',
        label: 'Use release toolkit (RTK)',
        defaultValue: false,
      },
      {
        id: 'skipChecks',
        flag: '--skip-checks',
        type: 'checkbox',
        label: 'Skip checks',
        defaultValue: false,
      },
    ],
  },
  'build_ios.sh': {
    file: 'build_ios.sh',
    fields: [
      {
        id: 'rtk',
        flag: '--rtk',
        type: 'checkbox',
        label: 'Use release toolkit (RTK)',
        defaultValue: false,
      },
      {
        id: 'skipChecks',
        flag: '--skip-checks',
        type: 'checkbox',
        label: 'Skip checks',
        defaultValue: false,
      },
    ],
  },
  'build_mobile_release.sh': {
    file: 'build_mobile_release.sh',
    allowExtra: true,
    fields: [
      {
        id: 'env',
        flag: '--env',
        type: 'select',
        label: 'Environment',
        options: [
          { value: 'prod', label: 'prod' },
          { value: 'dev', label: 'dev' },
        ],
        defaultValue: 'prod',
      },
      {
        id: 'skipChecks',
        flag: '--skip-checks',
        type: 'checkbox',
        label: 'Skip checks',
        defaultValue: false,
      },
      {
        id: 'target',
        type: 'positional',
        label: 'Target',
        required: true,
        options: [
          { value: 'apk', label: 'apk' },
          { value: 'ipa', label: 'ipa' },
        ],
        defaultValue: 'apk',
      },
    ],
  },
  'open-isolate-monitor.sh': {
    file: 'open-isolate-monitor.sh',
    allowExtra: true,
    fields: [
      {
        id: 'mode',
        type: 'select',
        label: 'Build mode',
        options: [
          { value: '', label: 'default (debug)' },
          { value: '--debug', label: 'debug' },
          { value: '--profile', label: 'profile' },
          { value: '--release', label: 'profile (legacy --release)' },
          { value: '--release-build', label: 'release-build (logs only)' },
        ],
        defaultValue: '',
      },
      {
        id: 'device',
        flag: '-d',
        type: 'text',
        label: 'Flutter device id',
        placeholder: 'flutter devices',
      },
      {
        id: 'backend',
        flag: '--backend',
        type: 'select',
        label: 'Monitor backend',
        options: [
          { value: '', label: 'ask / default' },
          { value: 'go', label: 'go' },
          { value: 'dart', label: 'dart' },
          { value: 'typescript', label: 'typescript' },
        ],
        defaultValue: 'go',
      },
      {
        id: 'port',
        flag: '--port',
        type: 'text',
        label: 'Port',
        placeholder: '8765',
      },
      {
        id: 'noDeploy',
        flag: '--no-deploy',
        type: 'checkbox',
        label: 'No deploy (monitor only)',
        defaultValue: false,
      },
      {
        id: 'noOpen',
        flag: '--no-auto-open',
        type: 'checkbox',
        label: 'Do not open browser',
        defaultValue: false,
      },
      {
        id: 'uri',
        flag: '--uri',
        type: 'text',
        label: 'Existing VM service URI',
        placeholder: 'ws://127.0.0.1:…',
      },
    ],
  },
  'clear_pub_cache.sh': {
    file: 'clear_pub_cache.sh',
    allowExtra: true,
    fields: [
      {
        id: 'mode',
        type: 'select',
        label: 'Mode',
        required: true,
        options: [
          { value: 'full', label: 'Full cache clean (--full)' },
          { value: 'repair', label: 'Repair cache (--repair)' },
          {
            value: 'git-pattern',
            label: 'Remove Git packages by pattern (--git-pattern)',
          },
        ],
        defaultValue: 'repair',
        help: 'Prefer --repair first; use --full only when repair is not enough',
      },
      {
        id: 'gitPattern',
        flag: '--git-pattern',
        type: 'text',
        label: 'Git pattern',
        required: true,
        placeholder: 'my_org*',
        visibleWhen: { field: 'mode', value: 'git-pattern' },
      },
      {
        id: 'cleanArtifacts',
        flag: '--clean-artifacts',
        type: 'checkbox',
        label: 'Remove project .dart_tool / build artifacts',
        defaultValue: false,
      },
      {
        id: 'iosPods',
        flag: '--ios-pods',
        type: 'checkbox',
        label: 'Run pod install after pub get',
        defaultValue: false,
      },
      {
        id: 'noGet',
        flag: '--no-get',
        type: 'checkbox',
        label: 'Skip flutter pub get at end',
        defaultValue: false,
      },
      {
        id: 'yes',
        flag: '--yes',
        type: 'checkbox',
        label: 'Skip confirmation (--yes)',
        defaultValue: true,
      },
    ],
  },
  'inspect_apk_environment.sh': {
    file: 'inspect_apk_environment.sh',
    allowExtra: false,
    fields: [
      {
        id: 'apk',
        type: 'positional',
        label: 'APK path',
        required: true,
        placeholder: '/path/to/app-release.apk',
        help: 'Required — path to the APK file to inspect',
      },
    ],
  },
  'classify_version_bump.sh': {
    file: 'classify_version_bump.sh',
    allowExtra: true,
    fields: [
      {
        id: 'applyEnv',
        flag: '--apply-env',
        type: 'checkbox',
        label: 'Apply bump to secrets env files',
        defaultValue: false,
      },
      {
        id: 'env',
        flag: '--env',
        type: 'select',
        label: 'Target env',
        options: [
          { value: 'prod', label: 'prod' },
          { value: 'dev', label: 'dev' },
        ],
        defaultValue: 'prod',
        visibleWhen: { field: 'applyEnv', value: true },
        help: 'Used with --apply-env',
      },
      {
        id: 'verbose',
        flag: '--verbose',
        type: 'checkbox',
        label: 'Verbose output',
        defaultValue: false,
      },
      {
        id: 'yes',
        flag: '--yes',
        type: 'checkbox',
        label: 'Skip confirmation (--yes)',
        defaultValue: false,
      },
    ],
  },
  'check_git_identity.sh': {
    file: 'check_git_identity.sh',
    fields: [],
  },
  'install_global.sh': {
    file: 'install_global.sh',
    fields: [
      {
        id: 'inPlace',
        flag: '--in-place',
        type: 'checkbox',
        label: 'In-place (no copy)',
        defaultValue: true,
      },
    ],
  },
  'install-device-logs-global.sh': {
    file: 'install-device-logs-global.sh',
    fields: [],
  },
  'setup.sh': {
    file: 'setup.sh',
    allowExtra: false,
    fields: [
      {
        id: 'noGlobal',
        flag: '--no-global',
        type: 'checkbox',
        label: 'Skip ~/.local/bin install (--no-global)',
        defaultValue: false,
      },
      {
        id: 'project',
        flag: '--project',
        type: 'text',
        label: 'Default Flutter project path',
        placeholder: '~/StudioProjects/my_app',
        help: 'Optional — written to setup.env snippet',
      },
    ],
  },
  'setup_packages.sh': {
    file: 'setup_packages.sh',
    allowExtra: false,
    fields: [
      {
        id: 'update',
        flag: '--update',
        type: 'checkbox',
        label: 'git pull existing clones (--update)',
        defaultValue: false,
      },
    ],
  },
  'get_iam_token.sh': {
    file: 'get_iam_token.sh',
    fields: [],
  },
  'release_package.sh': {
    file: 'release_package.sh',
    allowExtra: true,
    fields: [
      {
        id: 'listOnly',
        flag: '--list',
        type: 'checkbox',
        label: 'List configured packages only',
        defaultValue: false,
        exclusive: true,
      },
      {
        id: 'package',
        flag: '--package',
        type: 'select',
        label: 'Package',
        required: true,
        optionsSource: 'release-packages',
        options: [],
        visibleWhen: { field: 'listOnly', value: false },
        help: 'Required unless listing packages',
      },
      {
        id: 'bump',
        type: 'positional',
        label: 'Version bump',
        required: true,
        visibleWhen: { field: 'listOnly', value: false },
        options: [
          { value: 'patch', label: 'patch (default)' },
          { value: 'minor', label: 'minor' },
          { value: 'major', label: 'major' },
        ],
        defaultValue: 'patch',
      },
      {
        id: 'title',
        flag: '--title',
        type: 'text',
        label: 'Release title',
        placeholder: 'Fix heading recenter',
        visibleWhen: { field: 'listOnly', value: false },
      },
      {
        id: 'dryRun',
        flag: '--dry-run',
        type: 'checkbox',
        label: 'Dry run (plan only)',
        defaultValue: true,
        visibleWhen: { field: 'listOnly', value: false },
        help: 'Safe default — uncheck to perform a real release',
      },
      {
        id: 'noPush',
        flag: '--no-push',
        type: 'checkbox',
        label: 'Commit/tag locally without push',
        defaultValue: false,
        visibleWhen: { field: 'listOnly', value: false },
      },
      {
        id: 'skipChecks',
        flag: '--skip-checks',
        type: 'checkbox',
        label: 'Skip analyze / tests',
        defaultValue: false,
        visibleWhen: { field: 'listOnly', value: false },
      },
      {
        id: 'noAutoCommit',
        flag: '--no-auto-commit',
        type: 'checkbox',
        label: 'Fail if dirty (no auto-commit)',
        defaultValue: false,
        visibleWhen: { field: 'listOnly', value: false },
      },
      {
        id: 'yes',
        flag: '--yes',
        type: 'checkbox',
        label: 'Skip confirmation (-y)',
        defaultValue: false,
        visibleWhen: { field: 'listOnly', value: false },
      },
    ],
  },
  'build_both_release_apks.sh': {
    file: 'build_both_release_apks.sh',
    allowExtra: true,
    fields: [
      {
        id: 'scope',
        type: 'select',
        label: 'Apps to build',
        required: true,
        options: [
          { value: '', label: 'Both (needs FLUTTER_APP_B_DIR)' },
          { value: '--app-a-only', label: 'App A only' },
          { value: '--app-b-only', label: 'App B only' },
        ],
        defaultValue: '',
        help: 'Set FLUTTER_APP_A_DIR / FLUTTER_APP_B_DIR in the environment if needed',
      },
      {
        id: 'skipChecks',
        flag: '--skip-checks',
        type: 'checkbox',
        label: 'Skip environment checks',
        defaultValue: false,
      },
    ],
  },
}

export type FormValues = Record<string, string | boolean>

export function isFieldVisible(
  field: ScriptField,
  values: FormValues,
): boolean {
  if (!field.visibleWhen) return true
  const raw = values[field.visibleWhen.field]
  const actual =
    typeof raw === 'boolean' ? raw : String(raw ?? '').trim()
  const expected = field.visibleWhen.value
  if (Array.isArray(expected)) {
    return expected.some((v) =>
      typeof v === 'boolean' ? v === actual : v === String(actual),
    )
  }
  if (typeof expected === 'boolean') {
    return actual === expected
  }
  return String(actual) === expected
}

export function defaultValuesFor(def: ScriptFormDef): FormValues {
  const values: FormValues = {}
  for (const field of def.fields) {
    if (field.type === 'checkbox') {
      values[field.id] = field.defaultValue === true
    } else if (field.type === 'select' && field.options?.length) {
      values[field.id] =
        (field.defaultValue as string | undefined) ?? field.options[0]?.value ?? ''
    } else if (field.type === 'positional' && field.options?.length) {
      values[field.id] =
        (field.defaultValue as string | undefined) ?? field.options[0]?.value ?? ''
    } else {
      values[field.id] = (field.defaultValue as string | undefined) ?? ''
    }
  }
  return values
}

/** Build CLI argv from form values (field order preserved). */
export function buildArgsFromForm(
  def: ScriptFormDef,
  values: FormValues,
  extra = '',
): string[] {
  for (const field of def.fields) {
    if (
      field.type === 'checkbox' &&
      field.exclusive &&
      values[field.id] === true &&
      field.flag
    ) {
      return [field.flag, ...parseExtraArgs(extra)]
    }
  }

  const out: string[] = []

  for (const field of def.fields) {
    if (!isFieldVisible(field, values)) continue

    const raw = values[field.id]
    if (field.type === 'checkbox') {
      if (raw === true && field.flag) {
        out.push(field.flag)
      }
      continue
    }

    const text = String(raw ?? '').trim()
    if (!text) continue

    // clear_pub_cache: mode values map to standalone flags (--full / --repair)
    if (
      field.id === 'mode' &&
      def.file === 'clear_pub_cache.sh' &&
      (text === 'full' || text === 'repair')
    ) {
      out.push(text === 'full' ? '--full' : '--repair')
      continue
    }

    if (field.type === 'positional') {
      out.push(text)
      continue
    }

    // select that stores full flag as value (e.g. --debug, --app-a-only)
    if (field.type === 'select' && text.startsWith('-') && !field.flag) {
      out.push(text)
      continue
    }

    if (field.flag) {
      out.push(field.flag, text)
    }
  }

  return [...out, ...parseExtraArgs(extra)]
}

function parseExtraArgs(raw: string): string[] {
  const trimmed = raw.trim()
  if (!trimmed) return []
  const out: string[] = []
  const re = /"([^"]*)"|'([^']*)'|(\S+)/g
  let m: RegExpExecArray | null
  while ((m = re.exec(trimmed)) !== null) {
    out.push(m[1] ?? m[2] ?? m[3] ?? '')
  }
  return out
}

/** Script ids in forms/meta are basenames; catalog may return scripts/…/name.sh */
export function scriptBasename(file: string): string {
  const parts = file.replace(/\\/g, '/').split('/')
  return parts[parts.length - 1] || file
}

export function getFormForScript(file: string): ScriptFormDef | null {
  return SCRIPT_FORMS[scriptBasename(file)] ?? null
}
