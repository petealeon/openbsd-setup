#!/bin/sh
# lib/stages/system.sh — patching, /etc overlay, base services.

stage_system() {
	say "system: base patches, /etc overlay, services"

	if [ "$MODE" = metal ]; then
		run fw_update || warn "fw_update failed (offline, or nothing to do)"
	fi
	run syspatch || warn "syspatch failed or reported nothing to do"

	# ── /etc overlay ─────────────────────────────────────────────────────
	# Archive the repo directory itself (members `etc/...`), not the contents
	# of etc/: extracting `./...` at / would scatter doas.conf and friends
	# across the filesystem root instead of into /etc.
	run_shell "tar -C '$REPO' -cf - etc | tar -C / -xpf -"
	if [ "$MODE" = vm ]; then
		run_shell "tar -C '$REPO/etc-vm' -cf - . | tar -C /etc -xpf -"
	else
		run_shell "tar -C '$REPO/etc-hardware' -cf - . | tar -C /etc -xpf -"
	fi

	# Archives are built from files owned by whoever cloned the repo; the
	# resulting /etc files must be root's, and the sensitive ones private.
	run_shell "find /etc -user '$GUEST_USER' -exec chown root:wheel {} + 2>/dev/null || true"
	if [ -f /etc/doas.conf ]; then
		run chmod 600 /etc/doas.conf
	fi
	if [ -f /etc/ssh/sshd_config ]; then
		run chmod 600 /etc/ssh/sshd_config
	fi
	run_shell "find /etc/ssh/sshd_config.d -type f -exec chmod 600 {} + 2>/dev/null || true"

	# ── sshd drop-in include ─────────────────────────────────────────────
	if ! grep -q 'sshd_config.d' /etc/ssh/sshd_config 2>/dev/null; then
		run_shell "printf 'Include /etc/ssh/sshd_config.d/*.conf\n' |
			cat - /etc/ssh/sshd_config >/tmp/sshd_config.new &&
			mv /tmp/sshd_config.new /etc/ssh/sshd_config &&
			chmod 600 /etc/ssh/sshd_config"
	fi

	# ── services ─────────────────────────────────────────────────────────
	run rcctl enable xenodm
	run rcctl enable apmd
	run rcctl enable hotplugd
	if [ -x /etc/rc.d/obsdfreqd ]; then
		run rcctl enable obsdfreqd
		run rcctl start obsdfreqd || true
	fi

	if [ "$MODE" = vm ]; then
		# Serial console getty for `virsh console`.
		if ! grep -q '^tty00' /etc/ttys 2>/dev/null; then
			run_shell "echo 'tty00 \"/usr/libexec/getty std.115200\" vt220 on secure' >>/etc/ttys"
		fi
		# Root key so the host can run apply/capture without a password.
		if [ -f "$GUEST_HOME/.ssh/authorized_keys" ]; then
			run mkdir -p /root/.ssh
			run chmod 700 /root/.ssh
			run install -m 600 "$GUEST_HOME/.ssh/authorized_keys" /root/.ssh/authorized_keys
		fi
	fi

	# sshd reads the new drop-ins without dropping the running session.
	run rcctl reload sshd || true
}
