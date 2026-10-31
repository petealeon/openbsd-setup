#!/bin/sh
# Syntax-check the config that apply/provision just installed.
set -u
fail=0

echo "-- sshd"
sshd -t || fail=1

echo "-- pf"
pfctl -n -f /etc/pf.conf || fail=1

echo "-- doas"
doas -C /etc/doas.conf || fail=1

exit "$fail"
