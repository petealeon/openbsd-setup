#!/bin/sh
# collect-suspend-diagnostics.sh
#
# Collects baseline + post-resume diagnostics for OpenBSD suspend/wake issues
# (e.g. CPU pegged at ~100% / interrupt storm / fan spin after lid resume).
#
# Usage (on the target OpenBSD machine, from the repo copy):
#   sh ./scripts/collect-suspend-diagnostics.sh
#   sh ./scripts/collect-suspend-diagnostics.sh /path/to/report.txt
#
# The script writes a single text report. Default:
#   $HOME/suspend-diag-YYYYmmdd-HHMMSS.txt
#
# It is read-only with respect to system state (it only reads files/commands
# and writes the report). Some commands provide more detail if run with doas,
# but it is designed to be useful when run as a normal user.

set -eu

umask 077

ts() { date '+%Y%m%d-%H%M%S'; }

OUT=${1:-"$HOME/suspend-diag-$(ts).txt"}

# Ensure parent dir exists (for custom paths)
outdir=$(dirname "$OUT")
mkdir -p "$outdir" 2>/dev/null || true

# Append helper
log() { printf '%s\n' "$*" >>"$OUT"; }

section() {
	log ""
	log "########################################################################"
	log "## $*"
	log "## $(date '+%Y-%m-%d %H:%M:%S %z')"
	log "########################################################################"
}

run() {
	# run "title/cmd string" command args...
	title=$1
	shift
	log ""
	log "--- $title ---"
	log "\$ $*"
	# shellcheck disable=SC2068
	"$@" >>"$OUT" 2>&1 || log "[exit $?]"
}

run_sh() {
	# run a shell snippet for pipelines/globs
	title=$1
	shift
	log ""
	log "--- $title ---"
	log "\$ $*"
	sh -c "$*" >>"$OUT" 2>&1 || log "[exit $?]"
}

have() { command -v "$1" >/dev/null 2>&1; }

capture_common() {
	label=$1
	section "$label: basic state"
	run "$label: date" date
	run "$label: uptime" uptime || true
	run "$label: uname -a" uname -a
	run "$label: id" id

	section "$label: power/apm"
	if have apm; then
		run "$label: apm" apm || true
		run "$label: apm -v" apm -v || true
		run "$label: apm -L" apm -L || true
		run "$label: apm -A" apm -A || true
		run "$label: apm -l/-a/-b" sh -c 'apm -l 2>&1; echo "---"; apm -a 2>&1; echo "---"; apm -b 2>&1' || true
	else
		log "apm: not found"
	fi

	section "$label: sysctl (selected)"
	run_sh "$label: sysctl hw summary" 'sysctl hw.model hw.ncpu hw.ncpufound hw.smt hw.cpuspeed 2>&1 || true'
	run_sh "$label: sysctl machdep" 'sysctl machdep 2>&1 || true'
	run_sh "$label: sysctl hw.acpi/hw.sensors presence" 'sysctl hw.acpi 2>&1 || true; echo "---"; sysctl hw.sensors 2>&1 | sed -n "1,120p" || true'
	run_sh "$label: sysctl kern (version/time)" 'sysctl kern.ostype kern.osrelease kern.osrev kern.version kern.timecounter 2>&1 || true'

	section "$label: interrupts / CPU / processes"
	run "$label: vmstat -i" vmstat -i
	if have top; then
		# OpenBSD top: -b batch, -d 1 one display, -n non-interactive flags vary; try safe form
		run_sh "$label: top snapshot" 'top -b -d 1 2>&1 | sed -n "1,80p" || top -d 1 2>&1 | sed -n "1,80p" || true'
	fi
	run_sh "$label: ps snapshot" 'ps auxww 2>&1 | sed -n "1,120p" || ps -axww 2>&1 | sed -n "1,120p" || true'

	section "$label: kernel messages (current)"
	run_sh "$label: dmesg tail" 'dmesg 2>&1 | tail -n 250 || true'
	run_sh "$label: dmesg acpi/suspend/resume/lid/irq" 'dmesg 2>&1 | grep -Ei "acpi|suspend|resume|wakeup|wake|sleep|zzz|lid|apm|irq|cpu|hpet|lapic|ioapic|xhci|ehci|uhci|ohci|usb|iwm|azalia|inteldrm|i915|error|timeout|storm" || true'
}

capture_context_once() {
	section "context: boot/config (captured once)"
	if [ -r /var/run/dmesg.boot ]; then
		run_sh "dmesg.boot acpi/suspend/irq/device lines" 'grep -Ei "acpi|suspend|resume|wakeup|wake|sleep|zzz|lid|apm|irq|cpu|hpet|lapic|ioapic|xhci|ehci|uhci|ohci|usb|iwm|azalia|inteldrm|i915|pch|dwiic|tpm|error|timeout|storm" /var/run/dmesg.boot 2>&1 || true'
		run_sh "dmesg.boot tail" 'tail -n 200 /var/run/dmesg.boot 2>&1 || true'
	else
		log "/var/run/dmesg.boot: not readable"
	fi

	if have rcctl; then
		run_sh "rcctl apmd/xenodm/slaacd/dhcpleased state" 'rcctl ls on 2>&1 | grep -E "apmd|xenodm|slaacd|dhcpleased|sndiod|messagebus|hotplugd" || true'
	fi

	run_sh "/etc/apm contents" 'ls -la /etc/apm 2>&1 || true; for f in /etc/apm/*; do [ -f "$f" ] || continue; echo "----- $f -----"; sed -n "1,200p" "$f"; done 2>&1 || true'
	run_sh "/etc/rc.conf.local (if present)" 'if [ -f /etc/rc.conf.local ]; then sed -n "1,200p" /etc/rc.conf.local; else echo "missing"; fi'

	if have usbdevs; then
		run_sh "usbdevs -v" 'usbdevs -v 2>&1 || true'
	fi
}

echo "OpenBSD suspend/resume diagnostics"
echo "Report file: $OUT"
echo ""
echo "This will:"
echo "  1) capture a BASELINE snapshot"
echo "  2) ask you to suspend and resume the machine"
echo "  3) capture POST-RESUME snapshots (to catch CPU/IRQ storms)"
echo ""
echo "Tip: run from an X terminal or console session that will survive resume."
echo "     If the system becomes very slow after resume, wait a bit and continue."
echo ""

{
	log "OpenBSD suspend/resume diagnostic report"
	log "generated: $(date '+%Y-%m-%d %H:%M:%S %z')"
	log "output: $OUT"
} >"$OUT"

capture_context_once

printf 'Press Enter to capture BASELINE (before suspend)... '
read _dummy || true
capture_common "BASELINE"

section "instructions"
log "Suspend the machine now (close lid, or run: doas /usr/sbin/zzz / apm -z as appropriate)."
log "After resume, wait ~15-30 seconds (long enough for fan/CPU symptoms to show),"
log "then return to this terminal and press Enter to capture POST-RESUME state."

echo ""
echo "BASELINE captured."
echo "Now suspend the machine (close lid or: doas /usr/sbin/zzz)."
echo "After resume, wait ~15-30 seconds, then come back here."
printf 'Press Enter AFTER resume to capture POST-RESUME diagnostics... '
read _dummy || true

capture_common "POST-RESUME (immediate)"

section "POST-RESUME: follow-up samples"
log "Waiting 10 seconds before second interrupt/process snapshot..."
echo "Capturing follow-up sample in 10s..."
sleep 10 2>/dev/null || true
run "POST-RESUME (+10s): date" date
run "POST-RESUME (+10s): vmstat -i" vmstat -i
if have top; then
	run_sh "POST-RESUME (+10s): top snapshot" 'top -b -d 1 2>&1 | sed -n "1,80p" || top -d 1 2>&1 | sed -n "1,80p" || true'
fi
run_sh "POST-RESUME (+10s): ps snapshot" 'ps auxww 2>&1 | sed -n "1,120p" || ps -axww 2>&1 | sed -n "1,120p" || true'
run_sh "POST-RESUME (+10s): dmesg tail" 'dmesg 2>&1 | tail -n 250 || true'

section "notes"
cat >>"$OUT" <<'EOF'
Interpretation hints (for analysis):
- Compare BASELINE vs POST-RESUME vmstat -i totals and (+10s) to identify an interrupt/source incrementing rapidly.
- Check dmesg around resume for ACPI/wakeup/device errors or repeated messages.
- If a userspace process is pegging a CPU, top/ps snapshots should show it; if not, suspect kernel/interrupt activity.
EOF

echo ""
echo "Done. Report saved to: $OUT"
echo "Copy this file off the machine (e.g. via scp or removable media) for analysis."
