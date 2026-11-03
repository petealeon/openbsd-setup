#!/bin/sh
# lib/common.sh — shared helpers for install.sh and lib/stages/*.sh.
#
# Sourced, never executed.  Every mutation goes through run() or run_shell()
# so `install.sh --dry-run` is a real preview.

say()  { printf '==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

dry() { [ "${DRY:-0}" -eq 1 ]; }

run() {
	if dry; then
		printf '  + %s\n' "$*"
		return 0
	fi
	"$@"
}

run_shell() {
	if dry; then
		printf '  + sh -c %s\n' "$1"
		return 0
	fi
	sh -c "$1"
}

need_root() {
	[ "$(id -u)" -eq 0 ] ||
		die "run me as root: doas ./install.sh --$MODE"
}

# backup_path <path> — copy an existing user file into $BACKUP, path preserved.
backup_path() {
	p=$1
	[ -e "$p" ] || return 0
	[ -n "${BACKUP:-}" ] || return 0
	rel=${p#"$GUEST_HOME"/}
	[ "$rel" = "$p" ] && return 0
	mkdir -p "$BACKUP/$(dirname "$rel")"
	cp -Rp "$p" "$BACKUP/$rel"
}

init_backup() {
	BACKUP="$GUEST_HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
	run mkdir -p "$BACKUP"
	run chown "$GUEST_USER:$GUEST_USER" "$BACKUP" 2>/dev/null || true
	info "previous files will be saved in $BACKUP"
}

as_user() {
	run su -m "$GUEST_USER" -c "$1"
}
