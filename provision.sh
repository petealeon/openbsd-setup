#!/bin/sh
# provision.sh -- apply this repo to a fresh OpenBSD install.
#
#   doas ./provision.sh --vm      (rehearsal VM: adds serial console, qemu-ga, root key)
#   doas ./provision.sh --metal   (bare metal: adds iwm0/em0 and wscons config)
#
# Idempotent: safe to run again after editing the repo.
set -eu

MODE=
case ${1:-} in
--vm)    MODE=vm ;;
--metal) MODE=metal ;;
*)
	echo "usage: $0 --vm|--metal" >&2
	exit 2
	;;
esac

[ "$(id -u)" -eq 0 ] || {
	echo "error: run me as root (doas ./provision.sh $1)" >&2
	exit 1
}

REPO=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GUEST_USER=peter
GUEST_HOME=/home/$GUEST_USER

echo "== syspatch =="
syspatch || true

echo "== packages =="
pkg_add -l "$REPO/packages.txt"
if [ "$MODE" = vm ]; then
	pkg_add -l "$REPO/packages-vm.txt"
fi

echo "== /etc overlay =="
tar -C "$REPO" -cf - etc | tar -C / -xpf -
if [ "$MODE" = vm ]; then
	tar -C "$REPO/etc-vm" -cf - . | tar -C /etc -xpf -
else
	tar -C "$REPO/etc-hardware" -cf - . | tar -C /etc -xpf -
fi
# Archives are built from unprivileged files: fix ownership, then lock down doas.
find /etc -user "$GUEST_USER" -exec chown root:wheel {} + 2>/dev/null || true
[ -f /etc/doas.conf ] && chmod 600 /etc/doas.conf

echo "== home overlay =="
tar -C "$REPO/home" -cf - . | tar -C "$GUEST_HOME" -xpf -
chown -R "$GUEST_USER:$GUEST_USER" "$GUEST_HOME"

echo "== sshd drop-in include =="
if ! grep -q 'sshd_config.d' /etc/ssh/sshd_config; then
	printf 'Include /etc/ssh/sshd_config.d/*.conf\n' |
		cat - /etc/ssh/sshd_config >/tmp/sshd_config.new
	mv /tmp/sshd_config.new /etc/ssh/sshd_config
	chmod 600 /etc/ssh/sshd_config
fi

echo "== services =="
[ -x /etc/rc.d/xenodm ] && rcctl enable xenodm
if [ "$MODE" = vm ]; then
	[ -x /etc/rc.d/qemu_ga ] && rcctl enable qemu_ga
	# serial console getty for virsh console
	if ! grep -q '^tty00' /etc/ttys; then
		echo 'tty00 "/usr/libexec/getty std.115200" vt220 on secure' >>/etc/ttys
	fi
	# root key so the host can run apply/capture without a password
	if [ -f "$GUEST_HOME/.ssh/authorized_keys" ]; then
		install -d -m 700 /root/.ssh
		install -m 600 "$GUEST_HOME/.ssh/authorized_keys" /root/.ssh/authorized_keys
	fi
else
	fw_update || true
fi

# Pick up newly installed sshd drop-ins without dropping the running session.
rcctl reload sshd 2>/dev/null || true

echo "== validate =="
sh "$REPO/validate.sh"

echo "== done =="
if [ "$MODE" = vm ]; then
	echo "Reboot, then from the host: vm apply / vm capture / vm ssh"
else
	echo "Reboot to pick up sshd, xenodm and wscons settings."
fi
