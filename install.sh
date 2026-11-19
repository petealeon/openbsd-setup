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

# Default to the invoking user when run via doas/sudo or directly; fall back
# to the first non-root login hint. --user is required if we cannot infer one.
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
GUEST_HOME=
STAGES="system packages terminal desktop browser gaming validate"

usage() {
	cat <<'EOF'
usage: install.sh [--metal|--vm] [--only=a,b] [--dry-run] [--user name] [--list]

  --metal        bare metal (default): hardware /etc overlay, fw_update
  --vm           rehearsal VM: serial console getty, root SSH key
  --only=...     run just these stages (see --list)
  --dry-run      show every change without making it
  --user name    desktop user/home to configure (default: invoking user)
  --list         print the stage order and exit

Environment:
  GUEST_USER     same as --user
EOF
}

while [ $# -gt 0 ]; do
	case $1 in
	--metal) MODE=metal ;;
	--vm)    MODE=vm ;;
	--only)
		ONLY=${2:-}
		[ $# -gt 1 ] && shift
		;;
	--only=*) ONLY=${1#--only=} ;;
	--dry-run) DRY=1 ;;
	--user)
		GUEST_USER=${2:-}
		[ $# -gt 1 ] && shift
		;;
	--user=*) GUEST_USER=${1#--user=} ;;
	--list)
		printf '%s\n' "$STAGES"
		exit 0
		;;
	-h|--help) usage; exit 0 ;;
	*)
		printf 'unknown argument: %s\n' "$1" >&2
		usage >&2
		exit 2
		;;
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

if [ -z "$ONLY" ] && [ "$DRY" -eq 0 ]; then
	need_root
fi

say "OpenBSD setup — mode=$MODE user=$GUEST_USER"
[ "$DRY" -eq 1 ] && info "dry run: nothing is written"

run_stage() {
	name=$1
	file="$REPO/lib/stages/$name.sh"
	[ -f "$file" ] || die "unknown stage: $name"
	# shellcheck source=/dev/null
	. "$file"
	"stage_$name"
}

if [ -n "$ONLY" ]; then
	IFS=, set -- $ONLY
else
	set -- $STAGES
fi

for stage; do
	[ -n "$stage" ] || continue
	run_stage "$stage"
done

say "done"
if [ "$MODE" = vm ]; then
	info "serial console: /etc/boot.conf -> com0 115200"
	info "xenodm: rcctl ls on | grep xenodm"
	info "after a login test: ./vm snap baseline"
else
	info "reboot, log in via xenodm, then run ./validate.sh as a sanity check"
fi
