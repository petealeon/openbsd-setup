# OpenBSD setup

Target: **OpenBSD 8.0 amd64**, rehearsed in a libvirt/KVM VM on Omarchy and later
applied to a fresh install on the T480s.

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
| `packages-vm.txt` | VM-only packages |
| `provision.sh` | apply everything to a fresh install |
| `validate.sh` | `sshd -t`, `pfctl -n`, `doas -C` |
| `vm` | host-side VM and config CLI |

## First install (VM)

On the host:

```sh
omarchy pkg add qemu-full libvirt virt-install virt-manager edk2-ovmf rsync
sudo systemctl enable --now libvirtd.service
sudo usermod -aG libvirt,kvm peter      # log out and back in
sudo virsh net-autostart default
sudo virsh net-start default
```

Then:

```sh
cd ~/Work/openbsd-setup
./vm new
virt-manager --connect qemu:///system   # open the openbsd console
```

Installer answers:

- `(I)nstall`
- disk `sd0`, whole disk, GPT, auto disklabel
- hostname `openbsd`
- `vio0`: DHCP (IPv6 default is fine)
- root password, then `sshd` **yes**
- X Window System **yes**, start it with `xenodm` **yes**
- user `peter`, in `wheel`, with a password
- `doas` **yes**
- timezone, then reboot

Eject the ISO when it reboots:

```sh
virsh --connect qemu:///system change-media openbsd sda --eject
```

Pin the address once (get the MAC from `virsh domiflist openbsd`):

```sh
virsh --connect qemu:///system net-update default add ip-dhcp-host \
  '<host mac="52:54:00:xx:xx:xx" ip="192.168.122.50"/>' --live --config
```

Then bootstrap (asks for the guest password twice):

```sh
ssh-copy-id peter@192.168.122.50
./vm bootstrap
```

After this, `ssh root@openbsd` works with the same key, so `vm apply` and
`vm capture` need no password.

## Daily loop

```sh
./vm ssh                 # shell on the guest
./vm run 'make'          # one command in the guest
./vm apply               # push repo -> guest, validate, restart sshd
./vm capture             # pull tracked guest config -> repo
./vm snap before-update  # libvirt snapshot
./vm status              # state + address
./vm console             # serial console (Ctrl-])
```

Edit config on the host, `vm apply`, test, commit. If you configure something
by hand in the guest, `vm capture` brings it back into the repo.

## Export to bare metal

1. Fresh OpenBSD 8.0 install on the target (the installer creates `peter`).
2. Bring up networking (`/etc/hostname.iwm0` or `em0`).
3. Copy this repo over, then:

```sh
doas ./provision.sh --metal
```

`--metal` skips `qemu-ga`, `vio0`, the serial console and root SSH, and applies
`etc-hardware/` instead. Reboot afterwards.

## What is deliberately not tracked

`/etc/fstab` (DUID-specific), `/etc/mygate`, `/etc/ssh/ssh_host_*`,
`/etc/master.passwd`, `/etc/passwd`, `/etc/group`, `/etc/host.random`,
`/var/db/*`. Each install generates those itself.
