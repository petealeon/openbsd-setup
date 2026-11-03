#!/bin/sh
# provision.sh — compatibility wrapper. install.sh is the real entry point.
#
#   doas ./provision.sh --vm
#   doas ./provision.sh --metal
#
# Everything else (--only=..., --dry-run, --user) passes straight through.
set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MODE=--metal

case ${1:-} in
--vm|--metal)
	MODE=$1
	shift
	;;
esac

exec "$REPO/install.sh" "$MODE" "$@"
