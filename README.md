# OpenBSD setup

Target: **OpenBSD 8.0 amd64**, rehearsed in a libvirt/KVM VM on Omarchy and later
applied to a fresh install on the T480s. The repo, not the VM, is the deliverable.

## Hard rule

The internal 2 TB disk (`/dev/nvme0n1`, Windows + the existing OpenBSD install on
`nvme0n1p5`) is **read-only** for this project. Do not partition it, mount it,
run `installboot` against it, or write disk images to it. The VM disk lives at
`~/VMs/openbsd/openbsd.qcow2` on the USB Omarchy SSD.

## Layout

| Path | Purpose |
|---|---|
| `etc/` | portable `/etc` overlay |
| `etc-vm/` | VM-only (`vio0`, serial console, root SSH) |
| `etc-hardware/` | T480s-only (`iwm0`, `em0`, wscons) |
| `home/` | dotfiles, `bin/` helpers, amber theme, wallpapers |
| `lib/stages/` | one script per install stage (`system`, `packages`, `terminal`, `desktop`, `browser`, `gaming`, `validate`) |
| `share/st/` | pinned st source config, patches, `build.sh` |
| `share/fonts/` | BlexMono Nerd Font + licence (vendored) |
| `packages.txt` | packages (stems only, no pinned versions) |
| `packages-vm.txt` | VM-only packages (intentionally empty, see below) |
| `install.sh` | the one front door: stages, `--dry-run`, `--only=` |
| `provision.sh` | compatibility wrapper around `install.sh` |
| `validate.sh` | `sshd -t`, `pfctl -n`, `doas -C`, shell syntax |
| `vm` | host-side VM and config CLI |
| `docs/install.conf.vm` | untested draft autoinstall response file |

## Host prep (Omarchy)

```sh
sudo pacman -S qemu-full libvirt virt-install virt-manager edk2-ovmf rsync
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,kvm "$USER"     # log out and back in
sudo virsh net-start default
sudo virsh net-autostart default
```

If `ufw` is active, allow DHCP/DNS on `virbr0` and routed traffic in:

```sh
sudo ufw allow in on virbr0 to any port 67 proto udp
sudo ufw allow in on virbr0 from 192.168.122.0/24 to 192.168.122.1 port 53
sudo ufw route allow in on virbr0
```

`sg` is not installed; run individual libvirt commands as
`printf '...\n' | newgrp libvirt`.

## Create the VM

Download the ISO to `~/VMs/openbsd/install80.iso` (or set
`OPENBSD_VM_DIR`/`OPENBSD_VM_ISO`), then:

```sh
cd ~/Work/openbsd-setup
./vm new
```

`vm new` builds: 4 vCPU, 6 GiB RAM, 40 GiB qcow2, `q35` + non-Secure-Boot
OVMF, virtio disk/net, VGA + SPICE, 115200 serial console, and a pinned MAC
(`52:54:00:8c:51:3a`) so the DHCP reservation survives rebuilds.

The OVMF varstore is created as **qcow2** (`~/VMs/openbsd/OVMF_VARS.qcow2`).
libvirt refuses internal snapshots when pflash NVRAM is raw.

Add the DHCP reservation once:

```sh
virsh --connect qemu:///system net-update default add ip-dhcp-host \
  '<host mac="52:54:00:8c:51:3a" ip="192.168.122.50"/>' --live --config
```

## Install OpenBSD

Either open the console in virt-manager, or use the serial console:

```sh
./vm console
```

The installer's bootloader starts on VGA. To follow the install over the serial
console, interrupt it at the `boot>` prompt and type:

```
set tty com0
boot
```

(The installed system gets `/etc/boot.conf` from `etc-vm/`, so later boots go
to `com0` by themselves.)

Answers (verified over serial, OpenBSD 8.0):

| Prompt | Answer |
|---|---|
| `(I)nstall` | `I` |
| terminal type | `vt220` |
| system hostname | `openbsd` |
| network interface | `vio0` |
| IPv4 for `vio0` | `autoconf` |
| IPv6 for `vio0` | `none` |
| DNS domain / nameservers | empty / `none` |
| root password | generated, see `secrets/vm-passwords` |
| start sshd | `yes` |
| X Window System | `yes` |
| default console `com0` | `yes`, `115200` |
| setup a user | `peter`, full name `Peter`, in `wheel` |
| allow root ssh login | `no` |
| root disk | `sd0` |
| disk layout | **`g` (GPT)** |
| encryption | `no` |
| auto layout | `A` |
| timezone | `Europe/Dublin` |
| sets location | `cd0`, pathname empty, set names `all` |
| verification | continue without verification |
| final | `H` (halt) |

**Do not answer `whole` to the whole-disk question**: that selects MBR, which
leaves no ESP and produces an unbootable UEFI disk. Answer `g`.

OpenBSD `halt` leaves the libvirt domain running, so finish from the host:

```sh
virsh --connect qemu:///system destroy openbsd
virsh --connect qemu:///system change-media openbsd sda --eject --config
./vm up
```

The system now boots from `vda` via UEFI and has `192.168.122.50` from DHCP.

## First bootstrap

```sh
ssh-copy-id peter@192.168.122.50
./vm bootstrap
```

The installer does **not** create `/etc/doas.conf`. The first `vm bootstrap`
copies the repo into the guest, then stops and prints the exact fix: log in on
the serial console as root (`./vm console`) and run

```sh
install -m 600 /home/peter/openbsd-setup/etc/doas.conf /etc/doas.conf
```

Run `./vm bootstrap` again; it asks for `peter`'s password once (doas), then
installs packages, overlays `/etc` and `home/`, adds the `sshd` drop-ins, the
serial getty, enables `xenodm`, installs the root SSH key, validates, and
reloads `sshd`. After that `ssh root@openbsd` works and `vm apply` needs no
password.

Log in on the VGA console once to confirm xenodm → spectrwm, then snapshot:

```sh
./vm snap baseline
```

## Daily loop

```sh
./vm ssh                 # shell on the guest
./vm run 'make'          # one command in the guest
./vm apply               # push etc/ + etc-vm/ + home/, validate, reload sshd
./vm capture             # pull tracked guest config back into the repo
./vm snap before-update  # internal snapshot (qcow2 NVRAM, disk)
./vm status              # state + lease
./vm console             # serial console (Ctrl-])
```

Edit on the host, `vm apply`, test, commit. If you configure something by hand
in the guest, `vm capture` brings it back into the repo.

Snapshots:

```sh
virsh --connect qemu:///system snapshot-list openbsd
virsh --connect qemu:///system snapshot-revert openbsd baseline
virsh --connect qemu:///system snapshot-delete openbsd before-update
```

`vm down` shuts down via ACPI; `vm off` is a hard power off (necessary after a
guest `halt`, which leaves the domain "running").

### Console pointer grab

The SPICE console grabs the pointer because OpenBSD's `ums` driver has no
absolute-pointer support (no SPICE agent either). While grabbed, the window
title says *"Press Shift+F12 to release pointer."*

This host is configured to use **Shift+F12**. virt-manager's default is
Ctrl+Alt, which collides with other things; to restore it:

```sh
gsettings reset org.virt-manager.virt-manager.console grab-keys
```

If any grab ever swallows the keyboard: `Ctrl+Alt+F2` (VT switch, handled by
the kernel), log in, `pkill -f virt-manager`, then `Ctrl+Alt+F1` back to the
desktop.

## Export to bare metal

1. Fresh OpenBSD 8.0 install on the T480s (the installer creates `peter`).
2. Bring up networking: copy `etc-hardware/hostname.iwm0.example` to
   `/etc/hostname.iwm0` on the target and fill in SSID/passphrase (keep the
   passphrase out of git). `hostname.em0` is already in `etc-hardware/`.
3. Clone the repo as your user, then run it as root:

```sh
git clone <repo> ~/openbsd-setup
cd ~/openbsd-setup
doas ./install.sh --metal
```

`install.sh` walks idempotent stages: `system` (syspatch, fw_update, the
`etc-hardware/` overlay, xenodm/apmd/hotplugd), `packages` (`pkg_add`),
`terminal` (builds st 0.9.2 and installs BlexMono), `desktop` (dotfiles, amber
theme, wallpapers, `~/bin`), `browser` (Chromium policy and adblocker),
`gaming` (emulators, its own stage because it needs ~3 GiB in `/usr/local`) and
`validate`. Re-running it after editing the
repo is the normal workflow; anything it replaces is first copied to
`~/.config-backup-<timestamp>/`.

Useful variants:

```sh
./install.sh --metal --dry-run          # print every change, touch nothing
doas ./install.sh --metal --only=desktop
doas ./install.sh --metal --only=terminal   # just rebuild st
./install.sh --list                     # stage order
```

Root stays locked out (`PermitRootLogin no`, `AllowUsers peter`). Reboot
afterwards to pick up sshd, xenodm and the wscons settings.

`st` is compiled from upstream 0.9.2 with the scrollback, scrollback-mouse and
clipboard patches; its palette and font live in `share/st/config.h`. The alpha
patch does **not** apply to 0.9.2, so terminal transparency is picom's job
(`~/.config/picom/picom.conf`).

## Browser

Chromium's launcher on OpenBSD is `chrome` (`BROWSER=chrome` in `~/.profile`);
`chromium` is only the package name. It is pledged and unveiled, so dotfiles
cannot load an extension into it — but managed policy works, and
`/etc/chromium/unveil.main` already exposes `/etc/chromium` read-only.

The browser stage installs `etc/chromium/policies/managed/amber.json`, which
force-installs **uBlock Origin Lite** from the Web Store and turns off the
noise: no bookmarks bar, no default-browser nag, no background mode, no sync
prompts, no credit-card autofill. Chromium calls home for the extension on its
next launch; the stage pre-warms the profile headless so the first real window
already blocks ads, and says so — or warns that it was offline.

It is the *Lite* build because Chromium 156 dropped Manifest V2 and classic
uBlock Origin can no longer load. To see it in the browser:
`chrome://extensions` (the policy-installed one is pinned, not removable) and
`chrome://policy` for the active settings.

Downloading from the browser is Omarchy's flow, without an extension:

| Key | What it does |
|---|---|
| `Super+Shift+B` | `~/bin/browser`: Chromium with `--no-first-run`, so a fresh profile skips the "Additional Terms of Service" dialog (no policy covers it) |
| `Super+Shift+D` | `~/bin/video-download`: reads the focused tab's URL and runs `yt-dlp` in an `st` window, best video ≤1080p muxed to mp4 in `~/Videos/Downloads` |
| `Super+Shift+C` | `~/bin/copy-url`: copies the focused tab's URL to the clipboard (restoring what was there) |

`video-download` reads the clipboard first, because that is the route that
always works: `Ctrl+L`, `Ctrl+C` in Chromium, then `Super+Shift+D`. Only when
the clipboard holds no URL does it fall back to driving the browser with
`xdotool` (`copy-url`), since a sandboxed, unveiled browser cannot be asked
which page it is on. It also accepts a URL argument, so terminal downloads use
the same helper.

Caveat from the rehearsal VM: the `xdotool` fallback could not be exercised
there at all — the wsfb X server delivered no synthetic key events, not even
to `st`, so `Super+Shift+C` is untested until it runs on the T480s. The
clipboard route and the download itself are verified.

`yt-dlp` gets a JavaScript runtime (`deno`) because YouTube's player needs one
to solve its challenges; without it yt-dlp reports most videos as
"unavailable". Verified on OpenBSD 8.0: a YouTube URL downloads and muxes to
mp4 with the bundled `ffmpeg`.

## Gotchas worth remembering

- `pkg_add -l` does **not** skip `#` comments; `lib/stages/packages.sh`
  filters them into a temporary list. If a stem matches more than one
  package, pin it with the empty-version form (`rsync--`) instead of a
  version, which would break the next `pkg_add -u`.
- st's Makefile uses `$(shell ...)`, so it needs `gmake`, and it sets
  `CC = c99`, which OpenBSD 8.0 no longer ships: `build.sh` overrides both.
  freetype/fontconfig are in xenocara (no packages, no .pc files), so the
  build passes their include/link flags explicitly. The alpha patch fails
  against 0.9.2; use picom for opacity.
- The `chromium` package installs its launcher as `chrome`, not `chromium`.
- Chromium policy lives in `/etc/chromium/policies/managed/*.json`. Files that
  set the same key are merged, so the browser stage warns about any extra
  policy file it finds next to `amber.json`.
- Rehearsed on 2026-11-03: the force-install policy fetched uBlock Origin Lite
  2026.1026.1812 into a fresh profile in under a minute on Chromium 156.
- `tmux`, `pkg-config` and `doas` are base-system; do not list them as packages.
- A 40 GiB auto-layout VM gives `/usr/local` only ~4.7 GiB, which the gaming
  set does not fit in. That is why gaming has its own stage with a free-space
  check; the T480s has plenty.
- spectrwm does **not** expand `$HOME` in `bar_action` or in `program[]`
  paths; `install.sh` bakes the real home directory into `~/.spectrwm.conf`.
- `quirk[...]` keys end at the first `]`, so a bracket expression such as
  `[Zz]athura` is a parse error and spectrwm paints the exception into the
  bar. Use `.*athura.*` instead.
- xenodm's stock `Xsetup_0` starts `xconsole`, which lands in the main tile
  on a tiling desktop. The session cannot kill it (xenodm owns it as
  root/_x11), so this repo ships `etc/X11/xenodm/Xsetup_0` without it.
- Rehearsed on 2026-11-03: st 0.9.2 builds and runs, spectrwm + picom + dunst
  + clipmenud + xidle start, the amber bar renders and the wallpaper applies.
  Gaming was skipped by its free-space guard in the 40 GiB VM.
- In `.spectrwm.conf`, `#` starts a comment, so colours must use
  `rgb:rr/gg/bb` (not `#rrggbb`). `bar_type` does not exist in spectrwm 3.7.0.
- There is no `qemu-ga` in the VM: OpenBSD has no virtio-serial/virtio-console
  driver, so the agent can never connect. Shutdown uses ACPI and works.
- `AllowUsers` is a whitelist. The VM drop-in must list `root peter`, or
  `peter` loses SSH after the next reload.
- Overlays are archived from `peter`-owned files: `provision.sh` and `vm apply`
  chown `/etc` entries back to `root:wheel` and `chmod 600 /etc/doas.conf`.
- Eject the ISO before rebooting; otherwise the installer boots again.

## What is deliberately not tracked

`/etc/fstab` (DUID-specific), `/etc/mygate`, `/etc/ssh/ssh_host_*`,
`/etc/master.passwd`, `/etc/passwd`, `/etc/group`, `/etc/host.random`,
`/var/db/*`. Each install generates those itself.
