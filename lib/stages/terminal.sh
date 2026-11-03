#!/bin/sh
# lib/stages/terminal.sh — build st and install the bundled Nerd Font.

stage_terminal() {
	say "terminal: st $(sed -n 1p "$REPO/share/st/VERSION" 2>/dev/null || echo 0.9.2)"

	run sh "$REPO/share/st/build.sh"

	run mkdir -p "$GUEST_HOME/.fonts"
	for f in "$REPO"/share/fonts/*.ttf "$REPO"/share/fonts/OFL-*.txt; do
		[ -f "$f" ] || continue
		run install -m 644 -o "$GUEST_USER" -g "$GUEST_USER" "$f" \
			"$GUEST_HOME/.fonts/${f##*/}"
	done

	as_user "fc-cache -f >/dev/null 2>&1 || true"

	if ! dry && ! infocmp st-256color >/dev/null 2>&1; then
		warn "st-256color terminfo is missing: tic did not install it"
	fi
}
