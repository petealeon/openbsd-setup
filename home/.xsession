#!/bin/sh
# ---------------------------------------------------------------------------
#  ~/.xsession — X session started by xenodm (or by `startx` via ~/.xinitrc)
#
#  Order matters: the D-Bus session first (dunst and libnotify need it), then
#  theme resources, then the helpers the window manager expects to be running.
# ---------------------------------------------------------------------------

# Re-exec under a private session bus; a no-op when dbus is absent.
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
	exec dbus-run-session -- "$0" "$@"
fi

PATH="$HOME/bin:/usr/local/bin:/usr/X11R6/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

# Ensure interactive ksh shells (e.g. terminals) load ~/.kshrc for prompt,
# aliases, colors and persistent history.
export ENV="$HOME/.kshrc"

# Locale and terminal defaults for X session apps (btop, ncmpcpp, etc.).
export LANG="${LANG:-en_US.UTF-8}"
export LC_CTYPE="${LC_CTYPE:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
if [ -z "${TERM:-}" ] || [ "$TERM" = "dumb" ]; then
	if infocmp st-256color >/dev/null 2>&1; then
		export TERM=st-256color
	else
		export TERM=xterm-256color
	fi
fi

# Persisted audio output hint (set by ~/bin/audio-output).
if [ -z "${AUDIODEVICE:-}" ] && [ -f "$HOME/.config/audio-device" ]; then
	AUDIODEVICE=$(sed -n '1p' "$HOME/.config/audio-device" 2>/dev/null)
	case ${AUDIODEVICE:-} in ''|default) ;; *) export AUDIODEVICE ;; esac
fi

# Clipboard history (clipmenu) uses rofi as its picker.
export CM_LAUNCHER=rofi
export CM_SELECTIONS="clipboard"
export CM_HISTLENGTH=100
export CM_DIR="$HOME/.cache/clipmenu"

# ── X resources and screensaver ─────────────────────────────────────────────
xrdb -merge "$HOME/.Xresources" 2>/dev/null
# wsfb (the VM's framebuffer driver) has no DPMS extension; the intel driver
# on the T480s does, so these are best-effort rather than fatal.
xset s off 2>/dev/null || true
xset +dpms 2>/dev/null || true
xset dpms 600 900 1200 2>/dev/null || true
xset b off 2>/dev/null || true

# ── input: touchscreen and trackpad ─────────────────────────────────────────
# The wscons tunables themselves live in /etc/wsconsctl.conf (applied at boot).
# Here we configure X/libinput devices for a "smooth, natural" feel similar to
# modern desktops: natural scrolling, tap-to-click, tap drag, and sane accel.
# xinput works with both the xf86-input-libinput and synaptics-era device
# properties; commands fail harmlessly if a property is unsupported.
if command -v xinput >/dev/null 2>&1; then
	out=$(xrandr --query 2>/dev/null |
		sed -n 's/^\([^ ]*\) connected primary.*/\1/p' | sed -n 1p)
	[ -n "$out" ] || out=$(xrandr --query 2>/dev/null |
		sed -n 's/^\([^ ]*\) connected.*/\1/p' | sed -n 1p)
	if [ -n "$out" ]; then
		xinput list --name-only 2>/dev/null |
			grep -i -e touch -e wacom |
			while IFS= read -r dev; do
				xinput map-to-output "$dev" "$out" >/dev/null 2>&1 || true
			done
	fi

	# Apply pointer tuning to trackpads and the TrackPoint.
	xinput list --name-only 2>/dev/null | while IFS= read -r dev; do
		case $(printf '%s' "$dev" | tr 'A-Z' 'a-z') in
		*touchpad*|*trackpad*|*synaptics*|*trackpoint*|*pointing*)
			# libinput: natural scrolling, tap-to-click, tap-drag, accel
			xinput set-prop "$dev" "libinput Natural Scrolling Enabled" 1 \
				>/dev/null 2>&1 || true
			xinput set-prop "$dev" "libinput Tapping Enabled" 1 \
				>/dev/null 2>&1 || true
			xinput set-prop "$dev" "libinput Tapping Drag Enabled" 1 \
				>/dev/null 2>&1 || true
			xinput set-prop "$dev" "libinput Disable While Typing Enabled" 1 \
				>/dev/null 2>&1 || true
			xinput set-prop "$dev" "libinput Accel Speed" 0.25 \
				>/dev/null 2>&1 || true
			# synaptics fallback properties (if present)
			xinput set-prop "$dev" "Synaptics Tap Action" 1 1 1 1 1 1 2 3 \
				>/dev/null 2>&1 || true
			xinput set-prop "$dev" "Synaptics Scrolling Distance" -30 -30 \
				>/dev/null 2>&1 || true
			xinput set-prop "$dev" "Synaptics Palm Detection" 1 \
				>/dev/null 2>&1 || true
			;;
		esac
	done
fi
# wscons fallback (harmless if unsupported): try natural scrolling on the
# touchpad device if exposed via wsconsctl.
if command -v wsconsctl >/dev/null 2>&1; then
	for p in mouse.reverse_scrolling mouse.tp.reverse_scrolling \
		mouse.tp.scaling mouse.tp.tapping; do
		case $p in
		*reverse_scrolling) wsconsctl "$p=1" >/dev/null 2>&1 || true ;;
		*tapping)           wsconsctl "$p=1" >/dev/null 2>&1 || true ;;
		esac
	done
fi

# ── wallpaper ───────────────────────────────────────────────────────────────
theme=$(cat "$HOME/.cache/theme" 2>/dev/null)
[ -n "$theme" ] || theme=amber
wall="$HOME/Pictures/wallpapers/$theme.png"
[ -f "$wall" ] || wall="$HOME/.config/spectrwm/themes/$theme/wallpaper.png"
# sensible fallback for the cwm trial (and first runs)
[ -f "$wall" ] || wall="$HOME/Pictures/amber-wall.png"
if [ -f "$wall" ] && command -v feh >/dev/null 2>&1; then
	feh --no-fehbg --bg-fill "$wall" >/dev/null 2>&1
else
	xsetroot -solid "#0f0e0c" 2>/dev/null
fi
xsetroot -cursor_name left_ptr 2>/dev/null

# ── helpers ─────────────────────────────────────────────────────────────────
# Compositor: st transparency and the subtle window shadows.
command -v picom >/dev/null 2>&1 &&
	picom --config "$HOME/.config/picom/picom.conf" >/dev/null 2>&1 &
# Notifications.
command -v dunst >/dev/null 2>&1 && dunst >/dev/null 2>&1 &
# Clipboard watcher.
command -v clipmenud >/dev/null 2>&1 && clipmenud >/dev/null 2>&1 &
# Hide the pointer while typing.
command -v xbanish >/dev/null 2>&1 && xbanish >/dev/null 2>&1 &

# Music daemon, so the bar can show what is playing.
if command -v mpd >/dev/null 2>&1 && ! mpc ping >/dev/null 2>&1; then
	for d in "$HOME/Music" "$HOME/.local/share/mpd/playlists" "$HOME/.local/share/mpd" "$HOME/.local/share/lyrics"; do
		mkdir -p "$d" 2>/dev/null || true
	done
	# Clear stale pid if present
	if [ -f "$HOME/.local/share/mpd/pid" ]; then
		oldpid=$(sed -n '1p' "$HOME/.local/share/mpd/pid" 2>/dev/null)
		case $oldpid in
		''|*[!0-9]*) rm -f "$HOME/.local/share/mpd/pid" 2>/dev/null || true ;;
		*) kill -0 "$oldpid" 2>/dev/null || rm -f "$HOME/.local/share/mpd/pid" 2>/dev/null || true ;;
		esac
	fi
	mpd "$HOME/.config/mpd/mpd.conf" >>"$HOME/.local/share/mpd/log" 2>&1 || true
fi

# Lock after five idle minutes; `pkill -USR1 xidle` locks immediately (used by
# /etc/apm/suspend so the screen is locked before the machine sleeps).
if command -v xidle >/dev/null 2>&1; then
	xidle -no -timeout 300 -program "$HOME/bin/lock" &
fi

# No xconsole to close here: /etc/X11/xenodm/Xsetup_0 (shipped by this repo)
# no longer starts one. That has to be fixed there, because xenodm owns the
# process as root/_x11 and this session runs as an unprivileged user.

exec cwm
