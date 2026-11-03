#!/bin/sh
# ---------------------------------------------------------------------------
#  ~/.config/spectrwm/bar.sh — status bar for spectrwm
#
#  spectrwm starts this script once and keeps it running: every line written
#  to stdout is displayed in the bar (bar_action_expand = 1 allows the
#  +@fg=n; colour markup below to work).  Keep it cheap — it ticks every
#  two seconds.
# ---------------------------------------------------------------------------

PATH=/usr/local/bin:/usr/X11R6/bin:/usr/bin:/bin:/sbin:/usr/sbin:$HOME/bin
export PATH

# Colour indices refer to bar_font_color[1] in ~/.spectrwm.conf
#   0 = amber   1 = foreground   2 = dim   3 = red
AMBER='+@fg=0;'
FG='+@fg=1;'
DIM='+@fg=2;'
RED='+@fg=3;'
SEP="${DIM}· ${FG}"

# join_segments a b c ... — join non-empty segments with the separator
join_segments() {
	out=
	for seg in "$@"; do
		[ -n "$seg" ] || continue
		if [ -n "$out" ]; then
			out="$out$SEP$seg"
		else
			out=$seg
		fi
	done
	printf '%s' "$out"
}

volume_seg() {
	level=$(sndioctl -n output.level 2>/dev/null | sed -n 1p)
	[ -n "$level" ] || return 0
	pct=$(awk -v l="$level" 'BEGIN { printf "%d", l * 100 + 0.5 }')
	if [ "$(sndioctl -n output.mute 2>/dev/null | sed -n 1p)" = 1 ]; then
		printf '%svol muted%s' "$RED" "$FG"
	else
		printf '%svol %s%%%s' "$DIM" "$pct" "$FG"
	fi
}

battery_seg() {
	# 255 means "no battery": desktops and VMs should not show one.
	[ "$(apm -a 2>/dev/null)" = 255 ] && return 0
	pct=$(apm -l 2>/dev/null) || return 0
	case $pct in ''|*[!0-9]*) return 0 ;; esac
	ac=$(apm -a 2>/dev/null)
	if [ "$ac" = 1 ]; then
		printf '%sbat %s%% ac%s' "$AMBER" "$pct" "$FG"
	elif [ "$pct" -le 15 ]; then
		printf '%sbat %s%%%s' "$RED" "$pct" "$FG"
	else
		printf '%sbat %s%%%s' "$DIM" "$pct" "$FG"
	fi
}

net_seg() {
	ssid=$(ifconfig iwm0 2>/dev/null |
		sed -n 's/.*ieee80211: nwid \(.*\) chan .*/\1/p' | sed -n 1p)
	if [ -n "$ssid" ]; then
		# bar_action_expand processes +sequences in our output, so a '+'
		# inside a network name has to be escaped as '++'.
		ssid=$(printf '%s' "$ssid" | sed 's/+/++/g')
		printf '%swifi %s%s' "$DIM" "$ssid" "$FG"
		return 0
	fi
	# em0 on the T480s, vio0 in the rehearsal VM, re0 on USB/Thunderbolt NICs.
	for i in em0 vio0 re0; do
		if ifconfig "$i" 2>/dev/null | grep -q 'status: active'; then
			printf '%swired %s%s' "$DIM" "$i" "$FG"
			return 0
		fi
	done
	printf '%soffline%s' "$DIM" "$FG"
}

temp_seg() {
	t=$(sysctl -n hw.sensors.cpu0.temp0 2>/dev/null) || return 0
	t=${t%%.*}
	case $t in ''|*[!0-9]*) return 0 ;; esac
	if [ "$t" -ge 85 ]; then
		printf '%s%s°C%s' "$RED" "$t" "$FG"
	else
		printf '%s%s°C%s' "$DIM" "$t" "$FG"
	fi
}

music_seg() {
	command -v mpc >/dev/null 2>&1 || return 0
	song=$(mpc current 2>/dev/null) || return 0
	[ -n "$song" ] || return 0
	# Trim long titles and escape the + used by the bar markup.
	song=$(printf '%s' "$song" | cut -c1-40 | sed 's/+/++/g')
	if mpc status 2>/dev/null | grep -q '\[playing\]'; then
		printf '%s▶ %s%s' "$AMBER" "$song" "$FG"
	else
		printf '%s⏸ %s%s' "$DIM" "$song" "$FG"
	fi
}

# Battery, network, temperature and the current track move slowly: refresh
# them every 20s and keep the clock and volume on every tick.
net=''
bat=''
temp=''
music=''
tick=0

while :; do
	if [ "$tick" -eq 0 ]; then
		net=$(net_seg)
		bat=$(battery_seg)
		temp=$(temp_seg)
		music=$(music_seg)
	fi

	line=$(join_segments "$net" "$bat" "$temp" "$(volume_seg)" "$music" \
		"${AMBER}$(date '+%a %d %b  %H:%M')${FG}")
	printf '%s\n' "$line"

	tick=$(( (tick + 1) % 10 ))
	sleep 2
done
