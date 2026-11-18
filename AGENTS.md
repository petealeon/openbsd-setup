# AGENTS.md

Target platform: **OpenBSD 8.0 amd64** (the `openbsd` libvirt VM now, a T480s
later). Never assume Linux: no systemd, no GNU userland, no `/proc`, no
`ip`, no `sudo` (use `doas`).

## Hard rule

The host's `/dev/nvme0n1` (Windows + the existing OpenBSD install on
`nvme0n1p5`) is off limits. Never partition, mount, image, or run bootloader
commands against it. The VM disk is `~/VMs/openbsd/openbsd.qcow2`.

## Commands

- Install / re-install: `doas ./install.sh --vm` (or `--metal`); stages in
  `lib/stages/`. `./install.sh --dry-run` is a safe preview.
- Lint the repo anywhere: `make check` (shell syntax + config sanity).
- Rebuild the terminal: `doas ./install.sh --only=terminal`. Gaming stack:
  `doas ./install.sh --only=gaming` (space-checked).
- Run builds/tests in the VM: `./vm run '<command>'`
- Interactive shell: `./vm ssh`
- Push config: `./vm apply` (validates `sshd`, `pf`, `doas` first)
- Absorb hand edits from the guest: `./vm capture`
- Snapshot before upgrades: `./vm snap <tag>`
- Serial console if SSH breaks: `./vm console` (leave with Ctrl-])

## Conventions

- `etc/` is portable, `etc-vm/` is VM-only, `etc-hardware/` is T480s-only.
  Put a file in the narrowest directory that still works.
- Portable packages go in `packages.txt`; emulator/RetroArch packages in
  `packages-gaming.txt`; VM-only packages in `packages-vm.txt`. Stems only,
  never pinned versions.
- The amber theme is the default and lives in
  `home/.config/spectrwm/themes/amber/`; st's palette is compile-time in
  `share/st/config.h`.
- DNS adblocking backstop is `unwind` (+ `resolvd`) with a local blocklist
  (`/var/db/unwind.block`, seed in `share/unwind/`). Wired controller access on
  OpenBSD is via `/etc/hotplug/attach` → `/dev/uhid*`.
- Do not add `/etc/fstab`, host keys, `master.passwd`, or other per-install
  state to the repo.
- Prefer editing files in the repo over editing `/etc` in the guest. If you do
  edit the guest, run `./vm capture` and show the diff.
