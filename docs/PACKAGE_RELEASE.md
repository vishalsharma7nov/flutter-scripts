# Package release (`release-package`)

Config-driven release for **any** Flutter git package.

## Commands

```bash
release-package --list
release-package --package my_package --dry-run
release-package my_package -y --title "Fix map recenter"
```

## Add a package

```bash
mkdir -p packages/my_package
cp config/release.config.template.sh packages/my_package/release.config.sh
# or: cp examples/flutter_git_package/release.config.sh packages/my_package/release.config.sh
```

Edit IDs, repo path, and GitHub URL. Confirm:

```bash
release-package --list
```

Configs are discovered from:

```text
packages/<package_id>/release.config.sh
```

(legacy: `<repo-root>/<package_id>/release.config.sh` excluding tooling folders)

## Config fields

See comments in [`config/release.config.template.sh`](../config/release.config.template.sh).
