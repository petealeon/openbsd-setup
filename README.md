# openbsd-setup

> **Unfinished work in progress. Not recommended for use unless** you understand OpenBSD, have read the scripts, have backups and console access, and are prepared to debug and adapt everything to your own hardware and preferences.
>
> This repository is tailored to specific hardware and evolves rapidly. It modifies `/etc`, user configuration, services, and packages, builds software from source, and can leave a system in a broken or inconvenient state. It is provided **as-is**, with no warranty or support implied. Use it at your own risk.

`openbsd-setup` is an idempotent, staged setup for **OpenBSD 8.0 (amd64)** aimed at a lightweight X11 desktop (spectrwm, `st`, rofi, dunst, picom, etc.) with an "amber" theme. It was developed and tested primarily on a ThinkPad-class laptop, but many parts are hardware-specific and assumptions may not match your machine.

The repo is the source of truth: install/update behavior lives in scripts and overlays, not in a one-off manual system state.

## What this provides

- **Staged installer:** `install.sh` (`--metal` / `--vm`, `--dry-run`, `--only=...`, `--user <name>`) with idempotent stages in `lib/stages/`.
- **Updater:** `update.sh` to reapply configuration/script fixes to an existing install without a full reinstall (does not run `syspatch`, `fw_update`, or `pkg_add`, and does not touch disks/bootloader).
- **Self-update helper:** `~/bin/openbsd-setup-update` (installed with the desktop stage) to fetch upstream git changes and apply updates that have not been applied yet.
- **Config overlays:** portable `etc/`, VM-specific `etc-vm/`, hardware-specific examples in `etc-hardware/`.
- **User environment:** dotfiles, helper scripts, theme assets, and desktop/session wiring under `home/`.
- **Terminal:** `st` built from pinned source/config in `share/st/`.
- **Optional extras:** browser policy defaults, gaming/emulator stage (space-checked), DNS blocklist seed for `unwind`, hotplug/controller helpers, suspend/resume hooks and diagnostics.

## Status and limitations

- **WIP / experimental:** expect rough edges, changing behavior, and hardware-dependent issues.
- **Hardware-specific behavior exists:** power/suspend, backlight/keyboard backlight keys, audio devices, wireless NICs, trackpad/touch behavior, and firmware needs vary by machine. Some workarounds (e.g. suspend/hibernate policy and diagnostics) reflect tested hardware and may not be appropriate elsewhere.
- **Not a general OpenBSD installer replacement:** it does not partition disks, create filesystems, or install the bootloader. You must perform a normal OpenBSD installation first.
- **Desktop choices are opinionated:** X11/spectrwm/xenodm, specific keybindings/helpers, and theme defaults.
- **Validate on your system:** review diffs and test changes; keep a recovery path (console login, backups/snapshots where applicable).

## Repository layout

| Path | Purpose |
|---|---|
| `install.sh` | Main staged installer (`--metal`, `--vm`, `--dry-run`, `--only`, `--user`) |
| `update.sh` | Reapply repo-managed config/scripts to an existing install (no pkg/patch/disk changes) |
| `lib/` | Shared helpers and install stages (`lib/stages/*.sh`) |
| `etc/` | Portable `/etc` overlay (sshd/doas/pf/policy, xenodm, unwind, hotplug, apm, etc.) |
| `etc-vm/` | VM-only overlay (serial console, example networking, VM sshd policy) |
| `etc-hardware/` | Hardware-oriented example overlay (e.g. wireless/wscons examples) |
| `home/` | Dotfiles, `bin/` helpers, themes, wallpapers, app configs |
| `share/` | Vendored assets and build inputs (`st` source config/patches, fonts, blocklist seed) |
| `packages.txt` | Base package list (stems; not version-pinned) |
| `packages-gaming.txt` | Optional gaming/emulator packages (installed by `gaming` stage when space allows) |
| `packages-vm.txt` | VM-only package additions (if any) |
| `scripts/` | Maintenance/diagnostic helpers (e.g. suspend diagnostics, update helper copy) |
| `docs/` | Additional notes (updating, diagnostics, manual/install planning docs) |
| `vm` | Host-side helper for a libvirt/QEMU rehearsal VM workflow (optional/dev convenience) |

## Prerequisites

- A working **OpenBSD 8.0 amd64** installation (fresh install recommended for experimentation), with network access and console access.
- A non-root user account (typically in `wheel`) to use as the desktop user.
- Root privileges via `doas`/root shell to apply system changes.
- `git` if you want to clone/update from this repository on the target machine.

Read and adapt `etc-hardware/`, `etc-vm/`, and network-related files before applying on real hardware. Do **not** commit secrets (Wi-Fi passphrases, keys, passwords, tokens).

## Install

1. **Install OpenBSD normally** (disk layout, bootloader, users, networking as appropriate for your machine). Keep a way to recover (console, another machine, backups).
2. **Get the repo onto the machine** (example):
   ```sh
   # as root or with doas/pkg_add
   pkg_add git
   # as your user
   git clone https://github.com/petealeon/openbsd-setup.git ~/openbsd-setup
   cd ~/openbsd-setup
   ```
3. **Review before running.** Inspect `install.sh`, `lib/stages/*`, `etc*`, and `home/` (especially sshd/doas/pf/network/suspend settings) and adjust for your environment.
4. **Preview and run** (as root, from the repo directory):
   ```sh
   ./install.sh --list
   sh ./install.sh --metal --dry-run --user <your-user>
   doas ./install.sh --metal --user <your-user>
   ```
   - Use `--vm` instead of `--metal` for the rehearsal-VM overlay/profile.
   - If `--user` is omitted, scripts try to infer the invoking user (via `doas`/`sudo` context) and will error rather than guess dangerously when run in ambiguous contexts.
   - Use `--only=<stage,...>` to run selected stages (e.g. `desktop`, `terminal`, `system`).
5. **Reboot and log in** via xenodm (or your chosen flow) and verify behavior. Re-run `./validate.sh` on OpenBSD for config/service checks where applicable.

`install.sh` is intended to be re-runnable; replaced user files are backed up under `~/.config-backup-<timestamp>/` by desktop-stage logic.

## Updating an existing install

From the repo directory on the target machine:

```sh
doas sh ./update.sh --user <your-user>
# optional: --skip-terminal (skip rebuilding st), --dry-run
```

`update.sh` reapplies **desktop**, **system**, and (optionally) **terminal** stages in a safe order. It does **not** run `syspatch`, `fw_update`, or `pkg_add`, and does **not** modify disk/bootloader configuration. Re-run relevant `install.sh` stages if packages/patches/firmware are required.

After updates, log out/in to xenodm (or reboot) and restart affected apps/terminals so session, WM, services hooks, and rebuilt binaries take effect. See `docs/UPDATING.md` for details.

## Self-update from git (recommended once published)

`home/bin/openbsd-setup-update` (installed to `~/bin` by the desktop stage) can fetch upstream changes and apply only what has not been applied yet:

```sh
# first-time clone + apply (example)
~/bin/openbsd-setup-update --bootstrap --repo ~/openbsd-setup --user <your-user>

# later: check or apply updates
~/bin/openbsd-setup-update --check --repo ~/openbsd-setup --user <your-user>
~/bin/openbsd-setup-update --repo ~/openbsd-setup --user <your-user>
# optional: --skip-terminal
```

Behavior notes:
- Requires `git` and `doas`, and expects a clean working tree (it refuses to run with local uncommitted changes).
- Fast-forwards the local checkout from the configured remote/branch (no merge of divergent histories).
- Records the last successfully applied commit in `${XDG_STATE_HOME:-$HOME/.local/state}/openbsd-setup/last-applied` so failed runs do not advance state.
- Runs `doas sh ./update.sh ...`; log out/in or reboot as needed after applied changes.

## Safety notes

- **Review before applying:** this repo manages sensitive areas (`/etc/ssh`, `doas.conf`, `pf.conf`, `resolv.conf` handling via unwind/resolvd flow, service enablement, login/session files). Treat it as code you are deploying to your machine.
- **No secrets in git:** keep credentials out of the repo. `secrets/` is gitignored for local-only material (except its `.gitignore`); still verify before committing or publishing.
- **Hardware/network specifics:** example NIC/interface names, firmware needs, and device paths differ. Confirm wireless config files and permissions locally; never store passphrases in tracked files.
- **Idempotent, not harmless:** re-running can overwrite managed files (with backups for user files where implemented) and change system behavior.

## Development / validation

```sh
make check      # shell syntax + config sanity (safe on non-OpenBSD hosts in static mode)
sh ./validate.sh
```

Some checks are only meaningful on OpenBSD. A libvirt/QEMU rehearsal workflow is available via `vm` for contributors who want to test changes in a disposable VM; treat `vm` as optional/dev tooling and adjust paths/network settings for your environment.

## License / attribution

This repository vendors third-party assets and patches in places (e.g. fonts, `st` patches/config inputs). Review files under `share/` and other directories for their respective licenses/attributions before redistribution or reuse.
