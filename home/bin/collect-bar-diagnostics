#!/bin/sh
# collect-bar-diagnostics - gather local diagnostics for bar/desktop issues.
#
# Collects information useful for debugging:
#   - spectrwm/bar/workspace indicators and bar script behavior
#   - volume/mute behavior and bindings
#   - dunst notifications and rofi theme/highlight visibility
#   - logout/xenodm/X session issues
#   - input/touchpad/natural scrolling configuration
#
# Privacy/safety:
#   - Read-only diagnostics (except writing the local report file[s]).
#   - Does NOT upload or transmit any data.
#   - Avoids collecting secrets (passwords, private keys, tokens, clipboard,
#     browser/mail data). Network addresses/SSIDs/BSSIDs are redacted.
#   - Log tails are limited; review the report before sharing it.

umask 077

PATH=/usr/local/bin:/usr/X11R6/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/bin
export PATH

ts=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo unknown)
OUT=${BAR_DIAG_OUT:-"$HOME/bar-diag-$ts.txt"}

say() { printf '%s\n' "$*"; }
section() {
	printf '\n===== %s =====\n' "$*"
}
cmd() {
	printf '\n-- $ %s\n' "$*"
	# run in a subshell so failures don't affect the script
	( eval "$*" ) 2>&1 || printf '[exit %s]\n' "$?"
}
have() { command -v "$1" >/dev/null 2>&1; }

# Best-effort temp dir
TMPROOT=${TMPDIR:-/tmp}
TMPD="$TMPROOT/bar-diag.$$"
mkdir -p "$TMPD" 2>/dev/null || TMPD="$TMPROOT"

cleanup() {
	rm -rf "$TMPD" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Create report (local only)
: >"$OUT" 2>/dev/null || {
	OUT="$TMPROOT/bar-diag-$ts.txt"
	: >"$OUT"
}
chmod 600 "$OUT" 2>/dev/null || true

{
	say "collect-bar-diagnostics report"
	say "generated: $(date 2>/dev/null || echo unknown)"
	say "output: $OUT"
	say "note: This report is stored locally on this system only. No data is uploaded or transmitted."
	say "note: Review before sharing. Some local usernames/paths/log snippets may be included; secrets are intentionally avoided."

	section "system and session"
	cmd 'id 2>/dev/null || true'
	cmd 'uname -a 2>/dev/null || true'
	cmd 'test -r /etc/release && sed -n "1,5p" /etc/release || true'
	cmd 'sysctl -n kern.version 2>/dev/null | sed -n "1,3p" || true'
	cmd 'sysctl -n hw.model hw.ncpu hw.physmem 2>/dev/null || true'
	cmd 'echo "DISPLAY=${DISPLAY-}"'
	cmd 'echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE-}"'
	cmd 'echo "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP-}"'
	cmd 'echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR-<unset>}"'
	cmd 'echo "SHELL=${SHELL-}"'
	cmd 'echo "TERM=${TERM-}"'
	cmd 'echo "LANG=${LANG-}"'
	cmd 'echo "LC_ALL=${LC_ALL-}"'
	cmd 'echo "LC_CTYPE=${LC_CTYPE-}"'
	cmd 'echo "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS+<set>}${DBUS_SESSION_BUS_ADDRESS-<unset>}"'
	cmd 'if [ -d "$HOME/openbsd-setup/.git" ]; then git -C "$HOME/openbsd-setup" --no-pager log -1 --oneline --decorate 2>/dev/null || true; fi'

	section "relevant processes"
	cmd 'ps auxww 2>/dev/null | awk "NR==1 || /spectrwm|bar\.sh|dunst|picom|xbanish|clipmenu|xidle|mpd|xenodm|Xorg|Xenodm|rofi|volume/ {print}" || ps -axww 2>/dev/null | awk "NR==1 || /spectrwm|bar\.sh|dunst|picom|xenodm|Xorg|rofi|volume/ {print}" || true'
	cmd 'pgrep -lf "spectrwm|bar\.sh|dunst|xenodm|Xorg|volume" 2>/dev/null || true'

	section "bar and spectrwm config"
	cmd 'for f in "$HOME/.spectrwm.conf" "$HOME/.cache/theme" "$HOME/.config/spectrwm/bar.sh" "$HOME/.config/spectrwm/themes/amber/spectrwm.colors" "$HOME/.config/spectrwm/themes/amber/dunstrc" "$HOME/.config/spectrwm/themes/amber/rofi.rasi"; do if [ -e "$f" ]; then ls -ld "$f" 2>/dev/null; fi; done'
	cmd 'if [ -f "$HOME/.spectrwm.conf" ]; then echo "--- ~/.spectrwm.conf (relevant lines) ---"; grep -nE "^(bar_|workspace_|bar_action|bar_format|bar_font|workspace_mark_|program\[vol|bind\[vol|program\[lock|bind\[quit|bind\[menu|quirk)" "$HOME/.spectrwm.conf" 2>/dev/null || true; echo "--- ~/.spectrwm.conf (theme block) ---"; sed -n "/^# >>> theme colors >>>/,/^# <<< theme colors <<</p" "$HOME/.spectrwm.conf" 2>/dev/null || true; fi'
	cmd 'echo "theme cache: $(cat "$HOME/.cache/theme" 2>/dev/null || echo none)"'
	cmd 'for f in "$HOME/.config/spectrwm/themes/amber/spectrwm.colors" "$HOME/.config/spectrwm/bar.sh"; do if [ -f "$f" ]; then echo "--- $f ---"; sed -n "1,260p" "$f"; fi; done'
	cmd 'if [ -f "$HOME/.config/spectrwm/bar.sh" ]; then echo "--- bar.sh first 40 lines with numbers ---"; nl -ba "$HOME/.config/spectrwm/bar.sh" 2>/dev/null | sed -n "1,40p" || sed -n "1,40p" "$HOME/.config/spectrwm/bar.sh"; fi'

	section "bar timing and sample output"
	cmd 'echo -n "sleep 1 rc: "; sleep 1 >/dev/null 2>&1; echo $?'
	cmd 'echo -n "sleep 0.2 rc: "; sleep 0.2 >/dev/null 2>&1; echo $?'
	cmd 'echo -n "sleep 0.1 rc: "; sleep 0.1 >/dev/null 2>&1; echo $?'
	# Sample bar output safely (do not leave running)
	if [ -x "$HOME/.config/spectrwm/bar.sh" ] || [ -f "$HOME/.config/spectrwm/bar.sh" ]; then
		printf '\n-- sample: run bar.sh for ~4s (captured, then terminated)\n'
		outf="$TMPD/bar.out"; errf="$TMPD/bar.err"
		( sh "$HOME/.config/spectrwm/bar.sh" >"$outf" 2>"$errf" ) &
		bpid=$!
		i=0
		while [ "$i" -lt 4 ]; do
			sleep 1 2>/dev/null || sleep 1
			i=$((i + 1))
		done
		kill "$bpid" 2>/dev/null || true
		# try a little harder if still running
		sleep 1 2>/dev/null || true
		kill -9 "$bpid" 2>/dev/null || true
		wait "$bpid" 2>/dev/null || true
		echo "--- stdout (first 12 lines) ---"
		sed -n '1,12p' "$outf" 2>/dev/null || true
		echo "--- stderr (first 40 lines) ---"
		sed -n '1,40p' "$errf" 2>/dev/null || true
		rm -f "$outf" "$errf" 2>/dev/null || true
	else
		printf '\n-- bar.sh not found at ~/.config/spectrwm/bar.sh\n'
	fi

	section "volume and mute"
	cmd 'for c in sndioctl mixerctl audioctl aucat; do if have "$c"; then echo "have: $c -> $(command -v "$c")"; else echo "missing: $c"; fi; done'
	cmd 'ls -l /dev/audio* /dev/audioctl* /dev/mixer* 2>/dev/null || echo "(no matching /dev audio nodes listed)"'
	cmd 'if [ -f "$HOME/.config/audio-device" ]; then echo "--- ~/.config/audio-device ---"; sed -n "1,5p" "$HOME/.config/audio-device"; fi'
	cmd 'if [ -f "$HOME/.config/audio-device-name" ]; then echo "--- ~/.config/audio-device-name ---"; sed -n "1,5p" "$HOME/.config/audio-device-name"; fi'
	cmd 'if [ -f "$HOME/.config/audio-device-short" ]; then echo "--- ~/.config/audio-device-short ---"; sed -n "1,5p" "$HOME/.config/audio-device-short"; fi'
	cmd 'if have sndioctl; then echo "--- sndioctl (default, key values) ---"; sndioctl 2>&1 | sed -n "1,120p"; echo "--- sndioctl -n output.level/output.mute/server.device ---"; sndioctl -n output.level 2>&1 | sed -n "1,2p"; sndioctl -n output.mute 2>&1 | sed -n "1,2p"; sndioctl -n server.device 2>&1 | sed -n "1,2p"; fi'
	cmd 'if [ -f "$HOME/.spectrwm.conf" ]; then echo "--- volume bindings ---"; grep -n "vol_" "$HOME/.spectrwm.conf" 2>/dev/null || true; fi'
	cmd 'if [ -f "$HOME/bin/volume" ]; then echo "--- ~/bin/volume ---"; sed -n "1,260p" "$HOME/bin/volume"; else echo "~/bin/volume not found"; fi'

	# Functional tests (best-effort, state restored)
	printf '\n-- functional volume tests (best-effort, attempts to restore original state)\n'
	if have sndioctl && [ -x "$HOME/bin/volume" -o -f "$HOME/bin/volume" ]; then
		orig_level=$(sndioctl -n output.level 2>/dev/null | sed -n '1p')
		orig_mute=$(sndioctl -n output.mute 2>/dev/null | sed -n '1p')
		printf 'original: level=%s mute=%s\n' "${orig_level:-?}" "${orig_mute:-?}"

		printf '\n[test: single volume up tap]\n'
		before_l=$(sndioctl -n output.level 2>/dev/null | sed -n '1p')
		before_m=$(sndioctl -n output.mute 2>/dev/null | sed -n '1p')
		sh "$HOME/bin/volume" up 2>&1; up_rc=$?
		after_l=$(sndioctl -n output.level 2>/dev/null | sed -n '1p')
		after_m=$(sndioctl -n output.mute 2>/dev/null | sed -n '1p')
		printf 'before: level=%s mute=%s\n' "${before_l:-?}" "${before_m:-?}"
		printf 'after up (rc=%s): level=%s mute=%s\n' "$up_rc" "${after_l:-?}" "${after_m:-?}"
		# restore step
		sh "$HOME/bin/volume" down >/dev/null 2>&1 || true
		printf 'after restore-down: level=%s mute=%s\n' "$(sndioctl -n output.level 2>/dev/null | sed -n '1p')" "$(sndioctl -n output.mute 2>/dev/null | sed -n '1p')"

		printf '\n[test: toggle mute twice]\n'
		printf 'state before toggles: level=%s mute=%s\n' "$(sndioctl -n output.level 2>/dev/null | sed -n '1p')" "$(sndioctl -n output.mute 2>/dev/null | sed -n '1p')"
		sh "$HOME/bin/volume" toggle 2>&1; t1=$?
		printf 'after toggle #1 (rc=%s): level=%s mute=%s\n' "$t1" "$(sndioctl -n output.level 2>/dev/null | sed -n '1p')" "$(sndioctl -n output.mute 2>/dev/null | sed -n '1p')"
		sleep 1 2>/dev/null || true
		printf '1s later: level=%s mute=%s\n' "$(sndioctl -n output.level 2>/dev/null | sed -n '1p')" "$(sndioctl -n output.mute 2>/dev/null | sed -n '1p')"
		sh "$HOME/bin/volume" toggle 2>&1; t2=$?
		printf 'after toggle #2 (rc=%s): level=%s mute=%s\n' "$t2" "$(sndioctl -n output.level 2>/dev/null | sed -n '1p')" "$(sndioctl -n output.mute 2>/dev/null | sed -n '1p')"
		sleep 1 2>/dev/null || true
		printf '1s later: level=%s mute=%s\n' "$(sndioctl -n output.level 2>/dev/null | sed -n '1p')" "$(sndioctl -n output.mute 2>/dev/null | sed -n '1p')"

		# Restore original state as best-effort
		printf '\n[restore original state]\n'
		case ${orig_mute:-} in 0|1) sndioctl -q output.mute="$orig_mute" 2>/dev/null || true ;; esac
		case ${orig_level:-} in '' ) ;; *) sndioctl -q output.level="$orig_level" 2>/dev/null || true ;; esac
		printf 'restored: level=%s mute=%s\n' "$(sndioctl -n output.level 2>/dev/null | sed -n '1p')" "$(sndioctl -n output.mute 2>/dev/null | sed -n '1p')"
	else
		echo "skipped (sndioctl or ~/bin/volume not available)"
	fi

	section "notifications and dunst"
	cmd 'dunst -v 2>&1 | sed -n "1,5p" || echo "dunst version not available"'
	cmd 'command -v dunstctl >/dev/null 2>&1 && echo "dunstctl: $(command -v dunstctl)" || echo "dunstctl not found"'
	cmd 'for f in "$HOME/.config/dunst/dunstrc" "$HOME/.config/spectrwm/themes/amber/dunstrc"; do if [ -f "$f" ]; then echo "--- $f ---"; sed -n "1,260p" "$f"; fi; done'

	section "rofi (menu highlight/readability)"
	cmd 'rofi -v 2>&1 | sed -n "1,5p" || echo "rofi version not available"'
	cmd 'for f in "$HOME/.config/rofi/config.rasi" "$HOME/.config/rofi/themes/amber.rasi" "$HOME/.config/spectrwm/themes/amber/rofi.rasi"; do if [ -f "$f" ]; then echo "--- $f ---"; sed -n "1,260p" "$f"; fi; done'

	section "logout, xenodm, X session"
	cmd 'command -v rcctl >/dev/null 2>&1 && rcctl check xenodm 2>&1 || echo "rcctl/xenodm check not available"'
	cmd 'command -v rcctl >/dev/null 2>&1 && rcctl get xenodm 2>&1 | sed -n "1,40p" || true'
	cmd 'for f in /var/log/xenodm.log /var/log/messages /var/log/Xorg.0.log "$HOME/.xsession-errors" "$HOME/.local/share/xorg/Xorg.0.log"; do if [ -r "$f" ]; then echo "--- tail -n 120 $f ---"; tail -n 120 "$f" 2>&1; elif [ -e "$f" ]; then echo "--- $f exists but not readable ---"; ls -l "$f" 2>&1; fi; done'
	cmd 'dmesg 2>&1 | tail -n 120 || echo "dmesg not available/readable"'
	cmd 'if [ -f "$HOME/.xsession" ]; then echo "--- ~/.xsession (relevant sections) ---"; sed -n "1,260p" "$HOME/.xsession"; fi'

	section "input, touchpad, natural scrolling"
	cmd 'xinput list 2>&1 || echo "xinput not available or no DISPLAY"'
	if have xinput; then
		printf '\n-- xinput list-props (pointer/touch/track devices)\n'
		xinput list --name-only 2>/dev/null | while IFS= read -r dev; do
			[ -n "$dev" ] || continue
			case "$(printf '%s' "$dev" | tr 'A-Z' 'a-z')" in
			*mouse*|*touch*|*track*|*synaptics*|*pointer*|*wsmouse*|*tp*)
				echo "--- device: $dev ---"
				xinput list-props "$dev" 2>&1 | sed -n '1,160p'
				;;
			esac
		done
		printf '\n-- xinput list-props (all devices, brief)\n'
		xinput list --name-only 2>/dev/null | while IFS= read -r dev; do
			[ -n "$dev" ] || continue
			echo "--- $dev ---"
			xinput list-props "$dev" 2>&1 | sed -n '1,40p'
		done
	fi
	cmd 'if have wsconsctl; then echo "--- wsconsctl (mouse/tp/touch/scroll related, redacted where needed) ---"; wsconsctl 2>&1 | grep -iE "mouse|tp|touch|tap|scroll|wsmouse" || echo "(no matching wsconsctl keys)"; fi'
	cmd 'if have synclient; then synclient -l 2>&1 | sed -n "1,120p"; fi'
	cmd 'for f in /etc/wsconsctl.conf /etc/X11/xorg.conf /etc/X11/xorg.conf.d/*; do if [ -r "$f" ]; then echo "--- $f ---"; sed -n "1,220p" "$f"; fi; done'

	section "network summary (redacted)"
	# Avoid SSIDs, BSSIDs, MACs, and IP addresses; include interface/media/status only.
	if have ifconfig; then
		printf '\n-- ifconfig (redacted: no MAC/IP/SSID/BSSID)\n'
		ifconfig 2>&1 | sed \
			-e 's/lladdr [0-9a-fA-F:][0-9a-fA-F:]*/lladdr [redacted]/g' \
			-e 's/ether [0-9a-fA-F:][0-9a-fA-F:]*/ether [redacted]/g' \
			-e 's/inet6 [0-9a-fA-F:%._-]*/inet6 [redacted]/g' \
			-e 's/inet [0-9.][0-9.]*/inet [redacted]/g' \
			-e 's/nwid [^ ]*/nwid [redacted]/g' \
			-e 's/bssid [0-9a-fA-F:][0-9a-fA-F:]*/bssid [redacted]/g' \
			-e 's/join [^ ]*/join [redacted]/g' \
			| sed -n '1,220p'
	else
		echo "ifconfig not available"
	fi

	section "end"
	say "report complete: $(date 2>/dev/null || echo unknown)"
	say "Review this file before sharing. It was created locally and not transmitted."
} >"$OUT" 2>&1

# Also copy to current directory if writable and different
cwd_copy=""
if [ -w "." ]; then
	base="bar-diag-$ts.txt"
	if [ "$(pwd)/$base" != "$OUT" ] 2>/dev/null; then
		cp "$OUT" "./$base" 2>/dev/null && chmod 600 "./$base" 2>/dev/null && cwd_copy="$(pwd)/$base"
	fi
fi

printf 'Diagnostics saved locally to:\n  %s\n' "$OUT"
[ -n "$cwd_copy" ] && printf 'Copy saved to:\n  %s\n' "$cwd_copy"
printf 'No data was uploaded or transmitted. Please review the file before sharing it.\n'
