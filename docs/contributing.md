# Contributing

This is a personal configuration, but fixes and small features are welcome. Keep the owner's setup working first.

## Before you change something

1. Read `README.md`, `AGENTS.md` and this page.
2. For visual changes read `DESIGN.md`.
3. Check `qs log -c island` before and after. A clean reload ends with `Configuration Loaded`.
4. Do not hand-edit generated files. Change `themes/*.json`, `apply-theme.sh`, `apply-settings.sh` or the Settings spec instead.
5. Keep the shell lazy: new popouts and overlays should only exist while open.

## Testing

```sh
bash -n scripts/*.sh scripts/island-* install.sh sddm/install.sh
shellcheck scripts/island-power scripts/island-startup scripts/island-session install.sh sddm/install.sh
./install.sh --dry-run
scripts/island-power --dry-run suspend
scripts/island-startup --dry-run
qs log -c island
```

For a settings or compositor change, exercise it with IPC:

```sh
qs -c island ipc call settings page appearance
qs -c island ipc call menu controls
qs -c island ipc call lock preview
```

Do not test a lock, logout, suspend or shutdown on a machine someone is using.

## Style

- QML follows the existing `qs.services` / `qs.components` imports. New folders are modules automatically.
- JavaScript uses the patterns in `services/` and `components/`.
- Scripts are POSIX `sh` unless they need bash. New session scripts are bash and shellcheck clean.
- No secrets, tokens, `.env` files or personal paths in commits.
- Commit messages are short and scoped, for example `docs: add installation guide` or `startup: add non-systemd session helpers`.

## Pull requests

- Explain what was tested and on which compositor and init system.
- Say what was not tested.
- Keep unrelated changes out of the same commit.
- Do not add dependencies without explaining why and documenting their package names.

## License

Contributions are accepted under the repository's AGPL-3.0 license.
