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
| `home/` | dotfiles for `peter` |
| `packages.txt` | portable packages |
| `packages-vm.txt` | VM-only packages (intentionally empty, see below) |
| `provision.sh` | apply everything to a fresh install |
| `validate.sh` | `sshd -t`, `pfctl -n`, `doas -C` |
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
3. Copy this repo to the target, then:

```sh
doas ./provision.sh --metal
```

`--metal` applies `etc-hardware/` instead of `etc-vm/`, installs the portable
packages, runs `fw_update`, and does not add `vio0`, the serial console, or
root SSH. Root stays locked out (`PermitRootLogin no`, `AllowUsers peter`).
Reboot afterwards.

## Gotchas worth remembering

- `pkg_add -l` does **not** skip `#` comments and needs exact package names
  when a stem is ambiguous (`rsync` → `rsync-3.5.1`).
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
