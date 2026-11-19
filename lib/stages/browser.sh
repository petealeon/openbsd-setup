#!/bin/sh
# lib/stages/browser.sh — Chromium: calm defaults and adblock guidance.
#
# OpenBSD's Chromium is pledged/unveiled and honours managed policy in
# /etc/chromium/policies. We apply safe "calm" defaults, but we do NOT
# force-install extensions via policy: a force-installed MV3 extension can end
# up "Managed by your administrator" and (if its service worker fails to
# register on OpenBSD) be unusable and unmodifiable. Instead, users should
# install uBlock Origin Lite from the Web Store and can manage/adjust it
# themselves.

POLICY_DIR=/etc/chromium/policies/managed

stage_browser() {
	say "browser: Chromium policy defaults"

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

	info "Open Chrome and install 'uBlock Origin Lite' from the Web Store"
	info "(chrome://extensions) — not force-installed, so you can manage it."
	info "Super+Shift+B browser   Super+Shift+D download the tab   Super+Shift+C copy its URL"
}
