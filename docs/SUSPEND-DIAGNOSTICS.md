# Suspend/resume diagnostics (OpenBSD T480s) — focused capture

Goal: collect the minimum data needed to diagnose the deal-breaker issue where,
after suspend/resume (e.g. lid close/open), CPU usage pegs near 100% (often an
interrupt/IRQ storm), the fan spins up, and battery drains.

**Example observation (tested ThinkPad T480s-class hardware):** on one system (BIOS `N22ET85P 1.62`, OpenBSD 8.0 amd64 `GENERIC.MP` with `apmd -A`), S3 resume triggered a post-resume ACPI GPE 0x16 storm on `irq48/acpi0` (~1548 interrupts/s across baseline/immediate/+10s samples), with fan spin-up, temperature/load increase, and no userspace runaway. Reproduced in an isolated test (battery only, no dock/USB/power attached). **Hibernate (`ZZZ`) worked reliably** on that setup, so `machdep.lidaction=2` (lid close hibernates) was used as a workaround. S3 root-cause fixes may depend on BIOS/firmware settings or newer OpenBSD; avoid `zzz`/S3 on affected hardware unless re-testing.

This is **read-only** data collection. It does not change system configuration.

## What to run

On the target OpenBSD machine, use the updated repo copy and run:

```sh
cd ~/openbsd-setup   # or wherever you copied the repo
sh ./scripts/collect-suspend-diagnostics.sh
```

Optional: specify an output path (useful if you want the report written directly
to a mounted USB location):

```sh
sh ./scripts/collect-suspend-diagnostics.sh /path/to/suspend-diag.txt
```

By default the report is written to:
`$HOME/suspend-diag-YYYYmmdd-HHMMSS.txt`

## Flow

1. Script captures **boot/context** info and a **BASELINE** snapshot (before suspend).
2. You suspend/hibernate the machine (close the lid, `doas /usr/sbin/zzz` for S3,
   or `doas /usr/sbin/ZZZ` for hibernate). Record which action was used.
3. Resume the machine and wait ~15–30 seconds so the symptom (high CPU/fan/heat,
   if present) has time to appear.
4. Return to the script and press Enter to capture **POST-RESUME** snapshots
   (immediate and +10s), including `vmstat -i`, process snapshots, and recent `dmesg`.

If the system is extremely slow/unresponsive after resume, capture what you can
and note what happened. If possible, a manual `vmstat -i` and `dmesg | tail` run
after resume (and saved/copied) is also helpful.

## Current workaround (confirmed)

- **Hibernate:** `doas /usr/sbin/ZZZ` works reliably on this T480s (confirmed).
- **Lid policy:** repo sets `machdep.lidaction=2` in `/etc/sysctl.conf` so lid
  close **hibernates** (`apmd` required/enabled). Manual hibernate via `ZZZ` or
  launcher also works. **Avoid S3 (`zzz`)** unless re-testing — it still triggers
  the GPE 0x16 `acpi0` storm on BIOS 1.62/OpenBSD 8.0.

## Re-testing S3 (only if pursuing a fix)

If you update BIOS beyond `N22ET85P 1.62`, change ACPI/wake/Thunderbolt/power
settings, or try a newer OpenBSD release/snapshot, you can re-test S3 and compare:

1. **S3 with wireless quiesced:** `doas ifconfig iwm0 down`, then `doas /usr/sbin/zzz`;
   after resume confirm whether the `acpi0`/GPE 0x16 storm is absent (repo's
   `/etc/apm/resume` attempts to restore interfaces/nudge `dhcpleased`). Report
   `vmstat -i | grep acpi0` baseline vs post-resume/+10s and fan/CPU/load.
2. **Lid-S3 test (temporary):** `doas sysctl machdep.lidaction=1` to test lid-close
   S3, revert with `doas sysctl machdep.lidaction=2` after (and keep `2` in
   `/etc/sysctl.conf` unless S3 is confirmed fixed).
3. If a future S3 fix is confirmed, set `machdep.lidaction=1` (suspend) or `2`
   (hibernate) as preferred and update the repo config accordingly.

## What the report includes

- System/context: `uname -a`, uptime, relevant `sysctl` (hw/machdep/acpi/sensors),
  apmd/rc state, `/etc/apm` contents, selected boot `dmesg` lines.
- Power state: `apm` / `apm -v` output (when available).
- Interrupts and load: `vmstat -i` (baseline vs post-resume/+10s), `top`/`ps`
  snapshots to distinguish interrupt/kernel issues from a runaway userspace process.
- Kernel messages: recent `dmesg` and filtered suspend/resume/acpi/irq/device lines.

## Share the result

Copy the generated report off the affected machine for analysis (USB drive, `scp`, or paste relevant excerpts). Include which test/action was performed (`ZZZ`, `zzz`, lid), whether dock/power/USB were attached, and whether hibernate or pre-suspend wireless quiesce avoided the storm. Use the report to identify the interrupt/device or subsystem responsible and to guide a targeted fix or upstream/BIOS report.
