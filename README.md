# Flutter Scripts

Shell scripts and GUIs for building, releasing, and debugging **any** Flutter
project. Paths and secrets are resolved dynamically per run — nothing here is
tied to a specific company or product name.

**Requirements:** bash, Flutter (or FVM), macOS/Linux (Windows: Git Bash or WSL).

Layout: [`docs/STRUCTURE.md`](docs/STRUCTURE.md) · Package releases: [`docs/PACKAGE_RELEASE.md`](docs/PACKAGE_RELEASE.md)

---

## Quick start (one step)

On any machine / any user account:

```bash
cd /path/to/flutter-scripts   # wherever you cloned it
./start.sh
```

That installs commands for **this user**, then opens the GUI. Pick or switch the Flutter app in the **Project** tab.

```bash
./start.sh --project ~/path/to/app      # open GUI already on this app
./start.sh --pick                       # terminal chooser, then GUI
./start.sh --list-projects              # only list nearby apps
./start.sh --add-profile                # wire ~/.zshrc
./start.sh --no-open                    # setup only (no browser)
```

---

## Quick start (manual)

### 1. Get the scripts

```bash
git clone https://github.com/vishalsharma7nov/flutter-scripts.git ~/Documents/flutter-scripts
cd ~/Documents/flutter-scripts
```

### 2. Run setup once

```bash
bash setup.sh
# or: ./setup.sh
```

Point at your default app (optional):

```bash
./setup.sh --project ~/StudioProjects/my_app
```

### 3. Add to your shell profile

```bash
source "$HOME/Documents/flutter-scripts/shell-profile.snippet"
```

Custom clone location:

```bash
export FLUTTER_SCRIPTS_HOME="$HOME/path/to/flutter-scripts"
source "${FLUTTER_SCRIPTS_HOME}/shell-profile.snippet"
```

### 4. Verify

```bash
flutter-scripts --list
which flutter-build-android
```

---

## Interactive menu

```bash
flutter-scripts
```

Opens the **web GUI** (React UI + Go backend on port **8766**) with the same
script catalog as the terminal menu. Run a script from the browser; logs stream
in the UI. Working directory is the Flutter project you launched from (or
`PROJECT_ROOT`).

Terminal menu (classic):

```bash
flutter-scripts --cli
```

List without running:

```bash
flutter-scripts --list
```

```bash
flutter-scripts --select flutter-build-android
flutter-scripts --select flutter-build-android -- --aab
flutter-scripts --select flutter-build-android --help
```

Direct GUI launcher:

```bash
flutter-scripts-gui
# or: open-flutter-scripts-gui.sh --project ~/StudioProjects/my_app
```

See `tools/flutter_scripts_gui/README.md` for backend/UI details.

---

## Script catalog

| # | Command | File | What it does |
|---|---------|------|--------------|
| — | `android-logcat` | `android-logcat.sh` | Stream Android logcat for the app package on a connected device (picks project and device when needed) |
| — | `flutter-build-android` | `build_android.sh` | Build a release Android APK or App Bundle with secrets and env checks |
| — | `flutter-build-both-release-apks` | `build_both_release_apks.sh` | Build release APKs for two Flutter apps in one run |
| — | `flutter-build-ios` | `build_ios.sh` | Build a release iOS IPA with secrets and env checks |
| — | `flutter-build-mobile` | `build_mobile_release.sh` | Build `apk` or `ipa` for prod/dev with a single command |
| — | `check-git-identity` | `check_git_identity.sh` | Show git commit author vs GitHub account used by `gh` |
| — | `flutter-classify-version-bump` | `classify_version_bump.sh` | Classify semver bump (major/minor/patch) before a release |
| — | `flutter-clear-pub-cache` | `clear_pub_cache.sh` | Clear or repair Dart/Flutter pub cache entries |
| — | `device-logs` | `device-logs.sh` | Stream device logs for `android` or `ios` (wrapper) |
| — | `flutter-get-iam-token` | `get_iam_token.sh` | Run `tool/get_iam_token.dart` OTP helper in the project |
| — | `flutter-inspect-apk` | `inspect_apk_environment.sh` | Guess prod vs dev build from host strings inside an APK |
| — | `install-device-logs-global` | `install-device-logs-global.sh` | Install device-log commands to `~/.local/bin` |
| — | `install-global` | `install_global.sh` | Install or relink all script commands to `~/.local/bin` |
| — | `ios-device-logs` | `ios-device-logs.sh` | Stream iOS simulator or device logs for the app bundle id |
| — | `isolate-monitor` | `open-isolate-monitor.sh` | Deploy debug/release to a connected device, then open isolate monitor GUI |
| — | `flutter-scripts-gui` | `open-flutter-scripts-gui.sh` | Open the flutter-scripts React + Go web GUI (also: bare `flutter-scripts`) |
| — | `setup (first-time)` | `setup.sh` | One-time bootstrap after clone (`setup.env`, global install) |
| — | `flutter-setup-packages` | `setup_packages.sh` | Clone shared git packages listed in `packages.list` |
| — | `release-package` | `release_package.sh` | Config-driven release for any Flutter git package (see `docs/PACKAGE_RELEASE.md`) |

Numbers in the table match `flutter-scripts --list` on your machine (order may vary).

---

## Finding your Flutter project

| Priority | How |
|----------|-----|
| 1 | `PROJECT_ROOT` environment variable |
| 2 | Current directory if it contains `pubspec.yaml` |
| 3 | Walk up parent directories |
| 4 | Scan nearby apps (menu or flags) |

**Global options** (most scripts):

| Flag | Description |
|------|-------------|
| `--project PATH` | Use this Flutter project root |
| `--pick` | Show project picker menu |
| `--select N` | Pick project *N* from discovery list |
| `--list-projects` | List discoverable apps and exit |

**Examples:**

```bash
cd ~/StudioProjects/my_app
flutter-build-android

flutter-build-android --project ~/StudioProjects/my_app

export PROJECT_ROOT="$HOME/StudioProjects/my_app"
```

---

## Commands reference

### Build & release

| Command | Purpose |
|---------|---------|
| `flutter-build-android` | Release Android APK or App Bundle |
| `flutter-build-ios` | Release iOS IPA |
| `flutter-build-mobile` | Build `apk` or `ipa` with `--env prod\|dev` |
| `flutter-build-both-release-apks` | Build two apps (set `FLUTTER_APP_A_DIR` / `FLUTTER_APP_B_DIR`) |

```bash
flutter-build-android
flutter-build-android --aab
flutter-build-android --skip-checks
flutter-build-ios
```

Apps with `ConfigEnvironment` in `lib/main.dart` auto-pick secrets from `.secrets/`.
Override with `ENV_FILE` or `SECRETS_BASENAME`.

### Pub cache & packages

| Command | Purpose |
|---------|---------|
| `flutter-clear-pub-cache` | Clear or repair pub cache |
| `flutter-setup-packages` | Clone packages from `packages.list` |
| `flutter-classify-version-bump` | Classify semver bump for release |

```bash
flutter-clear-pub-cache --git-pattern 'my_org*' --yes
Copy [`config/packages.list.example`](config/packages.list.example) to `packages.list` in the repo root, then:
flutter-setup-packages
```

### Debugging & tooling

| Command | Purpose |
|---------|---------|
| `flutter-device-logs` | Stream logs (`flutter-device-logs android`) |
| `flutter-android-logcat` | Android logcat by package id |
| `flutter-ios-logs` | iOS simulator/device logs |
| `flutter-isolate-monitor` | Dart isolate monitor web GUI |
| `flutter-inspect-apk` | Heuristic prod/dev check inside an APK |
| `flutter-get-iam-token` | Run `tool/get_iam_token.dart` (if present) |
| `check-git-identity` | Show git author vs `gh auth` account |

```bash
flutter-device-logs android
flutter-android-logcat --clear
flutter-inspect-apk /path/to/app-release.apk
```

### Package release

| Command | Purpose |
|---------|---------|
| `release-package` | Release any configured Flutter git package |

```bash
release-package --list
release-package --package my_package --dry-run
release-package my_package -y --title "Fix map recenter"
```

See [`docs/PACKAGE_RELEASE.md`](docs/PACKAGE_RELEASE.md) for config format and adding packages.
See [`docs/STRUCTURE.md`](docs/STRUCTURE.md) for repository layout.

### Setup

| Command | Purpose |
|---------|---------|
| `setup (first-time)` | Bootstrap after clone |
| `install-global` | Install/relink `~/.local/bin` commands |

---

## Environment variables

| Variable | Description |
|----------|-------------|
| `FLUTTER_SCRIPTS_HOME` | Path to this scripts directory |
| `SCRIPTS_DIR` | Same as above (runtime) |
| `PROJECT_ROOT` | Default Flutter app root |
| `ENV_FILE` | Override secrets file for builds |
| `SECRETS_BASENAME` | Stem for `.secrets/<basename>.prod.env` |
| `SKIP_CONFIRM` / `SKIP_CHECKS` | Skip prompts or env tests |
| `FLUTTER_APP_A_DIR` / `FLUTTER_APP_B_DIR` | Multi-app APK build paths |
| `PACKAGES_ROOT` / `PACKAGES_LIST` | Shared package clone config |
| `INSPECT_APK_PROD_PATTERN` / `INSPECT_APK_DEV_PATTERN` | Host strings for `flutter-inspect-apk` |

`setup.env` is generated by `setup.sh` (machine-local; do not commit).

---

## Windows

Use **Git Bash** or **WSL** with the same commands.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `command not found: flutter-scripts` | Run `./setup.sh`; `source shell-profile.snippet` |
| `permission denied: ./setup.sh` | Run `bash setup.sh` |
| `Could not find a Flutter project root` | `cd` into app, set `PROJECT_ROOT`, or `--project PATH` |
| Wrong secrets file | Check `lib/main.dart` `const env` or set `ENV_FILE` |

---

## Layout

```
flutter-scripts/
├── README.md
├── setup.sh
├── packages.list.example
├── shell-profile.snippet
├── flutter-scripts.sh
├── install_global.sh
├── tools/
│   └── isolate_monitor/  # bundled Dart VM isolate monitor GUI
└── lib/                  # shared helpers (not menu entries)
```

Internal RTK wrappers (`build-android.sh`, etc.) are hidden from the menu.
