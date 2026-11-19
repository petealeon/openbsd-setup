# AGENTS.md

Target platform: **OpenBSD 8.0 amd64**. Never assume Linux: no systemd, no GNU userland, no `/proc`, no `ip`, no `sudo` (use `doas`).

## Hard rule

Do not run destructive disk, partition, filesystem, bootloader, mount, or imaging commands against any non-target disk or partition. Treat existing OS installations and user data on other disks/partitions as off-limits unless a human explicitly confirms the exact target and intent.

## Commands

- Install / re-install: `doas ./install.sh --metal` (or `--vm`); stages in `lib/stages/`. `./install.sh --dry-run --user <name>` is a safe preview.
- Apply updates to an existing install: `doas sh ./update.sh --user <name>` (idempotent; re-applies managed config/scripts without pkg/patch/disk changes).
- Self-update helper (on target systems): `~/bin/openbsd-setup-update` (fetch + apply unapplied changes from git).
- Lint the repo anywhere: `make check` (shell syntax + config sanity).
- Rebuild the terminal: `doas ./install.sh --only=terminal --user <name>`. Gaming stack: `doas ./install.sh --only=gaming --user <name>` (space-checked).

Optional VM rehearsal workflow (`vm` script, libvirt/qemu host tooling): `./vm new|bootstrap|apply|capture|run|ssh|console|snap ...` — adjust env/paths for your host and treat as disposable test infrastructure.

## Conventions

- `etc/` is portable, `etc-vm/` is VM-only, `etc-hardware/` contains hardware-oriented examples. Put a file in the narrowest directory that still works.
- Portable packages go in `packages.txt`; emulator/RetroArch packages in `packages-gaming.txt`; VM-only packages in `packages-vm.txt`. Stems only, never pinned versions.
- `install.sh` / `update.sh` require or infer a desktop user; avoid hardcoding personal usernames/paths in repo-managed behavior.
- The amber theme is the default and lives in `home/.config/spectrwm/themes/amber/`; `st`'s palette is compile-time in `share/st/config.h`.
- DNS adblocking backstop is `unwind` (+ `resolvd`) with a local blocklist (`/var/db/unwind.block`, seed in `share/unwind/`). Controller access on OpenBSD is via `/etc/hotplug/attach` → `/dev/uhid*`.
- Do not add secrets or per-install state: `/etc/fstab`, host keys, `master.passwd`, Wi-Fi passphrases, tokens, passwords, local diagnostic dumps, or anything under `secrets/` contents.
- Prefer editing files in the repo over editing target system files directly; keep changes idempotent and safe to re-run where possible.
