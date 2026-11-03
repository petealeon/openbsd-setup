#!/bin/sh
# lib/stages/validate.sh — validate what the earlier stages installed.

stage_validate() {
	say "validate"

	run sh "$REPO/validate.sh" || warn "validate.sh reported problems"

	if dry; then
		return 0
	fi

	# The chromium package's launcher is chrome(1) on OpenBSD.
	for b in st spectrwm rofi dunst picom feh maim ncmpcpp mpc yt-dlp deno \
		chrome; do
		command -v "$b" >/dev/null 2>&1 || warn "missing binary: $b"
	done

	# ~/bin is on the user's PATH, not root's, so test the files directly.
	for b in browser video-download copy-url theme-apply; do
		[ -x "$GUEST_HOME/bin/$b" ] || warn "missing helper: ~/bin/$b"
	done

	[ -f "$GUEST_HOME/.spectrwm.conf" ] ||
		warn "no ~/.spectrwm.conf for $GUEST_USER"

	if ! grep -q '>>> theme colors >>>' "$GUEST_HOME/.spectrwm.conf" 2>/dev/null; then
		warn "theme colour markers are missing from ~/.spectrwm.conf"
	fi

	info "validation finished"
}
