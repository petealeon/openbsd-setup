#!/bin/sh
# lib/stages/browser.sh — Chromium: adblocking and calm defaults.
#
# OpenBSD's chromium is pledged and unveiled, so there is no way to hand it an
# unpacked extension from a dotfile. What it does honour is managed policy in
# /etc/chromium/policies (which /etc/chromium/unveil.main already exposes), so
# the adblocker is force-installed from the Web Store by policy instead.
#
# The extension is uBlock Origin Lite (MV3): Chromium 156 dropped Manifest V2,
# so classic uBlock Origin can no longer load.

UBOL_ID=ddkjiahejlhfcafbddmgiahcphecmpfh
POLICY_DIR=/etc/chromium/policies/managed

stage_browser() {
	say "browser: Chromium policy + uBlock Origin Lite"

	run mkdir -p "$POLICY_DIR"
	run install -m 644 -o root -g wheel \
		"$REPO/etc/chromium/policies/managed/amber.json" \
		"$POLICY_DIR/amber.json"

	# Two policy files that set the same key are merged, not overridden, so a
	# leftover file from an earlier experiment is worth knowing about.
	for f in "$POLICY_DIR"/*.json; do
		[ -f "$f" ] || continue
		[ "${f##*/}" = amber.json ] && continue
		warn "another Chromium policy is also active: $f"
	done

	if dry; then
		info "would pre-fetch $UBOL_ID into $GUEST_HOME/.config/chromium"
		return 0
	fi

	ext="$GUEST_HOME/.config/chromium/Default/Extensions/$UBOL_ID"
	if [ -d "$ext" ]; then
		info "uBlock Origin Lite is already in the profile"
	elif ! command -v chrome >/dev/null 2>&1; then
		warn "chrome is not installed; skipping the adblocker warm-up"
	elif pgrep -qf '/usr/local/chrome/chrome'; then
		info "Chromium is running: uBlock Origin Lite installs on its next launch"
	else
		warm_profile
	fi

	info "Super+Shift+B browser   Super+Shift+D download the tab   Super+Shift+C copy its URL"
}

# warm_profile — launch Chromium headless until the store delivers the
# extension, then stop it. On a fresh install this means the very first window
# already has the adblocker, and the stage reports whether the policy was
# honoured instead of silently hoping it was.
warm_profile() {
	# --headless=new would otherwise invent ~/.config/chromium-headless, fail to
	# create its SingletonLock and abort before it ever contacts the store, so
	# point it at the real profile.  XDG_RUNTIME_DIR is what the OpenBSD sandbox
	# wants for its socket directory; without it, it complains but continues.
	run mkdir -p "$GUEST_HOME/.config/chromium" "$GUEST_HOME/.cache/chromium-runtime"
	run chown "$GUEST_USER:$GUEST_USER" \
		"$GUEST_HOME/.config/chromium" "$GUEST_HOME/.cache/chromium-runtime"
	run chmod 700 "$GUEST_HOME/.cache/chromium-runtime"

	pid=$(su -m "$GUEST_USER" -c \
		"HOME='$GUEST_HOME' XDG_RUNTIME_DIR='$GUEST_HOME/.cache/chromium-runtime' \
		chrome --headless=new --disable-gpu --no-first-run \
		--no-default-browser-check --user-data-dir='$GUEST_HOME/.config/chromium' \
		about:blank >/dev/null 2>&1 & echo \$!")
	info "warming the browser profile (uBlock Origin Lite, up to 60s)"
	i=0
	while [ "$i" -lt 30 ]; do
		[ -d "$ext" ] && break
		sleep 2
		i=$((i + 1))
	done
	# Chromium rewrites its process title to "chrome: --headless=new ...", so a
	# pkill on /usr/local/chrome/chrome misses it -- and a surviving headless
	# browser keeps SingletonLock, which makes the user's first real launch
	# abort. Kill the PID we started, and match the flag as a backstop.
	[ -n "${pid:-}" ] && kill "$pid" 2>/dev/null
	pkill -f 'headless=new' 2>/dev/null || true
	sleep 1

	# The chrome wrapper clears a dead SingletonLock by itself, but a fresh
	# install should not look like a broken browser in the meantime.
	lock="$GUEST_HOME/.config/chromium/SingletonLock"
	if [ -L "$lock" ]; then
		lockpid=${lock##*-}
		kill -0 "$lockpid" 2>/dev/null || rm -f "$lock"
	fi

	if [ -d "$ext" ]; then
		info "uBlock Origin Lite is installed in the browser profile"
	else
		warn "uBlock Origin Lite was not fetched (offline?); it installs on the next launch with network"
	fi
}
