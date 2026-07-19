# Repository structure

```text
flutter-scripts/
├── README.md
├── start.sh                  # ★ one-step: setup → open GUI
├── shell-profile.snippet     # source from ~/.zshrc
├── setup.env                 # machine-local (created by setup)
├── flutter-scripts.sh        # root entry → scripts/launcher/
├── open-flutter-scripts-gui.sh
├── open-isolate-monitor.sh
├── setup.sh
├── install_global.sh
├── config/                   # templates & examples of config files
│   ├── packages.list.example
│   └── release.config.template.sh
├── packages/                 # your package release configs live here
│   └── <package_id>/release.config.sh
├── scripts/
│   ├── build/                # Android / iOS / mobile release builds
│   ├── debug/                # device logs, APK inspect, IAM helper
│   ├── deps/                 # pub cache + shared packages
│   ├── git/                  # identity check + package release
│   ├── setup/                # setup + global install helpers
│   └── launcher/             # GUI / CLI launchers
├── lib/                      # shared bash helpers
├── docs/                     # guides
├── examples/                 # copy-paste samples (not auto-installed)
└── tools/
    ├── flutter_scripts_gui/  # Project · Scripts · Git LLM
    ├── isolate_monitor/
    └── git-llm-tool/         # redirect stub
```

## Project resolution (any Flutter app)

1. `--project PATH` / `PROJECT_ROOT`
2. Current directory if it is a Flutter project
3. Walk up parent directories
4. Nearby discovery in the GUI / `--pick`

## Adding a package release

```bash
mkdir -p packages/my_package
cp config/release.config.template.sh packages/my_package/release.config.sh
# edit, then:
release-package --list
```

See [PACKAGE_RELEASE.md](PACKAGE_RELEASE.md).
