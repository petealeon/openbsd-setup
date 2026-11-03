#!/bin/sh
# lib/stages/packages.sh — install packages.txt (and packages-vm.txt in a VM).
#
# pkg_add -l does not understand comments, so the list is filtered first.
# A stem that matches more than one package makes pkg_add refuse; the fix is
# to pin it in packages.txt (e.g. rsync-- or unzip--icons).

stage_packages() {
	say "packages: pkg_add"

	list=$(mktemp "${TMPDIR:-/tmp}/packages.XXXXXX") || die "mktemp failed"

	grep -v '^[[:space:]]*#' "$REPO/packages.txt" |
		grep -v '^[[:space:]]*$' >"$list" || true

	if [ "$MODE" = vm ] && [ -s "$REPO/packages-vm.txt" ]; then
		grep -v '^[[:space:]]*#' "$REPO/packages-vm.txt" |
			grep -v '^[[:space:]]*$' >>"$list" || true
	fi

	if [ ! -s "$list" ]; then
		warn "nothing to install"
		rm -f "$list"
		return 0
	fi

	info "$(wc -l <"$list" | tr -d ' ') packages"
	# -D snap keeps pkg_add on the release/snapshot path in installurl.
	run pkg_add -l "$list" || warn "pkg_add reported problems; see the output above"
	rm -f "$list"

	run pkg_check -q || warn "pkg_check is unhappy (partial install?)"
}
