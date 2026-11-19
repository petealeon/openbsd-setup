#!/bin/sh
# update.sh — apply config/script fixes to an existing OpenBSD install
# without a full reinstall.
#
# Run from the repo directory on the target machine:
#   doas sh ./update.sh                 # apply changes for invoking user
#   doas sh ./update.sh --user alice    # explicit user/home
#   doas sh ./update.sh --skip-terminal # skip rebuilding st (offline/faster)
#   sh ./update.sh --dry-run            # preview actions
#
# What it does (safe/idempotent):
#   - desktop: dotfiles, ~/bin helpers, theme/bar, user dirs
#   - system:  /etc overlays (doas, chromium policy, hotplug, unwind, apm,
#              xenodm Xsetup), permissions, service enable/reload
#   - terminal (optional): rebuild/install st from share/st so st-256color
#              terminfo and fonts/colors behave as intended
#
# It does NOT: syspatch, fw_update, pkg_add, or touch disk/bootloader config.
# Re-run the relevant install stage if packages/patches are missing:
#   doas ./install.sh --metal --only=packages,desktop,system,browser,terminal

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MODE=metal
DRY=0
SKIP_TERMINAL=0

DEFAULT_USER=${SUDO_USER:-${DOAS_USER:-${LOGNAME:-${USER:-}}}}
case ${DEFAULT_USER:-} in
	""|root)
		if command -v logname >/dev/null 2>&1; then
			DEFAULT_USER=$(logname 2>/dev/null || true)
		fi
		;;
esac
case ${DEFAULT_USER:-} in ""|root) DEFAULT_USER= ;; esac
GUEST_USER=${GUEST_USER:-$DEFAULT_USER}

usage() {
	cat <<'EOF'
usage: update.sh [--user name] [--dry-run] [--skip-terminal]

  --user name      desktop user/home to update (default: invoking user)
  --dry-run        show actions without making changes
  --skip-terminal  do not rebuild/install st (use if offline or already built)

Environment:
  GUEST_USER       same as --user
EOF
}

while [ $# -gt 0 ]; do
	case $1 in
	--user)
		GUEST_USER=${2:-}
		[ $# -gt 1 ] && shift
		;;
	--user=*) GUEST_USER=${1#--user=} ;;
	--dry-run) DRY=1 ;;
	--skip-terminal) SKIP_TERMINAL=1 ;;
	-h|--help) usage; exit 0 ;;
	*) printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
	esac
	shift
done

case ${GUEST_USER:-} in
	""|root)
		printf '%s\n' "error: cannot determine desktop user; pass --user <name>" >&2
		usage >&2
		exit 2
		;;
	*[!A-Za-z0-9._-]*)
		printf 'error: invalid user name: %s\n' "$GUEST_USER" >&2
		exit 2
		;;
esac
GUEST_HOME=/home/$GUEST_USER

. "$REPO/lib/common.sh"

[ "$DRY" -eq 1 ] || need_root
[ -d "$GUEST_HOME" ] || die "no such home directory: $GUEST_HOME"

say "OpenBSD update — mode=$MODE user=$GUEST_USER"
[ "$DRY" -eq 1 ] && info "dry run: nothing is written"
[ "$SKIP_TERMINAL" -eq 1 ] && info "terminal rebuild skipped (--skip-terminal)"

errors=0
note_err() {
	warn "$1"
	errors=$((errors + 1))
}

# --- desktop: dotfiles, helpers, theme, user dirs ---------------------------
# shellcheck source=lib/stages/desktop.sh
. "$REPO/lib/stages/desktop.sh"
if stage_desktop; then
	info "desktop stage: ok"
else
	note_err "desktop stage failed"
fi

# --- system: /etc overlays, doas, chromium policy, hotplug, services --------
# Run before terminal rebuild so critical system fixes (e.g. doas/wsconsctl,
# chromium policy) are applied even if st cannot be rebuilt (offline/no tarball).
# shellcheck source=lib/stages/system.sh
. "$REPO/lib/stages/system.sh"
if stage_system; then
	info "system stage: ok"
else
	note_err "system stage failed"
fi

# --- terminal: rebuild st (fonts/terminfo/colors), optional ---------------
if [ "$SKIP_TERMINAL" -eq 0 ]; then
	# shellcheck source=lib/stages/terminal.sh
	. "$REPO/lib/stages/terminal.sh"
	if stage_terminal; then
		info "terminal stage: ok"
	else
		note_err "terminal stage failed (st rebuild/terminfo). Other fixes were still applied."
		warn "Retry with network/sources: doas sh ./install.sh --metal --only=terminal"
	fi
else
	info "terminal stage: skipped"
fi

if [ "$errors" -eq 0 ]; then
	say "update complete"
else
	say "update finished with $errors error(s) (see warnings above)"
fi

info "Log out and log back in to xenodm (or reboot) so the new session,"
info "spectrwm config, input settings, dunst, and environment take effect."
info "Close and reopen terminals after login (and after any st rebuild)."
info "Check: echo \$ENV ; grep wsconsctl /etc/doas.conf"
exit "$errors"
