#!/bin/sh
# validate.sh — syntax-check the configuration install.sh just applied.
#
# Runs on OpenBSD for real, and on any other host in a static-only mode so the
# repo can be linted before it ever reaches the machine.

set -u
fail=0

step() { printf '%s\n' "-- $*"; }
bad()  { fail=1; printf '   %s\n' "$*" >&2; }

if [ "$(uname -s)" = OpenBSD ]; then
	step "sshd"
	sshd -t || bad "sshd -t failed"

	step "pf"
	pfctl -n -f /etc/pf.conf || bad "pfctl -n failed"

	step "doas"
	doas -C /etc/doas.conf || bad "doas -C failed"

	step "unwind"
	if command -v unwind >/dev/null 2>&1 && [ -f /etc/unwind.conf ]; then
		unwind -n >/dev/null 2>&1 || bad "unwind -n failed"
	fi

	step "services"
	rcctl ls on 2>/dev/null | grep -qx xenodm || bad "xenodm is not enabled"
else
	printf '%s\n' "not OpenBSD: skipping sshd/pf/doas checks"
fi

step "shell syntax"
repo=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
for f in "$repo/install.sh" "$repo/provision.sh" "$repo/validate.sh" \
	"$repo/lib/common.sh" "$repo"/lib/stages/*.sh \
	"$repo/share/st/build.sh" "$repo"/home/bin/* \
	"$repo/home/.config/spectrwm/bar.sh" "$repo/home/.config/lf/open" \
	"$repo/home/.config/lf/preview" "$repo/home/.xsession" \
	"$repo/home/.xinitrc" "$repo/etc/apm/suspend"; do
	[ -f "$f" ] || continue
	sh -n "$f" || bad "sh -n $f"
done

step "config sanity"
grep -q '>>> theme colors >>>' "$repo/home/.spectrwm.conf" ||
	bad "spectrwm theme markers missing"
grep -q '@theme "amber"' "$repo/home/.config/rofi/config.rasi" ||
	bad "rofi is not pointing at the amber theme"
[ -f "$repo/home/.config/spectrwm/themes/amber/wallpaper.png" ] ||
	bad "amber wallpaper missing"
[ -f "$repo/share/st/patches/st-scrollback-0.9.2.diff" ] ||
	bad "st scrollback patch missing"
if grep -q 'ExtensionInstallForcelist' \
	"$repo/etc/chromium/policies/managed/amber.json"; then
	bad "Chromium policy still force-installs extensions (can be unmanageable/broken)"
fi
[ -f "$repo/home/bin/audio-output" ] ||
	bad "audio-output helper missing"
[ -f "$repo/home/bin/kbdlight" ] ||
	bad "kbdlight helper missing"
[ -f "$repo/home/bin/video-download" ] ||
	bad "video-download helper missing"
[ -f "$repo/home/bin/update-blocklist" ] ||
	bad "update-blocklist helper missing"
[ -x "$repo/etc/hotplug/attach" ] ||
	bad "hotplug/attach script missing or not executable"
[ -f "$repo/etc/unwind.conf" ] ||
	bad "unwind.conf missing"
[ -f "$repo/home/.config/retroarch/retroarch.cfg" ] ||
	bad "RetroArch default config missing"

if [ "$fail" -eq 0 ]; then
	printf '%s\n' "all checks passed"
else
	printf '%s\n' "checks failed" >&2
fi

exit "$fail"
