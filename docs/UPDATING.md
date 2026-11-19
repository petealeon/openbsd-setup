# Applying updates to an existing install

`update.sh` reapplies repository-managed configuration and helper scripts to an existing OpenBSD install **without a full reinstall**. It is intended to be idempotent and safe to re-run.

> Run as root (`doas ...`) from the repo directory on the target OpenBSD system. `update.sh` does **not** run `syspatch`, `fw_update`, or `pkg_add`, and it does **not** touch disk or bootloader configuration.

## Usage

```sh
cd /path/to/openbsd-setup

# apply changes for the invoking/configured desktop user
doas sh ./update.sh --user <your-user>

# optional
# doas sh ./update.sh --user <your-user> --skip-terminal   # skip rebuilding st
# sh ./update.sh --user <your-user> --dry-run              # preview actions
```

If `--user` is omitted, scripts try to infer the desktop user from the invoking environment (`doas`/`sudo` context) and will error in ambiguous cases rather than guessing.

## What `update.sh` does

Stages run in this order so important fixes are applied even if rebuilding `st` fails:

1. **desktop** — refreshes dotfiles, `~/bin` helpers, themes/bar assets, and user directories. Replaced user files may be backed up under `~/.config-backup-<timestamp>/`.
2. **system** — reapplies `/etc` overlays (including `doas`, sshd drop-in user policy, Chromium managed policy defaults, hotplug, unwind, apm hooks, xenodm setup files, and `/etc/sysctl.conf` as shipped by the repo), fixes permissions, and enables/reloads relevant services. It does **not** restart xenodm.
3. **terminal** (unless `--skip-terminal`) — rebuilds/installs `st` from `share/st` and related assets. This may require network access/build dependencies if sources are not cached; a failure is reported but does not roll back desktop/system changes.

## What it does not do

- No `syspatch`, `fw_update`, or package installation/upgrades.
- No disk partitioning, filesystem, bootloader, or image operations.
- No automatic reboot or session restart.

If packages/firmware/patches are missing, run the relevant installer stages instead, for example:

```sh
doas ./install.sh --metal --user <your-user> --only=packages,desktop,system,browser,terminal
```

## After applying

- **Log out and back in to xenodm** (or reboot) so session startup, WM config, helpers, notifications/compositor, and environment changes take effect.
- **Restart terminals/apps** as needed (especially after rebuilding `st`, changing audio device selection, or updating helpers).
- **Review sysctl changes:** `/etc/sysctl.conf` is read at boot; to apply a value immediately use `sysctl` once (only if appropriate for your hardware).

## Self-update via git

If you track this repo with git, `~/bin/openbsd-setup-update` can fetch upstream changes and run `update.sh` for commits not yet applied (recording the last successful apply under `${XDG_STATE_HOME:-$HOME/.local/state}/openbsd-setup/`). See the root `README.md` for usage and safety behavior.

## Troubleshooting and diagnostics

- Check script output and rerun with `--dry-run` to preview actions.
- On OpenBSD, `./validate.sh` can help catch common config/syntax issues.
- For suspend/resume issues, use `scripts/collect-suspend-diagnostics.sh` (see `docs/SUSPEND-DIAGNOSTICS.md`). Treat suspend/hibernate policy and hardware workarounds as machine-specific; verify before relying on them.
- Hardware-dependent features (audio devices, brightness/backlight keys, wireless, touch input) may require adjustment for your system; collect relevant command output (`ifconfig`, `dmesg`/boot messages, `wsconsctl`, `sndioctl`/`mixerctl`, etc.) when debugging.
