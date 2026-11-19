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

saved_audio_dev() {
	d=$(sed -n '1p' "$HOME/.config/audio-device" 2>/dev/null)
	case ${d:-} in ''|default) printf '%s' "" ;; *) printf '%s' "$d" ;; esac
}

volume_seg() {
	dev=$(saved_audio_dev)
	if [ -n "$dev" ]; then
		level=$(sndioctl -f "$dev" -n output.level 2>/dev/null | sed -n 1p)
		mute=$(sndioctl -f "$dev" -n output.mute 2>/dev/null | sed -n 1p)
	else
		level=$(sndioctl -n output.level 2>/dev/null | sed -n 1p)
		mute=$(sndioctl -n output.mute 2>/dev/null | sed -n 1p)
	fi
	# fallback
	if [ -z "$level" ]; then
		level=$(sndioctl -n output.level 2>/dev/null | sed -n 1p)
		[ -n "$mute" ] || mute=$(sndioctl -n output.mute 2>/dev/null | sed -n 1p)
	fi
	[ -n "$level" ] || return 0
	pct=$(awk -v l="$level" 'BEGIN { printf "%d", l * 100 + 0.5 }')
	case $mute in 1)
		printf '%svol muted%s' "$RED" "$FG"
		;;
	*)
		printf '%svol %s%%%s' "$DIM" "$pct" "$FG"
		;;
	esac
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
		ssid=$(printf '%s' "$ssid" | sed 's/+/++/g')
		printf '%swifi %s%s' "$DIM" "$ssid" "$FG"
		return 0
	fi
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
	song=$(printf '%s' "$song" | cut -c1-40 | sed 's/+/++/g')
	if mpc status 2>/dev/null | grep -q '\[playing\]'; then
		printf '%s▶ %s%s' "$AMBER" "$song" "$FG"
	else
		printf '%s⏸ %s%s' "$DIM" "$song" "$FG"
	fi
}

audio_seg() {
	short=$(sed -n '1p' "$HOME/.config/audio-device-short" 2>/dev/null)
	if [ -z "$short" ]; then
		name=$(sed -n '1p' "$HOME/.config/audio-device-name" 2>/dev/null)
		dev=$(saved_audio_dev)
		[ -n "$dev" ] || dev=default
		lc=$(printf '%s %s' "$name" "$dev" | tr 'A-Z' 'a-z')
		case $lc in
		*uaudio*|*usb*|*dac*|*headset*|*interface*) short="USB" ;;
		*dock*) short="Dock" ;;
		*hdmi*|*displayport*) short="HDMI" ;;
		*azalia*|*hdafg*|*hdaudio*|*speaker*) short="Int" ;;
		*default*) short="Default" ;;
		*)
			case $dev in
			snd/*) short="snd${dev#snd/}" ;;
			*) short="Audio" ;;
			esac
			;;
		esac
	fi
	[ -n "$short" ] || return 0
	short=$(printf '%s' "$short" | cut -c1-10 | sed 's/+/++/g')
	printf '%s%s%s' "$DIM" "$short" "$FG"
}

# Battery, network, temperature and the current track move slowly: refresh
# them every 20s and keep clock/volume/audio on every tick.
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
	audio=$(audio_seg)

	line=$(join_segments "$net" "$bat" "$temp" "$(volume_seg)" "$audio" "$music" \
		"${AMBER}$(date '+%a %d %b  %H:%M')${FG}")
	printf '%s\n' "$line"

	tick=$(( (tick + 1) % 10 ))
	sleep 2
done
