#!/bin/sh
# install.sh — take a fresh OpenBSD 8.0 install to the amber desktop.
#
#   doas ./install.sh --metal          real install on the T480s
#   doas ./install.sh --vm             rehearsal VM (serial console, root key)
#   ./install.sh --metal --dry-run     print every change, touch nothing
#   doas ./install.sh --metal --only=terminal,desktop
#   ./install.sh --list                show the stage order
#
# Stages live in lib/stages/<name>.sh as stage_<name>.  They are idempotent:
# running the whole thing again after editing the repo is the normal workflow.

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MODE=metal
ONLY=
DRY=0
GUEST_USER=${GUEST_USER:-peter}
GUEST_HOME=/home/$GUEST_USER
STAGES="system packages terminal desktop browser gaming validate"

usage() {
	cat <<'EOF'
usage: install.sh [--metal|--vm] [--only=a,b] [--dry-run] [--user name] [--list]

  --metal        bare metal (default): hardware /etc overlay, fw_update
  --vm           rehearsal VM: serial console getty, root SSH key
  --only=...     run just these stages (see --list)
  --dry-run      show every change without making it
  --user name    desktop user (default: peter)
  --list         print the stage order and exit
EOF
}

while [ $# -gt 0 ]; do
	case $1 in
	--metal) MODE=metal ;;
	--vm)    MODE=vm ;;
	--only)
		ONLY=${2:-}
		if [ $# -gt 1 ]; then shift; fi
		;;
	--only=*) ONLY=${1#--only=} ;;
	--dry-run) DRY=1 ;;
	--user)
		GUEST_USER=${2:-}
		GUEST_HOME=/home/$GUEST_USER
		if [ $# -gt 1 ]; then shift; fi
		;;
	--list)
		printf '%s\n' "$STAGES"
		exit 0
		;;
	-h|--help)
		usage
		exit 0
		;;
	*)
		printf 'unknown argument: %s\n\n' "$1" >&2
		usage >&2
		exit 2
		;;
	esac
	shift
done

. "$REPO/lib/common.sh"

[ "$DRY" -eq 1 ] || need_root
[ -d "$GUEST_HOME" ] || die "no such home directory: $GUEST_HOME"

want_stage() {
	[ -z "$ONLY" ] && return 0
	case ",$ONLY," in
	*",$1,"*) return 0 ;;
	*) return 1 ;;
	esac
}

say "OpenBSD setup — mode=$MODE user=$GUEST_USER"
[ "$DRY" -eq 1 ] && info "dry run: nothing is written"

for stage in $STAGES; do
	if ! want_stage "$stage"; then
		info "skip $stage"
		continue
	fi
	[ -f "$REPO/lib/stages/$stage.sh" ] || die "missing stage: $stage"
	. "$REPO/lib/stages/$stage.sh"
	"stage_$stage"
done

say "done"
case $MODE in
metal) info "reboot to pick up sshd, xenodm, wscons and the st build" ;;
vm)    info "reboot, then from the host: ./vm apply / ./vm ssh" ;;
esac
info "keybindings: Super+Shift+/    command menu: Super+space"
