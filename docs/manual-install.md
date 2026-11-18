# Manual install — OpenBSD 8.0 → amber X11 desktop

A runbook for a human, at the machine, installing OpenBSD 8.0 by hand into free
space on an NVMe disk that already holds Windows 11 Pro, then building the
desktop described in [`x11-ml4w-plan.md`](x11-ml4w-plan.md).

Status: **manual procedure, verified against the repo and OpenBSD's documented
installer/`fdisk`/`installboot` behaviour.** The automated equivalent is
`install.sh` + `lib/stages/*`; the plan-only desktop work (Tier 1/2) is marked
as such wherever it appears.

> **This is the one document that intentionally writes to a disk shared with
> Windows.** `README.md` declares the *host's* `/dev/nvme0n1` read-only for
> this project, and that rule still binds every script and agent here. This
> runbook exists because a human, at the console, with the layout recorded and
> a backup in hand, is the only thing allowed to partition that disk.

Target hardware: ThinkPad T480s, UEFI, GPT, one NVMe disk, one 1080p panel,
`iwm0` wifi, `em0` ethernet. Nothing here depends on the model except those
device names.

## Time and disk budget

| Phase | Time | Result |
|---|---|---|
| 0. Prepare Windows | 30–90 min (BitLocker slowdowns dominate) | 80 GiB unallocated, UTC RTC, no fast startup |
| 1. Media and firmware | 20 min | Bootable USB, Secure Boot off, UEFI only |
| 2. Installer | 20–30 min | OpenBSD on the free space, Windows untouched |
| 3. Boot path | 10 min | Firmware menu boots both systems |
| 4. Base system | 20 min | Patched, networked, `doas`, services |
| 5. Packages | 15–40 min | ~130 packages, ~2–3 GiB |
| 6. st + fonts | 5 min | Terminal and BlexMono |
| 7. `/etc` | 15 min | Firewall, sshd, xenodm, chromium, suspend |
| 8. Desktop | 20 min | spectrwm + amber theme, every helper |
| 9. Browser + gaming | 15 min + 3 GiB | uBlock Origin Lite, RetroArch |
| 10. Validate | 10 min | `make check`, live login |
| X1–X5 | 1 evening + 4 sessions | picom blur/rounding, themed login, i3, polybar |

Disk: **80 GiB** is the recommended free-space figure. The file sets are
~1 GiB, the package set ~2–3 GiB, the emulators ~3 GiB, `st`'s build ~100 MiB,
and auto-layout swap scales with RAM. 40 GiB works if you skip gaming and keep
`/home` small; below 25 GiB auto layout starts shortchanging `/usr/local`.

---

## 0. Read this before touching the disk

You are about to put a second operating system on a disk whose boot path
Windows owns. Four things make that safe, in this order:

1. **A backup you have restored from once.** Not "a backup": one you tested.
2. **A Windows recovery USB.** Windows 11 Pro: *Create a recovery drive*,
   tick "Back up system files". Also record the BitLocker recovery key if
   BitLocker is on (`manage-bde -protectors -get C:`).
3. **A recorded layout.** Partition numbers, types, byte offsets and sizes,
   plus the current firmware boot order. You will compare the installer's view
   against this before you write anything.
4. **A named stop condition.** If the free region in the installer differs from
   what Windows reported, stop. If a partition you did not create is about to
   move, stop. Do not "fix it later" inside the installer.

Record the layout on Windows, in an **administrator** PowerShell:

```powershell
Get-Disk | Format-Table Number,FriendlyName,PartitionStyle,Size
Get-Partition -DiskNumber 0 |
  Format-Table PartitionNumber,DriveLetter,Type,Offset,Size -AutoSize
```

Note the disk number of the NVMe Windows disk (almost always `0`). For every
partition record `PartitionNumber`, `Type`, `Offset` (bytes) and `Size`
(bytes). `Offset / 512` is the OpenBSD/fdisk start LBA you will compare
against later.

Also record the firmware boot order, for restoring it if Windows stops booting:

```powershell
bcdedit /enum firmware
```

Save the output to a file on a USB stick. It is your map back.

---

## 1. Prepare Windows 11 Pro

Do all of this **in Windows**, before you boot anything else. Resizing from
outside Windows, or with a third-party tool on an encrypted volume, is how
people lose the Windows install.

### 1.1 BitLocker: suspend it, or decrypt it

OpenBSD cannot read BitLocker, and that is not the problem. The problem is
that disabling Secure Boot, changing the boot order, or letting another boot
loader write to the ESP changes the measurements BitLocker seals against, so
the next Windows boot stops at the recovery screen.

Check the state (admin PowerShell):

```powershell
manage-bde -status C:
```

Then either suspend protection across the next two reboots:

```powershell
manage-bde -protectors -disable C: -rebootcount 2
```

…or, if you are going to keep dual-booting for a while, decrypt fully and
re-encrypt after OpenBSD is installed and the boot order is final:

```powershell
manage-bde -off C:
manage-bde -status C:      # wait for "Percentage Encrypted: 0.0%"
```

Decryption of a full disk takes a while; it is also the least surprising
option, because an encrypted volume plus a resized partition table plus a
second boot loader is three independent ways to end up at the recovery prompt.
Whichever you choose, **have the recovery key written down** before rebooting.

Note for later: with Secure Boot off, Windows still runs, but BitLocker's
TPM-only protector becomes fragile and some anti-cheat software refuses to
start. Decide deliberately; this is the price of OpenBSD on the same machine.

### 1.2 Turn off Fast Startup and hibernation

Fast Startup leaves NTFS in a hibernated, dirty state that no other OS should
mount, and it also keeps a `hiberfil.sys` that blocks shrinking.

```powershell
powercfg /h off
powercfg /a          # should now report hibernation unavailable
```

Also confirm Windows is fully shut down, not "fast started": *Shut down* with
Fast Startup off is a real shutdown.

### 1.3 Put the hardware clock in UTC

OpenBSD reads the RTC as UTC and will not be told otherwise. Windows, by
default, stores local time there, so a dual-boot machine shows a clock that is
wrong by your UTC offset in one OS or the other. Fix Windows once:

```powershell
reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
```

Reboot, confirm Windows still shows the right local time, then continue.
(`RealTimeIsUniversal` is unsupported by Microsoft but is the standard fix and
survives feature updates in practice. If a future update resets it, re-apply
and re-check both systems.)

### 1.4 Shrink C: and leave the space unallocated

Use Disk Management (`diskmgmt.msc`) or `diskpart`. The GUI is harder to get
wrong; `diskpart` is easier to record.

```
diskpart
list disk
select disk 0
list partition
select partition 3          # the large "Primary" partition, your C:
shrink desired=81920        # MB → 80 GiB
exit
```

If Windows refuses to shrink as far as you want, it is holding immovable files
at the end of the volume. In order, try:

1. `powercfg /h off` (done above) and reboot.
2. Disable System Restore on C: temporarily, retry, re-enable.
3. Set the page file on C: to "No paging file", retry, restore it.
4. `defrag C: /X` (consolidate free space), retry.
5. Shrink in two steps (e.g. 40 GiB, reboot, 40 GiB again).

Do **not** create a partition, format it, or assign a drive letter to the new
free space. It must stay "Unallocated". Do not touch the EFI System Partition,
the 16 MB "Reserved" partition, or the recovery partition: OpenBSD needs the
ESP as it is, and Windows needs the other two.

Then confirm the result and let Windows check its own filesystem:

```powershell
Get-Partition -DiskNumber 0 |
  Format-Table PartitionNumber,Type,Offset,Size -AutoSize
chkdsk C: /scan
```

Reboot Windows once more. If it does not boot cleanly now, stop: you have a
Windows problem, not an OpenBSD one, and it is much cheaper to fix before the
partition table changes.

Write the free region down in sectors:

```
free_start_LBA = (start of the partition after the gap) - free_size_in_sectors
free_end_LBA   = (start of the partition after the gap) - 1
free_size      = free_end_LBA - free_start_LBA + 1
```

Worked example (a 512 GB disk, C: shrunk by exactly 80 GiB):

| # | Type | Start LBA | Size (sectors) | Last LBA |
|---|---|---|---|---|
| 1 | EFI Sys | 34 | 204800 | 204833 |
| 2 | MS Reserved | 204834 | 32768 | 237601 |
| 3 | MS Basic (C:) | 237602 | 232227840 | 232465441 |
| — | **free** | **232465442** | **167772160** | **400237601** |
| 4 | Windows RE | 400237602 | 2097152 | 402334753 |

So in the installer: offset `232465442`, size `167772160`. Your numbers will
differ; use yours. 1 GiB = 2097152 sectors of 512 bytes.

### 1.5 Optional but cheap: update firmware and Windows first

Lenovo Vantage / Windows Update for the BIOS and Thunderbolt firmware, then
`sfc /scannow`. A firmware update after partitioning can reorder boot entries;
doing it before means one less variable.

---

## 2. Install media and firmware

### 2.1 Download and verify

Use **`install80.img`**, not `miniroot80.img` — the `install*.img` images
include the file sets, so one USB stick installs the whole system offline.

```sh
mkdir -p ~/iso && cd ~/iso
curl -O https://cdn.openbsd.org/pub/OpenBSD/8.0/amd64/install80.img
curl -O https://cdn.openbsd.org/pub/OpenBSD/8.0/amd64/SHA256
curl -O https://cdn.openbsd.org/pub/OpenBSD/8.0/amd64/SHA256.sig
sha256sum -c --ignore-missing SHA256
```

If `signify` is installed (`signify-openbsd` on Debian/Ubuntu, `signify` on
Arch), verify the signature too — the checksum file alone only proves the
download is intact, not that it is genuine:

```sh
signify -Cp /etc/signify/openbsd-80-base.pub -x SHA256.sig install80.img
```

That key path is the OpenBSD one; point `-p` at your signify package's
`openbsd-80-base.pub` if it lives elsewhere.

### 2.2 Write the USB

Linux (replace `/dev/sdX` with the whole stick, not a partition):

```sh
lsblk
sudo dd if=install80.img of=/dev/sdX bs=1M status=progress conv=fsync
sync
```

macOS: `diskutil list`, then `sudo dd if=install80.img of=/dev/rdiskX bs=1m`.
Windows: use Win32DiskImager or `dd` under WSL with the raw device. The image
is a full disk image: it replaces the stick's partition table, it is not a file
you copy onto a FAT32 stick.

### 2.3 T480s firmware settings

Reboot, press **F1** for BIOS Setup:

| Setting | Value | Why |
|---|---|---|
| Security → Secure Boot → Secure Boot | **Disabled** | OpenBSD's loader is not signed; firmware will not run it otherwise |
| Startup → UEFI/Legacy Boot | **UEFI Only** | the install must be UEFI on a GPT disk, or it cannot boot alongside Windows |
| Startup → CSM Support | Disabled (implied by UEFI Only) | |
| Startup → Boot Mode | Quick (or Diagnostics while testing) | |
| Config → Thunderbolt BIOS Assist / Security Level | leave alone | irrelevant to this install |
| Security → TPM | leave enabled | OpenBSD ignores it; Windows may want it later |

Press **F10** to save. Then **F12** at the logo for the one-time boot menu:
pick the **UEFI** entry for the USB stick, not a legacy one. Firmware menus
that list the same device twice are the classic way to install a system that
will not boot.

Sanity check: the installer banner must say `Welcome to the OpenBSD/amd64 8.0
installation program`. If it says `i386`, you booted the wrong way.

---

## 3. Installer, step by step

### 3.1 Look at the disk before you change it

At the first prompt choose **(S)hell** and confirm the installer sees the same
disk Windows described:

```sh
sysctl hw.disknames          # sd0 sd1 ...; the USB is usually the last
dmesg | grep -E '^(sd|nvme)[0-9]'
fdisk -v sd0                 # NOT sd0c
```

Match the model string and the sector count against Windows' disk size. The
internal NVMe is `sd0` on a T480s; the USB stick is `sd1`. If you cannot match
them, stop.

`fdisk -v sd0` prints the primary and secondary GPT. Compare partition starts
and sizes with the table from §1.4. The free region must be exactly where
Windows left it. Write down the free `start` and `size` again — you will type
them in a moment.

Leave the shell with `exit` to return to the installer prompt.

### 3.2 Answer sheet

| Prompt | Answer | Notes |
|---|---|---|
| `(I)nstall, (U)pgrade, (A)utoinstall or (S)hell?` | `I` | |
| Terminal type | `vt220` | accept the default |
| System hostname | `t480s` | short, no domain |
| Network interface | `em0` | built-in ethernet; `iwm0` needs firmware that is not on the media |
| IPv4 address for em0 | `autoconf` | |
| IPv6 address for em0 | `none` | or `autoconf` if you use it |
| DNS domain name | *(empty)* | DHCP supplies the rest |
| DNS nameservers | `none` | |
| Password for root | *(strong)* | |
| Start sshd by default | `yes` | |
| Do you want the X Window System | `yes` | xenodm and the desktop need it |
| Do you want to change the default console to com0 | `no` | that is the VM's setting, not metal's |
| Setup a user | `peter` | must match the repo's default `--user` |
| Full name | `Peter` | |
| Password for user | *(strong)* | |
| Allow root ssh login | `no` | the repo's sshd drop-in enforces this anyway |
| Which disk is the root disk | `sd0` | **verify against the model string** |
| Use (W)hole disk MBR, whole disk (G)PT, (O)penBSD area or (E)dit | `E` | the only safe answer on a shared disk |
| Encrypt the root disk | `no` | partition-preserving encryption is a separate procedure |
| Use (A)uto layout, (E)dit layout | `A` | auto layout inside the OpenBSD area only |
| What timezone are you in | `Europe/Dublin` | match the repo's default; `?` lists zones |
| Location of sets | `cd0` | the USB image presents its sets as `cd0` |
| Set name(s) | `all` | |
| Continue without verification | `yes` | the image's signature was verified in §2.1 |
| Exit to (S)hell, (H)alt or (R)eboot | `H` or `R` | then remove the USB |

Three of those answers destroy data if given on the wrong disk: `G`, `W`, and
anything but `E` at the partition prompt. `G` writes a fresh GPT containing a
single OpenBSD partition. `W` does the same with MBR. Neither asks twice.

### 3.3 Create the OpenBSD partition in the free space

Answering `E` opens `fdisk -e sd0`. The prompt looks like `sd0*:1>`. Work only
in the free slot (in the example, entry 5), and never touch entries 1–4.

```
print                       # compare with your recorded table, again
edit 5                      # the first unused GPT entry
offset: 232465442           # free_start_LBA from §1.4 — YOUR number
size: 167772160             # free_size from §1.4 — YOUR number
type: OpenBSD               # accept the default OpenBSD (A6) type
print                       # 1-4 unchanged, 5 is OpenBSD, same start/size
write
quit
```

If `edit` does not offer a type, set it separately before writing:
`setpid 5`, choose `OpenBSD` (`A6`), then `print`, `write`, `quit`.

Notes that save an install:

- `offset` and `size` are 512-byte sectors. Type digits only; `b`/`k`/`m`/`g`
  suffixes are accepted by newer `fdisk`, but digits are unambiguous.
- If `edit 5` offers defaults, read them before pressing Enter. They are only
  correct if they equal your recorded free region.
- `reinit` re-creates the GPT. It is the command that erases Windows. Never
  type it here.
- If the OpenBSD entry already exists (a previous install — the repo's target
  machine has one on `nvme0n1p5`), either select it with `O` at the installer's
  partition prompt to reinstall into that same area, or delete it in `fdisk`
  (`delete 5`, `write`, `quit`) and use its space with a new entry. Both wipe
  its contents; copy anything you need off it first.
- After `write`, the installer re-reads the GPT and shows the OpenBSD area it
  found. That number should equal your `size`.

### 3.4 disklabel: filesystems inside the OpenBSD area

`A` (auto layout) splits the OpenBSD area into `/`, swap, `/tmp`, `/var`,
`/usr`, `/usr/X11R6`, `/usr/local`, `/home`, `/usr/src`, `/usr/obj`. Accept it,
then check the sizes it chose at the confirmation screen.

Things to look for:

- **`/usr/local` ≥ 4 GiB.** Packages (Chromium, fonts, emulators) live there,
  and `wxallowed` is set on it so those packages can run. If auto layout gives
  it less than ~3.5 GiB, choose `E` and grow it. With 80 GiB free this is
  usually fine.
- **swap.** Auto layout scales swap with RAM; on a 24 GB machine that can be
  most of the disk. 8–16 GiB is plenty for suspend-to-disk plus a laptop's
  working set. Adjust in `disklabel -E sd0` (`d b`, `a b`, new size) if you
  care, or leave it and lose the space.
- **`/home`.** Your music, videos and ROMs live here; give it the remainder.

Manual disklabel editing (inside the installer it is the `E` choice; later it
is `doas disklabel -E sd0`) uses the same commands:

```
sd0> p                       # print the label
sd0> a a                     # add/modify partition a
offset: [64]
size: [167772160]
FS type: [4.2BSD]
sd0*> w
sd0> q
```

`c` is the whole disk and must not be reused. Filesystem types: `4.2BSD` for
everything except swap (`swap`).

### 3.5 Sets, timezone, finish

`cd0` is right when you booted `install80.img`: the image carries the sets on
its own FFS partition. If the installer insists on a disk location, answer
`disk`, pick the USB device from `sysctl hw.disknames` (e.g. `sd1`), then
partition `a`. If the media was not signature-verified, do not answer `yes` to
"Continue without verification".

The installer extracts the sets, asks for the timezone, then offers
`(S)hell`, `(H)alt`, `(R)eboot`. Choose `H` (or `R`), **remove the USB stick**,
and power on. If you leave the stick in, you will re-enter the installer and
may re-run it against the wrong disk.

### 3.6 First boot path

The firmware still boots Windows first. That is expected: OpenBSD installed
its loader but the NVRAM boot order belongs to Windows Boot Manager.

1. Power on, press **F12**, and look for the entry that is the internal NVMe
   (often `NVMe0: <model>`), not `Windows Boot Manager`.
2. Select it. The OpenBSD boot loader (`boot>`) should appear, then the kernel.
3. If it boots Windows anyway, the ESP does not have a working OpenBSD loader;
   see §3.7.

Once OpenBSD boots, make the choice permanent in the direction you want:

```sh
# OpenBSD first at power-on, Windows via F12:
doas installboot -v sd0          # reinstall both stages, print what it does
doas installboot -c sd0          # UEFI/GPT: add/point the default boot entry

# or leave Windows first and use F12 for OpenBSD: do nothing.
```

`installboot -c` only works on amd64/arm64 with UEFI and GPT, and it may fail
on firmware that refuses new variables. Either policy is fine; record which one
you chose, because a Windows feature update may rewrite the order.

### 3.7 Verify the ESP, and repair it if needed

OpenBSD's UEFI loader is `\EFI\BOOT\BOOTX64.EFI` on the **existing** ESP. It
does not touch `\EFI\Microsoft\Boot\bootmgfw.efi`, so Windows keeps its own
loader. Verify:

```sh
doas fdisk -v sd0 | grep -i 'EFI Sys'   # note start and size of the ESP
```

To read the ESP from OpenBSD you need a disklabel entry mapping it (this edits
only the OpenBSD disklabel, never the GPT):

```sh
doas disklabel -E sd0
sd0> a i
offset: 34                 # ESP start LBA from fdisk -v
size: 204800               # ESP size from fdisk -v
FS type: [MSDOS]           # type MSDOS
sd0*> w
sd0> q

doas mount -t msdos /dev/sd0i /mnt
ls -l /mnt/efi/boot        # BOOTX64.EFI should be there
doas umount /mnt
```

If it is missing, or `installboot` reported a failure, install it by hand:

```sh
doas mount -t msdos /dev/sd0i /mnt
doas mkdir -p /mnt/efi/boot
doas cp /usr/mdec/BOOTX64.EFI /mnt/efi/boot/BOOTX64.EFI
doas umount /mnt
```

`installboot` can also fail with `no OpenBSD partition` when the GPT entry's
type is not OpenBSD. That is the signal to go back to `fdisk -e sd0`, fix the
type on your entry, `write`, and re-run `installboot -v sd0`.

Do not format the ESP with `installboot -p`. On a shared disk that would take
Windows' boot files with it.

---

## 4. Base system and network

Log in as `root` on the console (xenodm is not enabled yet).

### 4.1 Network first

Ethernet (`em0`) is configured by the installer. Confirm and, if you need
wifi, install its firmware:

```sh
ifconfig em0
ping -c 3 cdn.openbsd.org

fw_update              # downloads iwm/other firmware the kernel asked for
```

Wifi, in `/etc/hostname.iwm0` (root-owned, mode 600 because it holds the
passphrase):

```
join "YourSSID" wpakey "YourPassphrase"
inet autoconf
```

Then:

```sh
chmod 600 /etc/hostname.iwm0
sh /etc/netstart iwm0
ifconfig iwm0
```

Use `join "SSID" wpakey "pass"` for WPA2/WPA3, `join "SSID" nwid "pass"` for
WEP (do not), and repeat `join` lines for multiple networks — the kernel tries
them in order. Keep the passphrase out of git; the repo ships only
`etc-hardware/hostname.iwm0.example`.

### 4.2 Patch and repositories

```sh
syspatch                  # base-system security patches; may take minutes
pkg_add -u                # no packages yet; this is a no-op
echo 'https://cdn.openbsd.org/pub/OpenBSD' > /etc/installurl
```

`fw_update` and `syspatch` are the two commands that keep an OpenBSD install
patched; both are safe to re-run and both need the network. They are not
services and do not run on a schedule by themselves (see §11.1).

### 4.3 `doas`

The installer does not create `/etc/doas.conf`, so `doas` refuses everything
until you do. As root:

```sh
printf 'permit persist :wheel\n' > /etc/doas.conf
chmod 600 /etc/doas.conf
```

This is exactly `etc/doas.conf` in the repo, so running `install.sh` later will
rewrite it identically. The repo's file is deliberately minimal; the desktop
helpers need three more rules to work from X (no terminal to type a password
into), see §7.1.

Add the extra local rules now if you want the brightness keys and the launcher's
power menu to work before you run the installer.

### 4.4 Services

```sh
rcctl enable xenodm apmd hotplugd obsdfreqd
rcctl start hotplugd obsdfreqd
rcctl ls on
```

- `xenodm` — graphical login; starts `~/.xsession` after authentication.
- `apmd` — battery/thermal policy and suspend/resume hooks.
- `hotplugd` — runs `/etc/hotplug/*`; the gaming stack uses it to hand
  `/dev/uhid*` controller devices to the desktop user.
- `obsdfreqd` — CPU frequency policy that behaves better than `apmd`'s
  default on Intel laptops (installed by the package stage).

`/etc/rc.conf.local` should end up holding `xenodm_flags=""` and friends; use
`rcctl`, not hand-edited `_flags` lines, so the two never disagree.

### 4.5 Laptop sysctls

Append to `/etc/sysctl.conf` (root-owned; read at boot):

```
machdep.lidaction=1
```

`1` suspends on lid close (`0` ignores, `2` powers down). Apply now with
`doas sysctl machdep.lidaction=1`. Check what your panel and sensors expose:

```sh
sysctl hw.sensors             # cpu0.temp0, acpibat0, acpitz0
doas wsconsctl mouse.tp       # tap/scale tunables your build exposes
doas wsconsctl display.brightness
```

Then write the ones that exist for you into `/etc/wsconsctl.conf`:

```
keyboard.map.keylayout=uk
#display.brightness=80
```

`/etc/wsconsctl.conf` is applied by `wsconsctl -f` at boot; a typo'd key makes
boot noisy but not fatal. The repo ships this file with everything commented
out, which is why the keyboard layout is a deliberate local edit, not a repo
default.

### 4.6 Time

```sh
date -u
date
```

If both are wrong by your UTC offset, the RTC is still on local time — go back
to §1.3 in Windows. OpenBSD has no supported "RTC is local time" switch; fix
the other OS.

---

## 5. Packages and dependencies

The repo does not install packages with a shell one-liner per package: it
filters `packages.txt` (because `pkg_add -l` does not understand `#` comments)
and hands the result to `pkg_add -l`. Reproduce that when installing by hand:

```sh
cd ~/openbsd-setup
grep -v '^[[:space:]]*#' packages.txt | grep -v '^[[:space:]]*$' > /tmp/pkgs
doas pkg_add -l /tmp/pkgs
doas pkg_check -q
```

Order matters only for the `st` build (§6): `gmake` must be installed first.
`pkg_add` resolves the rest itself.

### 5.1 What each group is for

| Group | Packages | Why it is here |
|---|---|---|
| Window manager | `spectrwm` | tiling WM, text bar, no config language beyond one file |
| Compositor | `picom` | shadows, frame opacity, per-window alpha; `st` has no alpha patch in 0.9.2 |
| Notifications | `dunst`, `libnotify`, `dbus` | desktop notifications with history and urgency colours |
| Launcher | `rofi`, `dmenu` | drun menu, window switcher, script modes; `dmenu` is a fallback |
| Wallpaper | `feh` | `--bg-fill`, also used by `theme-apply` |
| Clipboard | `clipmenu`, `clipnotify`, `xclip`, `xsel` | history picker plus the two CLI back ends the helpers expect |
| X automation | `xdotool`, `wmctrl`, `xbanish` | window focus/keys for `copy-url`, list windows, hide the pointer while typing |
| Lock | `slock` | `~/bin/lock`; replaced by `i3lock` in plan phase X2 |
| Screenshots | `maim`, `slop`, `scrot` | full/window/region capture to file and clipboard |
| Viewers | `nsxiv`, `chafa` | image viewer, terminal image preview (used by `lf`) |
| Night light | `redshift` | installed by the repo, **not wired**; `~/bin/nightlight` uses RandR gamma |
| Icons/theme | `adwaita-icon-theme`, `papirus-icon-theme`, `gtk+3`, `gtk+4` | rofi/dunst/zathura/GTK app consistency |
| Power | `obsdfreqd` | frequency scaling on Intel |
| Build | `gmake` | `st`'s Makefile uses `$(shell …)`, which base make lacks |
| Fonts | `noto-fonts`, `noto-emoji`, `noto-nerd-fonts`, `dejavusansmono-nerd-fonts`, `jetbrains-mono`, `terminus-nerd-fonts` | coverage for anything the vendored BlexMono lacks |
| TUIs | `neovim`, `git`, `curl`, `wget`, `aria2`, `rsync--minimal`, `jq`, `tree`, `ncdu`, `bat`, `eza`, `fd`, `ripgrep`, `fzf`, `nnn--nerd`, `ranger`, `btop`, `htop`, `newsboat`, `tig`, `unzip--iconv`, `zip`, `lf`, `zathura`, `zathura-pdf-poppler`, `poppler-utils`, `keepassxc--browser` | daily work; aliases in `~/.kshrc` point at `eza`, `bat`, `btop`, `lf` |
| Music | `mpd`, `ncmpcpp`, `mpc`, `ffmpeg`, `flac`, `opus-tools`, `mpv`, `ffmpegthumbnailer` | per-user MPD over sndio, terminal client, conversion/preview |
| Video download | `yt-dlp`, `deno` | YouTube's player needs a JS runtime; without `deno` most videos report "unavailable" |
| Fun | `cowsay`, `figlet`, `toilet`, `asciiquarium`, `cmatrix`, `sl` | optional, small |

Stem pinning: `rsync--minimal`, `nnn--nerd`, `unzip--iconv`,
`keepassxc--browser` use the empty-version form because the bare stem matches
more than one package. Do not replace those with a version number: a pinned
version breaks the next `pkg_add -u`.

Deliberately **not** installed:

- `sndiokeys` — it would adjust the mixer a second time for every XF86 volume
  key, which `~/.spectrwm.conf` already binds to `~/bin/volume`.
- `tmux`, `pkg-config`, `doas` — base system on 8.0; listing them as packages
  is a classic way to make `pkg_add` fail.
- `firefox` — the repo's browser story is Chromium with managed policy.

### 5.2 Gaming, separately

The emulator set is ~3 GiB and has its own list and its own free-space guard:

```sh
grep -v '^[[:space:]]*#' packages-gaming.txt | grep -v '^[[:space:]]*$' > /tmp/games
df -h /usr/local          # need ≥ 3 GiB free
doas pkg_add -l /tmp/games
```

It installs RetroArch, SDL2, `libhidapi`, eight libretro cores and standalone
`snes9x`, `mednafen`, `scummvm`, `dosbox-staging`. Cores land in
`/usr/local/lib/libretro`, which is where `~/bin/games` looks.

### 5.3 Fonts from the repo

```sh
mkdir -p ~/.fonts
install -m 644 ~/openbsd-setup/share/fonts/*.ttf ~/.fonts/
install -m 644 ~/openbsd-setup/share/fonts/OFL-BlexMono.txt ~/.fonts/
fc-cache -f
fc-list | grep -i blex        # must list BlexMono Nerd Font
```

The repo installs the font to `~/.fonts` rather than system-wide so the
installer can do it without root and it follows the user, not the machine.

---

## 6. Build `st` (the terminal)

`st` is not packaged in the version the theme needs, and its palette is
compile-time. The repo pins 0.9.2, three patches and a SHA256.

```sh
doas sh ~/openbsd-setup/share/st/build.sh
```

What the script does, and why each step exists:

1. Fetches `st-0.9.2.tar.gz` from `dl.suckless.org` and checks it against
   `share/st/SHA256`. A mismatch is fatal, not a warning.
2. Installs the repo's `config.h` — BlexMono at pixelsize 18, amber palette,
   `st-256color`, scrollback settings.
3. Applies `st-scrollback-0.9.2.diff`, `st-scrollback-mouse-0.9.2.diff`,
   `st-clipboard-0.8.3.diff` with `patch -p1 -F3`. The alpha patch is **not**
   applied: it does not apply to 0.9.2, which is why transparency is picom's
   job.
4. Builds with `gmake CC=cc` and explicit
   `INCS=-I/usr/X11R6/include -I/usr/X11R6/include/freetype2` and
   `LIBS=-lX11 -lutil -lXft -lfontconfig -lfreetype`. OpenBSD 8.0 has no `c99`
   and xenocara ships freetype/fontconfig without `.pc` files, so pkg-config
   cannot find them.
5. `gmake install PREFIX=/usr/local`, then checks `st-256color` exists in
   terminfo.

Verify:

```sh
st -v                     # st-0.9.2
infocmp st-256color >/dev/null && echo terminfo ok
```

`TERM=st-256color` is exported in `~/.profile`. If a remote host complains
about an unknown terminal, copy the terminfo entry there
(`infocmp -x st-256color > st.terminfo` and `tic` on the target).

To build only, or to test patches without installing:
`sh share/st/build.sh --check` (as the user, no root).

---

## 7. Configure `/etc`

The repo's `etc/` is a portable overlay, `etc-hardware/` is T480s-only, and
`etc-vm/` is for the rehearsal VM. On metal, `install.sh` extracts `etc/` then
`etc-hardware/` over `/`, then fixes ownership and modes. By hand, the same
result is:

```sh
cd ~/openbsd-setup
doas tar -C . -cf - etc | doas tar -C / -xpf -
doas tar -C etc-hardware -cf - . | doas tar -C /etc -xpf -
doas find /etc -user "$USER" -exec chown root:wheel {} +
doas chmod 600 /etc/doas.conf /etc/ssh/sshd_config
```

Then walk the files one at a time; each is small and each exists for a reason.

### 7.1 `/etc/doas.conf`

Shipped:

```
permit persist :wheel
```

`persist` keeps the authorisation for five minutes, so repeated `doas` calls in
one session prompt once (the VM's `vm apply` relies on this).

The brightness keys call `doas /sbin/wsconsctl`, and the launcher's power menu
calls `doas /usr/sbin/zzz`, `doas /sbin/reboot` and
`doas /sbin/shutdown -p now`. From X there is no terminal for a password
prompt, so those fail with the shipped file alone. Add the three rules
locally — they are not in the repo because they widen what any `wheel` process
can do without a password:

```
permit persist :wheel
permit nopass :wheel cmd /sbin/wsconsctl
permit nopass :wheel cmd /usr/sbin/zzz
permit nopass :wheel cmd /sbin/reboot
permit nopass :wheel cmd /sbin/shutdown
```

`cmd` matches the command path, so the `shutdown` rule covers `-p now` and
`-r now` alike. That is not an escalation: `wheel` already has `permit
persist`, and root can shut the machine down anyway. Validate with
`doas -C /etc/doas.conf`, which prints the rule a given command would match.

### 7.2 `/etc/pf.conf`

Shipped:

```
set skip on lo

block return
pass
```

Stateful outbound, no unsolicited inbound, loopback skipped. It is deliberately
not a "laptop firewall with rules for every service"; the default policy is
closed, and nothing in the desktop listens on the network except `sshd` (which
is limited by its own config). Enable it:

```sh
doas pfctl -nf /etc/pf.conf && doas pfctl -f /etc/pf.conf
doas rcctl enable pf        # if pf isn't already on
```

### 7.3 `/etc/ssh/sshd_config.d/10-local.conf`

```
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
AllowUsers peter
```

This is a drop-in, included by `Include /etc/ssh/sshd_config.d/*.conf`. The repo
appends that `Include` line if it is absent, because OpenBSD's stock
`sshd_config` does not have it.

**Order of operations matters**: `PasswordAuthentication no` means you must
already have a key in `~/.ssh/authorized_keys` and `AllowUsers peter` means any
other account loses SSH. Do it while you still have console access:

```sh
# as peter, with your key ready
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cat >> ~/.ssh/authorized_keys      # paste, then Ctrl-D
chmod 600 ~/.ssh ~/.ssh/authorized_keys
doas sshd -t && doas rcctl reload sshd
```

Test in a second session before closing the first. `sshd -t` catches syntax,
not policy mistakes.

### 7.4 `/etc/X11/xenodm/Xsetup_0`

The stock file starts `xconsole`, which on a tiling desktop occupies the main
tile and cannot be killed from the user session (xenodm owns it as root/_x11).
The repo's version omits it and paints a neutral root window:

```sh
#!/bin/sh
prefix="/usr/X11R6"
${prefix}/bin/xsetroot -fg \#6f6f6f -bg \#bfbfbf \
	-bitmap ${prefix}/include/X11/bitmaps/root_weave
if test -x /usr/local/bin/openbsd-wallpaper; then
	/usr/local/bin/openbsd-wallpaper
fi
```

`~/.xsession` replaces the root image with the amber wallpaper a moment later,
so this only matters for the login screen. Plan phase X2 makes this screen
part of the theme; see §10.2.

### 7.5 `/etc/chromium/policies/managed/amber.json`

```json
{
  "ExtensionInstallForcelist": [
    "ddkjiahejlhfcafbddmgiahcphecmpfh;https://clients2.google.com/service/update2/crx"
  ],
  "AdsSettingForIntrusiveAdsSites": 2,
  "RestoreOnStartup": 1,
  "BookmarksBarEnabled": false,
  "DefaultBrowserSettingEnabled": false,
  "MetricsReportingEnabled": false,
  "BackgroundModeEnabled": false,
  "PromotionalTabsEnabled": false,
  "SyncDisabled": true,
  "AutofillCreditCardEnabled": false
}
```

Chromium on OpenBSD is pledged and unveiled, so a dotfile cannot load an
unpacked extension. Managed policy is the supported route, and
`/etc/chromium/unveil.main` already exposes `/etc/chromium` read-only. The
extension is **uBlock Origin Lite** because Chromium 156 removed Manifest V2
and classic uBlock Origin can no longer load. The stage pre-warms the profile
headless so the first real window already blocks ads; by hand:

```sh
mkdir -p ~/.config/chromium ~/.cache/chromium-runtime
chmod 700 ~/.cache/chromium-runtime
XDG_RUNTIME_DIR=~/.cache/chromium-runtime \
  chrome --headless=new --disable-gpu --no-first-run \
  --user-data-dir=~/.config/chromium about:blank &
sleep 30; pkill -f 'headless=new'
ls ~/.config/chromium/Default/Extensions/ddkjiahejlhfcafbddmgiahcphecmpfh
```

Then `chrome://policy` in the browser shows the active keys and
`chrome://extensions` shows the pinned extension. Two policy files setting the
same key are merged, not overridden; check for leftovers if a setting will not
stick.

### 7.6 `/etc/apm/suspend`

```sh
#!/bin/sh
pkill -USR1 xidle 2>/dev/null || true
```

Locks the screen before the machine sleeps. It must be executable
(`chmod 755`); apmd runs it as root, and `xidle` is the user's process, so the
signal only lands if the helper is running. `~/.xsession` starts `xidle` with
a 300 s timeout and `~/bin/lock` as the program.

### 7.7 Network files, and the ones that stay machine-local

| File | Content | Tracked? |
|---|---|---|
| `/etc/hostname.em0` | `inet autoconf` | yes (`etc-hardware/`) |
| `/etc/hostname.iwm0` | `join "SSID" wpakey "…"` + `inet autoconf` | **no** — secret; example only |
| `/etc/myname` | hostname | no — installer writes it |
| `/etc/mygate` | absent with DHCP | no |
| `/etc/resolv.conf` | DHCP-written | no |
| `/etc/fstab` | DUIDs from this install | **never** |
| `/etc/installurl` | mirror URL | yes |
| `/etc/wsconsctl.conf` | keyboard/display | yes (commented examples) |
| `/etc/sysctl.conf` | `machdep.lidaction=1` | no — add locally |

### 7.8 `/etc/ttys`

Leave the stock `ttyC1`–`ttyC6` console gettys alone: they are the recovery path
when X or xenodm breaks. xenodm owns `ttyC4` (`xenodm` in `/etc/ttys`), which is
why `Ctrl+Alt+F2` still gives a text login. `install.sh --vm` adds a serial
getty; metal does not need one.

---

## 8. The desktop (`home/`)

The repo's `home/` is a complete dotfile tree. Copy it, then fix modes and
ownership — the installer does exactly this, plus two sed rewrites:

```sh
cd ~/openbsd-setup
tar -C home -cf - . | tar -C "$HOME" -xpf -
chown -R "$USER:$USER" "$HOME"
chmod 755 "$HOME"/bin/* "$HOME/.xsession" "$HOME/.xinitrc"
chmod 755 "$HOME/.config/spectrwm/bar.sh" "$HOME/.config/lf/open" \
          "$HOME/.config/lf/preview"
```

Then do the two rewrites by hand, because both matter:

```sh
# spectrwm does not expand $HOME in bar_action or program[] paths
sed 's|[$]HOME|'"$HOME"'|g' ~/.spectrwm.conf > ~/.spectrwm.conf.new &&
  mv ~/.spectrwm.conf.new ~/.spectrwm.conf

# rofi must point at the amber palette, not a leftover theme name
sed 's|^@theme .*|@theme "amber"|' ~/.config/rofi/config.rasi > ~/.config/rofi/config.rasi.new &&
  mv ~/.config/rofi/config.rasi.new ~/.config/rofi/config.rasi

mkdir -p ~/Music ~/Videos/Downloads ~/Pictures/Screenshots ~/Games \
  ~/.local/share/mpd/playlists ~/.local/share/ncmpcpp ~/.local/share/lyrics \
  ~/.cache/lf ~/.config/zathura
printf 'amber\n' > ~/.cache/theme
```

### 8.1 `~/.xsession` — session order

xenodm runs this after login. The order is the design:

1. **`dbus-run-session` re-exec** — a private session bus for dunst/libnotify;
   a no-op if dbus is missing. Without it, some notifications fail silently.
2. **PATH** with `~/bin` first, so the bindings call the repo's helpers.
3. **clipmenu environment** — `CM_LAUNCHER=rofi`, `CM_SELECTIONS=clipboard`,
   100 entries, cache in `~/.cache/clipmenu`.
4. **X resources / DPMS / bell** — `xrdb -merge ~/.Xresources`, `xset s off`,
   `xset +dpms`, `xset dpms 600 900 1200`, `xset b off`. On the VM's `wsfb`
   DPMS is absent; on the T480s' intel driver it works.
5. **Touchscreen mapping** — maps any `touch`/`wacom` device to the primary
   RandR output. Harmless on a T480s without a touch panel.
6. **Wallpaper** — `feh --bg-fill` from `~/.cache/theme`, falling back to
   `xsetroot -solid "#0f0e0c"`.
7. **Helpers** — `picom`, `dunst`, `clipmenud`, `xbanish`, per-user `mpd`
   (only if `mpc ping` fails), `xidle -no -timeout 300 -program ~/bin/lock`.
8. **`exec spectrwm`** — the WM is last and replaces the shell, so logging out
   of spectrwm ends the X session and returns to xenodm.

`~/.xinitrc` is one line, `exec "$HOME/.xsession"`, so `startx` from a text
console gives the same session.

Debug a broken session with `~/.xsession-errors` and by running components
manually after a `startx` that drops to an `xterm`-less screen — switch to
`ttyC2`, log in, and run `DISPLAY=:0 st` to get a terminal.

### 8.2 `~/.spectrwm.conf`

The file is the window manager *and* the keybinding table. Sections:

| Section | What it sets |
|---|---|
| core | `modkey = Mod4`, 10 workspaces, focus-follows-mouse off (`focus_mode = default`), `warp_focus = 1` |
| decoration | `border_width = 2`, `tile_gap = 8`, `region_padding = 8`, `layout_order` |
| programs | every helper, so bindings stay one-liners |
| `spawn_flags[.*] += optional` | a missing helper never replaces the bar with a validation error |
| bindings | see the table below |
| bar | `bar_action = …/bar.sh`, `bar_format = +|L +@fg=2;+L+@fg=1; +|C +48W +|R +A`, 10 workspaces, list-all indicators |
| quirks | dialogs float anywhere, Gimp/mpv/feh/lxappearance float, zathura floats |
| theme block | between `>>> theme colors >>>` and `<<< theme colors <<<`; `theme-apply` owns it |

Three gotchas encoded in the file:

- spectrwm cuts a line at an unescaped `#`, so colours are `rgb:rr/gg/bb`, never
  `#rrggbb`.
- `quirk[...]` ends at the first `]`; a bracket expression like `[Zz]athura` is
  a parse error that spectrwm paints into the bar. Use `.*athura.*`.
- `$HOME` is not expanded in `bar_action` or `program[]`, hence the sed above.

### 8.3 Bindings

| Keys | Action |
|---|---|
| `Super+Return` | `st` |
| `Super+D` | rofi drun (applications) |
| `Super+Space` | `~/bin/launcher` (command centre) |
| `Super+Tab` | rofi window switcher |
| `Super+E` | `~/bin/files` (lf) |
| `Super+Shift+B` | `~/bin/browser` |
| `Super+Shift+M` | `~/bin/music` (mpd + ncmpcpp) |
| `Super+Shift+G` | `~/bin/games` (RetroArch menu) |
| `Super+Shift+D` | `~/bin/video-download` |
| `Super+Shift+C` | `~/bin/copy-url` |
| `Super+Q` / `Super+Shift+Q` | close / kill window |
| `Super+F` / `Super+Shift+F` | fullscreen / float toggle |
| `Super+M` / `Super+Shift+M` | maximize / focus main |
| `Super+J` / `Super+K` | focus next / previous |
| `Super+1..0` | workspace 1–10 |
| `Super+Shift+1..0` | move window to workspace |
| `Super+Shift+Space` | cycle layout |
| `Super+Control+Space` | reset stack |
| `Super+B` | toggle bar |
| `Super+Control+R` | reload config |
| `Super+Escape` | lock |
| `Super+S` / `Super+Shift+S` / `Super+Control+S` | screenshot full / window / region |
| `Super+Shift+/` | keybinding cheat sheet (`~/bin/keybinds`) |
| `Super+Shift+E` | quit spectrwm → xenodm |
| `XF86Audio*`, `XF86MonBrightness*` | volume, mute, brightness |

`~/bin/keybinds` reads the live config, so the cheat sheet never drifts from
what is actually bound.

### 8.4 The bar: `~/.config/spectrwm/bar.sh`

spectrwm starts it once and displays every line it prints; `bar_action_expand
= 1` makes the `+@fg=n;` markup work. It ticks every 2 s and refreshes the slow
segments every 20 s:

| Segment | Source | Rule |
|---|---|---|
| network | `ifconfig iwm0` SSID, else `em0`/`vio0`/`re0` active | shows `offline` when nothing is up |
| battery | `apm -l`, `apm -a` | hidden when `apm -a` returns 255 (no battery) |
| temperature | `sysctl -n hw.sensors.cpu0.temp0` | red at ≥ 85 °C |
| volume | `sndioctl output.level/output.mute` | `vol muted` in red |
| music | `mpc current` and `mpc status` | trimmed to 40 chars, ▶/⏸ |
| clock | `date '+%a %d %b  %H:%M'` | every tick |

Two things to preserve if you edit it: escape `+` in dynamic text as `++`
(SSIDs and track titles), and keep it cheap — a `sysctl` fork every 2 s is
fine, a `pkg_info` is not.

### 8.5 `picom.conf`

XRender backend, vsync on, 10 px shadows at 35% opacity, active 1.0 / inactive
0.94 / frame 0.96, `st` at 96% and Chromium opaque, blur off, and
`focus-exclude` for `slock` and `dunst`. The comment in the file explains the
choice: the UHD 620 is fine with GLX too, but XRender is the safe backend on
OpenBSD's intel driver, and `st` has no alpha of its own.

Plan phase X1 upgrades this to rounded corners, real blur and animations — see
§10.1. Keep this file as the fallback: if the fan spins up, you are one
`cp` away from the cheap compositor.

### 8.6 dunst, rofi, GTK, Xresources

- **dunst** — 340 px wide, top-right, offset `(14, 44)` to clear the 30 px bar,
  6 notifications, progress bar, 1 px frame, BlexMono 10, history 20,
  `rofi -dmenu` as its dmenu, urgency palettes `#17140f`/`#0f0e0c` with amber
  and red frames. `dunstctl history` is the notification centre.
- **rofi** — `config.rasi` holds behaviour (`drun,run,window`, Papirus-Dark
  icons, `st` as terminal, fzf sorting) and one line, `@theme "amber"`.
  `themes/amber.rasi` is the palette: 44% width, amber border, 10 lines,
  selected row inverted to amber-on-black.
- **GTK 3/4** — Adwaita-dark, Papirus-Dark icons, BlexMono 11/10, Adwaita
  cursor at 24 px, `gtk-decoration-layout=menu:`. This is what keeps
  zathura/keepassxc/lxappearance from looking like a different desktop.
- **`~/.Xresources`** — `Xft.dpi: 120`. The panel is 1920×1080 across 14
  inches (~157 dpi), so 96 dpi text is too small and full GTK scaling is too
  blunt. 120 is the compromise. Also sets cursor theme/size and classic X
  client colours.

### 8.7 Music, PDFs, files

- **mpd** — per-user, not a system service. `~/.config/mpd/mpd.conf` uses
  `sndio` output, `mixer_type "software"`, music in `~/Music`, state under
  `~/.local/share/mpd`. `~/bin/music` starts it if `mpc ping` fails, then
  `st -e ncmpcpp`.
- **ncmpcpp** — alternative UI, spectrum visualizer, ANSI colour names so it
  inherits `st`'s palette.
- **zathura** — `zathurarc` with the amber palette, quoted colours (`#` starts
  a comment), 100 px scroll step, `guioptions ""` for a clean page.
- **lf** — `lfrc` sets `drawbox`, icons, `ratios 1:2:3`, previews via
  `~/.config/lf/preview` (chafa/images/PDF text), and opens with
  `~/.config/lf/open`: mg for text, feh for images, zathura for PDFs,
  `xdg-open` for the rest. `~/bin/files` resumes the last directory from
  `~/.cache/lf/lastdir`.

### 8.8 The theme system

`~/.config/spectrwm/themes/<name>/` is a theme. `~/bin/theme-apply <name>`:

1. splices `spectrwm.colors` between the two markers in `~/.spectrwm.conf`;
2. installs `rofi.rasi` → `~/.config/rofi/themes/<name>.rasi` and rewrites
   `@theme` in `config.rasi`;
3. installs `dunstrc`, `Xresources`, `lf.colors`, `zathurarc`;
4. copies `wallpaper.png` → `~/Pictures/wallpapers/<name>.png` and remembers
   the name in `~/.cache/theme`;
5. if `DISPLAY` is set: `xrdb -merge`, `dunstctl reload` (or restart dunst),
   repaint the wallpaper, and `Super+Control+R` to make spectrwm re-read its
   config.

`st`'s palette is compile-time in `share/st/config.h`, so **open terminals do
not repaint** on a theme switch. That is deliberate: rebuilding `st` to change
a colour is worse than a restart.

Adding a theme means creating that directory with the six files (copy `amber`
and edit the palette) — `theme-apply` will fail loudly on a missing directory
and quietly skip a missing file.

Do not run `theme-apply` as root: it writes only under `$HOME`, and a root-owned
`~/.config` will break the next login.

### 8.9 Wallpapers

`home/Pictures/wallpapers/amber.png` and
`home/.config/spectrwm/themes/amber/wallpaper.png` are the same image in two
places: one for the session, one for `theme-apply`. Keep them in sync when you
replace the image, or a theme switch will revert your wallpaper.

---

## 9. Browser, downloads, gaming

### 9.1 Chromium

`BROWSER="$HOME/bin/browser"` and `TERMINAL=st` are exported in `~/.profile`.
The launcher is `chrome` (`/usr/local/bin/chrome`); `chromium` is only the
package name. `~/bin/browser` adds `--no-first-run`, the only way to skip the
"Additional Terms of Service" dialog, which no policy covers.

Three flows, all bound in spectrwm:

- `Super+Shift+B` — Chromium.
- `Super+Shift+D` — `~/bin/video-download`: takes the focused tab's URL,
  runs `yt-dlp` in an `st` window, best video ≤ 1080p muxed to mp4 in
  `~/Videos/Downloads`.
- `Super+Shift+C` — `~/bin/copy-url`: focuses Chromium, `Ctrl+L`, `Ctrl+C`,
  reads the clipboard, restores what was there.

`video-download` reads the clipboard first (`Ctrl+L`, `Ctrl+C` in the browser
is the route that always works) and only falls back to driving the browser with
`xdotool`. A pledged, unveiled browser cannot be asked which page it is on, and
synthetic keys are not delivered by every X server — the VM's `wsfb` delivered
none, so `copy-url` is metal-only until proven.

### 9.2 RetroArch

`~/bin/games` lists system folders under `~/Games/roms/<system>/` (and still
accepts the older `~/Games/<system>/roms/` layout), picks a ROM and runs it with
the matching core from `/usr/local/lib/libretro`. Layout:

```
~/Games/
  roms/snes/*.sfc
  roms/nes/*.nes
  roms/gba/*.gba
  roms/psx/*.cue + *.bin
  bios/
```

Controllers are `/dev/uhid*`, which the repo's `/etc/hotplug/attach` (run by
`hotplugd`) re-owns for the console user as they are plugged in; RetroArch uses
SDL2 with `input_autodetect_enable = "true"` (see
`~/.config/retroarch/retroarch.cfg`), so a wired Xbox One/Series pad should be
detected automatically. `RetroArch` in the menu opens the emulator's own
interface. Verify pad mapping and per-title settings on real hardware.

---

## 10. Apply the X11 plan (Tier 1 → Tier 2)

The repo implements the plan's **Tier 0**: spectrwm, st, rofi, dunst, picom,
feh, clipmenu, amber palette. Tier 1 and Tier 2 are **plan only** — the
following is the manual work from
[`x11-ml4w-plan.md`](x11-ml4w-plan.md), in its phase order. Rehearse every
config in the VM or under `Xephyr :1` before it touches the laptop, because the
VM cannot show GPU effects but can show syntax, layout and colour.

```sh
Xephyr :1 -screen 1280x800 &
DISPLAY=:1 i3 -c ~/.config/i3/config &
DISPLAY=:1 polybar -c ~/.config/polybar/config.ini main &
DISPLAY=:1 rofi -show drun &
DISPLAY=:1 xwd -root | convert xwd:- /tmp/shot.png
```

### 10.1 X1 — picom 13, rounded, blurred, tear-free (one evening)

Install/confirm picom 13 (`picom` is already in `packages.txt`) and replace the
compositor config. This is the largest visual gain per hour in either plan.

`~/.config/picom/picom.conf`:

```
backend = "glx";
vsync = true;
use-damage = true;

corner-radius = 10;
rounded-corners-exclude = [
  "window_type = 'dock'",
  "window_type = 'desktop'",
  "class_g = 'Polybar'",
  "fullscreen"
];

shadow = true;
shadow-radius = 10;
shadow-opacity = 0.35;
shadow-offset-x = -8;
shadow-offset-y = -8;

fade = true;
fade-in-step = 0.06;
fade-out-step = 0.06;

blur-background = true;
blur-background-frame = true;
blur-method = "dual_kawase";
blur-strength = 5;
blur-background-exclude = [
  "window_type = 'desktop'",
  "class_g = 'slock'",
  "class_g = 'i3lock'"
];

frame-opacity = 0.96;
inactive-opacity = 0.94;
active-opacity = 1.0;
opacity-rule = [ "96:class_g = 'st'", "100:class_g = 'Chromium'" ];

focus-exclude = [ "class_g = 'slock'", "class_g = 'i3lock'", "class_g = 'dunst'" ];
```

If picom 13 rejects a key it prints the line and exits — read the log rather
than assuming it applied. `animations = true` exists in 12+, but it needs
`animation-stiffness`/`animation-dampening` tuning and is the first thing to
drop if the fan spins.

Tear-free presentation, `/etc/X11/xorg.conf.d/20-intel.conf`:

```
Section "Device"
    Identifier "Intel Graphics"
    Driver     "intel"
    Option     "TearFree" "true"
EndSection
```

`/etc/X11/xorg.conf.d/` does not exist by default; create it. Verify in
`/var/log/Xorg.0.log` (`TearFree` should appear in the intel driver's option
dump) and by scrolling a long page in Chromium.

**Done when:** st, rofi and dunst are rounded and blurred, idle CPU is under
5% (`top`), and scrolling in Chromium does not tear.

### 10.2 X2 — themed xenodm, real lock screen (one evening)

**Login.** `/etc/X11/xenodm/Xresources` (root-owned):

```
xlogin.Login.foreground: #e6ded0
xlogin.Login.background: #0f0e0c
xlogin.Login.face: BlexMono Nerd Font-14
xlogin.Login.greeting: OpenBSD
xlogin.Login.namePrompt: \040login:
xlogin.Login.passwdPrompt: \040password:
xlogin.Login.fail: \040login incorrect
xlogin.Login.failDelay: 2000
xlogin.Login.echoPasswd: true
```

`xlogin.Login.face` needs an Xft-enabled xenodm; if the font does not change,
your `Xresources` is not being read — xenodm reads it from its own directory,
not `~/.Xresources`. Then paint the same wallpaper the session uses, by copying
the image somewhere root can read and extending `Xsetup_0`:

```sh
doas mkdir -p /usr/local/share/backgrounds
doas install -m 644 ~/Pictures/wallpapers/amber.png \
  /usr/local/share/backgrounds/amber.png
```

```
# in /etc/X11/xenodm/Xsetup_0, after the xsetroot line
if test -x /usr/local/bin/feh; then
	/usr/local/bin/feh --no-fehbg --bg-fill /usr/local/share/backgrounds/amber.png
fi
```**Lock.** Pre-render a blurred copy. This needs ImageMagick's `convert`,
which is not in `packages.txt`: `doas pkg_add ImageMagick`.

```sh
install -d ~/.cache
convert ~/Pictures/wallpapers/amber.png -blur 0x6 ~/.cache/amber-blur.png
```

`i3lock` is in the plan's inventory but **not** in `packages.txt` yet; install
it (`doas pkg_add i3lock`) and point the helper at it:

`~/bin/lock`:

```sh
#!/bin/sh
exec /usr/local/bin/i3lock -n -i "$HOME/.cache/amber-blur.png"
```

`-n` avoids forking after the password is accepted. Keep `slock` installed as
the fallback (`slock` still works if i3lock breaks on a driver update).

The plan's `xss-lock` pairing is optional: the repo's existing `xidle` already
locks after 300 s and already answers `SIGUSR1` from `/etc/apm/suspend`, so
swapping the lock binary is enough. If you do adopt `xss-lock`, replace the
`xidle` line in `~/.xsession` with `xss-lock -- i3lock -n -i
"$HOME/.cache/amber-blur.png" &` and change `/etc/apm/suspend` to
`pkill -USR1 xss-lock`; verify on resume before you trust it.

**Done when:** the login screen and the lock screen both use the desktop
palette and the wallpaper; `Super+Escape` and lid-close both lock.

### 10.3 X3 — i3 (two sessions)

```sh
doas pkg_add i3
```

Keep spectrwm as the fallback: both configs stay in the repo, and
`~/.xsession` chooses. The simplest switch is a one-line file the session
reads:

```sh
# ~/.xsession — replace the final `exec spectrwm` with:
exec "$HOME/bin/session"
```

```sh
# ~/bin/session
#!/bin/sh
[ -f "$HOME/.session-wm" ] && wm=$(cat "$HOME/.session-wm") || wm=spectrwm
case $wm in
i3) exec i3 ;;
*)  exec spectrwm ;;
esac
```

`~/.config/i3/config` — the plan's binding contract, gaps, and no bar (polybar
comes next):

```
set $mod Mod4
font pango:BlexMono Nerd Font 10

# gaps and borders
gaps inner 8
gaps outer 8
smart_gaps on
smart_borders on
default_border pixel 2
default_floating_border pixel 2

client.focused          #ffb000 #ffb000 #0f0e0c #ffb000 #ffb000
client.unfocused        #17140f #17140f #e6ded0 #2a241b #2a241b
client.urgent           #d90d10 #d90d10 #e6ded0 #d90d10 #d90d10

floating_modifier $mod

# applications
bindsym $mod+Return       exec st
bindsym $mod+d            exec rofi -show drun -show-icons
bindsym $mod+space        exec $HOME/bin/launcher
bindsym $mod+Tab          exec rofi -show window -show-icons
bindsym $mod+e            exec $HOME/bin/files
bindsym $mod+Shift+b      exec $HOME/bin/browser
bindsym $mod+Shift+m      exec $HOME/bin/music
bindsym $mod+Shift+g      exec $HOME/bin/games
bindsym $mod+Shift+d      exec $HOME/bin/video-download
bindsym $mod+Shift+c      exec $HOME/bin/copy-url
bindsym $mod+Shift+slash  exec $HOME/bin/keybinds

# windows
bindsym $mod+q            kill
bindsym $mod+Shift+q      exec xkill
bindsym $mod+f            fullscreen toggle
bindsym $mod+Shift+f      floating toggle
bindsym $mod+Shift+space  layout toggle split
bindsym $mod+w            layout tabbed
bindsym $mod+s            layout stacking
bindsym $mod+m            layout toggle split
bindsym $mod+j            focus next
bindsym $mod+k            focus prev
bindsym $mod+minus        scratchpad show
bindsym $mod+Shift+minus  move scratchpad

# workspaces 1-10
bindsym $mod+1 workspace number 1
bindsym $mod+2 workspace number 2
bindsym $mod+3 workspace number 3
bindsym $mod+4 workspace number 4
bindsym $mod+5 workspace number 5
bindsym $mod+6 workspace number 6
bindsym $mod+7 workspace number 7
bindsym $mod+8 workspace number 8
bindsym $mod+9 workspace number 9
bindsym $mod+0 workspace number 10
bindsym $mod+Shift+1 move container to workspace number 1
bindsym $mod+Shift+2 move container to workspace number 2
bindsym $mod+Shift+3 move container to workspace number 3
bindsym $mod+Shift+4 move container to workspace number 4
bindsym $mod+Shift+5 move container to workspace number 5
bindsym $mod+Shift+6 move container to workspace number 6
bindsym $mod+Shift+7 move container to workspace number 7
bindsym $mod+Shift+8 move container to workspace number 8
bindsym $mod+Shift+9 move container to workspace number 9
bindsym $mod+Shift+0 move container to workspace number 10

# session
bindsym $mod+Escape       exec $HOME/bin/lock
bindsym $mod+Shift+e      exec i3-msg exit
bindsym $mod+Shift+r      restart
bindsym $mod+Control+r    reload

# media and hardware keys
bindsym XF86AudioRaiseVolume  exec $HOME/bin/volume up
bindsym XF86AudioLowerVolume  exec $HOME/bin/volume down
bindsym XF86AudioMute         exec $HOME/bin/volume mute
bindsym XF86MonBrightnessUp   exec $HOME/bin/brightness up
bindsym XF86MonBrightnessDown exec $HOME/bin/brightness down

# floating rules
for_window [class=".*athura.*"] floating enable
for_window [class="mpv"] floating enable
for_window [window_role="pop-up"] floating enable

bar { mode invisible }

exec_always --no-startup-id picom --config $HOME/.config/picom/picom.conf
exec --no-startup-id dunst
exec --no-startup-id clipmenud
exec --no-startup-id xbanish
exec --no-startup-id feh --no-fehbg --bg-fill $HOME/Pictures/wallpapers/amber.png
exec --no-startup-id xidle -no -timeout 300 -program $HOME/bin/lock
```

Validate before switching: `i3 -C -c ~/.config/i3/config` prints errors and
exits non-zero on a bad config. `$mod+Shift+q` runs `xkill` from xenocara:
click a window to destroy that client. Drop the binding if you would rather
only ever close windows politely (`$mod+q`).

**Done when:** a full working day on i3 needs no terminal for window
management, and `~/.session-wm` containing `spectrwm` still gives the old
session back.

### 10.4 X4 — polybar and rofi modes (two sessions)

`doas pkg_add polybar`. `~/.config/polybar/config.ini`, bar height 34, amber
on `#0f0e0c`, BlexMono 10, `wm-restack = i3`:

```
[bar/main]
monitor = ${env:MONITOR:}
width = 100%
height = 34
offset-x = 0
offset-y = 0
background = #0f0e0c
foreground = #e6ded0
radius = 0
padding-left = 1
padding-right = 1
module-margin = 1
font-0 = BlexMono Nerd Font:size=10;2
modules-left = i3
modules-center = xwindow
modules-right = quicklinks cpu memory temp battery network volume tray date
tray-position = right
tray-padding = 2
wm-restack = i3

[module/i3]
type = internal/i3
format = <label-state> <label-mode>
index-sort = true
wrapping-scroll = false
label-focused = %index%
label-focused-background = #ffb000
label-focused-foreground = #0f0e0c
label-focused-padding = 1
label-occupied = %index%
label-occupied-foreground = #8a8175
label-empty = %index%
label-empty-foreground = #5c554a
label-urgent = %index%
label-urgent-background = #d90d10
label-separator = " "

[module/xwindow]
type = internal/xwindow
label = %title:0:60:...%
label-foreground = #8a8175

[module/cpu]
type = internal/cpu
interval = 2
format = cpu %percentage:2%%
label-foreground = #8a8175

[module/memory]
type = internal/memory
interval = 5
format = mem %percentage_used%%
label-foreground = #8a8175

[module/temp]
type = custom/script
exec = ~/.config/polybar/scripts/temp.sh
interval = 20
label-foreground = #8a8175

[module/battery]
type = custom/script
exec = ~/.config/polybar/scripts/battery.sh
interval = 30
label-foreground = #8a8175

[module/network]
type = custom/script
exec = ~/.config/polybar/scripts/network.sh
interval = 10
label-foreground = #8a8175

[module/volume]
type = custom/script
exec = ~/.config/polybar/scripts/volume.sh
interval = 2
label-foreground = #8a8175

[module/quicklinks]
type = custom/script
exec = echo "%{A1:$HOME/bin/browser &:} web %{A} %{A1:$HOME/bin/launcher &:} menu %{A}"
interval = false

[module/date]
type = internal/date
interval = 10
date = %a %d %b
time = %H:%M
format = <label>
label = %date%  %time%
label-foreground = #ffb000
```

The five status scripts are `bar.sh`'s segment functions with polybar markup
instead of `+@fg=n;`. The mapping, and why each exists:

| Script | Reads | Replaces the module that fails on OpenBSD |
|---|---|---|
| `battery.sh` | `apm -l`, `apm -a` | `internal/battery` (`/sys/class/power_supply`) |
| `network.sh` | `ifconfig iwm0` nwid, else `em0`/`vio0` active | `internal/network` (netlink) |
| `temp.sh` | `sysctl -n hw.sensors.cpu0.temp0` | `internal/temperature` (`/sys/class/hwmon`) |
| `volume.sh` | `sndioctl -n output.level`, `output.mute` | `internal/pulseaudio`/`internal/alsa` |
| `music.sh` | `mpc current`, `mpc status` | `internal/mpd` works, but one script keeps the look consistent |

One complete example, `~/.config/polybar/scripts/temp.sh`:

```sh
#!/bin/sh
t=$(sysctl -n hw.sensors.cpu0.temp0 2>/dev/null) || exit 0
t=${t%%.*}
case $t in ''|*[!0-9]*) exit 0 ;; esac
if [ "$t" -ge 85 ]; then
	printf '%%{F#d90d10}%s°C%%{F-}' "$t"
else
	printf '%s°C' "$t"
fi
```

Use `%{F#ffb000}…%{F-}` for amber, `%{F#d90d10}…%{F-}` for red, and `chmod
755` all five. `internal/i3`, `internal/xwindow`, `internal/tray`,
`internal/cpu`, `internal/memory` and `internal/date` are compiled into the
OpenBSD package and work; the Linux-interface modules listed above do not, so
do not enable them "to see".

Make `theme-apply` repaint the bar by rendering `polybar.ini.in` from the
palette — that is the plan's phase X4 requirement and the only way switching
themes stays one command.

Rofi script modes (the ML4W "sidebar" substitute): one script dispatching
subcommands, and one `-modi` line in `~/.config/rofi/config.rasi`:

```
modi: "drun,run,window,theme:~/.config/rofi/scripts/menu.sh theme,display:~/.config/rofi/scripts/menu.sh display,audio:~/.config/rofi/scripts/menu.sh audio,wifi:~/.config/rofi/scripts/menu.sh wifi,power:~/.config/rofi/scripts/menu.sh power,keys:~/.config/rofi/scripts/menu.sh keys";
```

rasi has no line continuation: the `modi` value must stay on one line, or rofi
reports a parse error and falls back to its defaults.

`menu.sh` prints one choice per line for rofi and performs the action on the
selected line: `theme` lists `~/.config/spectrwm/themes/*/`, `display` wraps
`xrandr`/`arandr`, `audio` wraps `sndioctl` sinks and mute, `wifi` wraps
`ifconfig iwm0 join`, `power` wraps lock/suspend/reboot/off/logout, `keys`
runs `~/bin/keybinds`. Keep each action a single command so the script stays
readable and fails loudly.

**Done when:** the bar carries workspace pills, focused window, quicklinks,
five live status modules, tray and clock; `theme-apply` repaints bar and
launcher; no module shows a Linux-path error.

### 10.5 X5 — docs and checks (one session)

- Add `i3 -C` and `polybar` startup checks to `validate.sh`, and `sh -n` for
  the new scripts (`make check` already lints `home/bin/*`).
- Record the two session paths in the README: `~/.session-wm` = `i3` or
  `spectrwm`.
- Write down the keybinding table once, in the README, and generate the cheat
  sheet from the live config (the `keybinds` helper already does this for
  spectrwm; i3 has `i3-msg -t get_config`, or parse the config with the same
  `sed`).
- Definition of done is the plan's: boot → themed xenodm → i3 with gapped
  tiles, polybar with pills/tray/clock → `Super+D` → `Super+Shift+/` →
  screenshots to clipboard → clipboard history → idle lock with blurred
  wallpaper → power menu → `theme-apply` repaints everything → `Super+Shift+E`
  returns to xenodm.

---

## 11. Day-2 operations

### 11.1 Updates

```sh
doas syspatch              # base-system patches (reboot if it says so)
doas pkg_add -u            # packages; then `doas pkg_check -q`
doas fw_update             # firmware, after a kernel update or new hardware
```

Automate the two that are safe unattended, in `/etc/weekly.local` (create it,
`chmod 755`, root-owned):

```sh
#!/bin/sh
syspatch >/var/log/syspatch.log 2>&1
pkg_add -u >/var/log/pkg-update.log 2>&1
```

`syspatch` occasionally needs a reboot; `pkg_add -u` can need a session
restart. Read the logs weekly rather than trusting the cron.

### 11.2 Backups

There is no snapshot filesystem here. What is worth keeping:

```sh
doas tar -C / -czf /home/peter/backup/etc-$(date +%F).tgz etc
doas tar -C /var -czf /home/peter/backup/var-db-$(date +%F).tgz db
tar -C "$HOME" -czf /home/peter/backup/home-$(date +%F).tgz \
  --exclude=.cache --exclude=.config/chromium .
```

`/var/backups/fdisk-sd0` holds the GPT from install time; copy it off the
machine. `/home` holds the ROMs and music — that is a separate, bigger backup.

### 11.3 Boot path repairs

After a Windows feature update, Windows often rewrites the NVRAM boot order and
the machine boots straight to Windows again. That is a boot-order change, not
data loss:

1. `F12` → internal NVMe entry → OpenBSD.
2. `doas installboot -v sd0`, then `doas installboot -c sd0` to restore the
   default entry.
3. If the firmware entry is gone entirely, re-check `\EFI\BOOT\BOOTX64.EFI` in
   §3.7; the file usually survives, only the variable is lost.

Windows' own entry is `Windows Boot Manager` in the same menu; if *it*
disappears, repair from the Windows recovery USB (`bootrec /rebuildbcd`), not
from OpenBSD.

### 11.4 Windows and BitLocker after the fact

- If you decrypted, re-enabling BitLocker now saves the recovery prompt later,
  but Secure Boot is still off. TPM-only protectors are fragile in that state;
  keep the recovery key somewhere you can reach without Windows.
- Windows updates can re-enable Fast Startup. Re-check `powercfg /a` after big
  updates; a hibernated NTFS volume is the one thing OpenBSD will not mount
  happily.
- Re-check the clock after a Windows feature update — `RealTimeIsUniversal` is
  unsupported and occasionally reset.

### 11.5 Hardware notes for this laptop

| Thing | How it works |
|---|---|
| Backlight | `wsconsctl display.brightness` via `doas`; `~/bin/brightness` falls back to RandR gamma |
| Audio | sndio; `sndioctl output.level`, `mixerctl` for hardware levels; no PulseAudio |
| Suspend | `zzz`/lid (`machdep.lidaction=1`); `apmd` + `/etc/apm/suspend` locks first |
| Battery | `apm -l`, `apm -a`; bar hides it when `apm -a` is 255 |
| Temperature | `hw.sensors.cpu0.temp0` |
| Fan/CPU | `obsdfreqd`; `hw.perfpolicy` if you prefer manual |
| Wifi | `iwm0`, firmware from `fw_update`; `join … wpakey` in `hostname.iwm0` |
| Trackpad | `ums`/`wsmouse`; tap/scroll tunables via `wsconsctl mouse.tp` (check what your build exposes) |
| Dock | Thunderbolt/USB-C works as `em0`/USB; re-run `xrandr`/`autorandr`-style display setup after docking |

---

## 12. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Installer does not see the NVMe | firmware booted legacy, or the disk is in a RAID/Intel RST mode | UEFI Only; T480s NVMe is native AHCI, but check BIOS if it was reconfigured |
| USB does not appear in F12 | Secure Boot on, or the image was copied as a file | Secure Boot off; re-`dd` the `.img` to the whole device |
| Installer offers no `(E)dit` | you are at the disk *selection* prompt, not the partition prompt | pick the disk first; `E` is the next question |
| `fdisk` says the partition overlaps | offset/size typed wrong, or the free-space numbers changed | `abort`, re-read `fdisk -v`, recompute; write nothing |
| OpenBSD boots to `boot>` but not the kernel | `installboot` wrote the loader but `/boot` is missing | boot `bsd.rd` from USB, check the root partition, re-run `installboot -v sd0` |
| Firmware has no OpenBSD entry | NVRAM variable not created | `installboot -c sd0`; else copy `BOOTX64.EFI` (§3.7) and pick the NVMe entry |
| `installboot: no OpenBSD partition` | GPT entry type is not OpenBSD | `fdisk -e sd0`, `setpid`/`edit` the entry to OpenBSD, `write`, retry |
| Windows no longer boots | boot order, or BCD damaged | F12 → Windows Boot Manager; if absent, Windows recovery USB `bootrec /rebuildbcd` |
| Clock off by the UTC offset | RTC is local time | §1.3 in Windows; OpenBSD expects UTC |
| xenodm restarts to the login prompt | `~/.xsession` failed | `Ctrl+Alt+F2`, log in, read `~/.xsession-errors`, run the failing command with `DISPLAY=:0` |
| Bar shows a validation error | a `program[]` path or `quirk` is bad | `spawn_flags[.*] += optional` is already set; check for `[Zz]`-style quirks and `#` colours |
| Bar shows `$HOME/...` literally | spectrwm does not expand `$HOME` | re-run the sed rewrite (§8) |
| st build fails on `c99` | 8.0 no longer ships `c99` | `build.sh` passes `CC=cc`; do not build with plain `make` |
| st build fails on Xft/freetype | no `.pc` files in xenocara | use `build.sh`'s explicit `INCS`/`LIBS` |
| `st: unknown terminal type` on a remote host | terminfo not copied | `infocmp -x st-256color`, `tic` on the remote |
| No sound | mixer muted, or wrong output | `sndioctl -n output.mute`, `sndioctl output.level=0.8`, `mixerctl -a` |
| Brightness keys do nothing | missing `doas` rule, or panel has no `display.brightness` | add the rule (§7.1); the script falls back to gamma |
| `Super+Shift+C` does not copy the URL | synthetic keys not delivered | use `Ctrl+L`, `Ctrl+C` then `Super+Shift+D`; clipboard route always works |
| Chromium has no adblocker | policy not fetched (offline) or profile locked | `chrome://policy`; close Chromium, remove a stale `SingletonLock`, relaunch |
| Chromium ignores a policy | another file in `policies/managed` sets the same key and they merge | list the directory, remove leftovers |
| picom exits immediately | config key unsupported in your picom build | run `picom --config …` in a terminal and read the first error |
| Tearing with picom | GLX/vsync mismatch | `xrender` backend (repo default) or `TearFree` (§10.1) |
| `pkg_add` refuses a stem | stem matches several packages | pin with the empty-version form (`rsync--minimal`) |
| Gaming stage skipped | < 3 GiB free on `/usr/local` | grow `/usr/local` or install later with `--only=gaming` |
| `doas` says "no rules" | `/etc/doas.conf` missing (installer never writes one) | §4.3 |
| SSH login lost after applying the repo | `AllowUsers peter`, `PasswordAuthentication no` | console on `ttyC2`, add the key or relax the drop-in |

---

## 13. Definition of done

Power on → firmware → OpenBSD `boot>` → xenodm with the amber wallpaper →
password → spectrwm with gapped tiles, amber bar carrying network, battery,
temperature, volume, track music and clock → `Super+Return` gives an amber `st`
→ `Super+D` gives rofi drun → `Super+Shift+/` lists the live bindings →
`Super+S` saves a screenshot to `~/Pictures/Screenshots` and the clipboard →
`clipmenu` shows history → five idle minutes lock the screen → lid close locks
then suspends → `Super+Space` power menu works without a password prompt →
`theme-apply amber` repaints terminal chrome, rofi, dunst, wallpaper and bar →
`Super+Shift+E` returns to xenodm → reboot into Windows through F12 with
BitLocker and the clock both intact.

Then, and only then, start plan phase X1.

---

## Appendix A — installer answers at a glance

```
I
vt220
t480s
em0
autoconf
none
<empty>
none
<root password>
yes
yes
no
peter
Peter
<peter password>
no
sd0
E          # then: edit 5 / offset / size / type OpenBSD / print / write / quit
A
no
Europe/Dublin
cd0
all
yes
H
```

## Appendix B — the whole thing as commands

For a machine that is already installed, networked and has the repo in
`~/openbsd-setup` as `peter`:

```sh
# as root, once
printf 'permit persist :wheel\n' > /etc/doas.conf && chmod 600 /etc/doas.conf
syspatch
fw_update

# as peter
doas pkg_add git
git clone <repo> ~/openbsd-setup
cd ~/openbsd-setup
doas ./install.sh --metal --dry-run    # read every line
doas ./install.sh --metal              # system, packages, terminal, desktop,
                                       # browser, gaming, validate
doas reboot
```

`install.sh` is idempotent: re-running it after editing the repo is the normal
workflow, and anything it replaces is first copied to
`~/.config-backup-<timestamp>/`. Use `--only=terminal` to rebuild `st`,
`--only=desktop` for dotfiles only, `--list` for the stage order.

## Appendix C — files that must never be committed

`/etc/fstab`, `/etc/mygate`, `/etc/ssh/ssh_host_*`, `/etc/master.passwd`,
`/etc/passwd`, `/etc/group`, `/etc/host.random`, `/var/db/*`, the wifi
passphrase, and anything under `secrets/`. Each install generates them; the
repo's `.gitignore` and `secrets/.gitignore` already cover the obvious ones.
