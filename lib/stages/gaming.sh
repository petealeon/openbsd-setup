#!/bin/sh
# lib/stages/gaming.sh — RetroArch, cores and the standalone emulators.
#
# Kept separate from packages.txt because it is the only part of the setup
# that needs gigabytes under /usr/local; a small VM disk should still get a
# working desktop rather than a half-installed emulator stack.

stage_gaming() {
	say "gaming: RetroArch and emulators"

	list=$(mktemp "${TMPDIR:-/tmp}/gaming.XXXXXX") || die "mktemp failed"
	grep -v '^[[:space:]]*#' "$REPO/packages-gaming.txt" |
		grep -v '^[[:space:]]*$' >"$list" || true

	if [ ! -s "$list" ]; then
		rm -f "$list"
		return 0
	fi

	# ~3 GiB is the measured footprint of the set with its dependencies.
	need=3145728
	avail=$(df -k /usr/local 2>/dev/null | awk 'NR==2 { print $4 }')
	case ${avail:-} in
	''|*[!0-9]*) avail=0 ;;
	esac

	if [ "$avail" -lt "$need" ]; then
		warn "/usr/local has $((avail / 1024)) MiB free; the emulators need ~3 GiB"
		warn "skipping gaming packages (install later: doas ./install.sh --only=gaming)"
		rm -f "$list"
		return 0
	fi

	info "$(wc -l <"$list" | tr -d ' ') packages, $((avail / 1024)) MiB free"
	run pkg_add -l "$list" || warn "pkg_add reported problems; see the output above"
	rm -f "$list"

	# The games menu wants a predictable place to look.
	run mkdir -p "$GUEST_HOME/Games"
	run chown "$GUEST_USER:$GUEST_USER" "$GUEST_HOME/Games"
}
