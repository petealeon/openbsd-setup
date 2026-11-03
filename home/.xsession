#!/bin/sh
# ---------------------------------------------------------------------------
#  ~/.xsession — X session started by xenodm (or by `startx` via ~/.xinitrc)
#
#  Order matters: the D-Bus session first (dunst and libnotify need it), then
#  theme resources, then the helpers spectrwm expects to already be running.
# ---------------------------------------------------------------------------

# Re-exec under a private session bus; a no-op when dbus is absent.
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
	exec dbus-run-session -- "$0" "$@"
fi

PATH="$HOME/bin:/usr/local/bin:/usr/X11R6/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

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
# Map an absolute pointing device (touchscreen) onto the internal panel, and
# turn on natural scrolling / tap-to-click when the driver exposes them.  The
# wscons tunables themselves live in /etc/wsconsctl.conf.
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
fi

# ── wallpaper ───────────────────────────────────────────────────────────────
theme=$(cat "$HOME/.cache/theme" 2>/dev/null)
[ -n "$theme" ] || theme=amber
wall="$HOME/Pictures/wallpapers/$theme.png"
[ -f "$wall" ] || wall="$HOME/.config/spectrwm/themes/$theme/wallpaper.png"
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
	for d in "$HOME/Music" "$HOME/.local/share/mpd/playlists"; do
		mkdir -p "$d" 2>/dev/null || true
	done
	mpd "$HOME/.config/mpd/mpd.conf" >/dev/null 2>&1 || true
fi

# Lock after five idle minutes; `pkill -USR1 xidle` locks immediately (used by
# /etc/apm/suspend so the screen is locked before the machine sleeps).
if command -v xidle >/dev/null 2>&1; then
	xidle -no -timeout 300 -program "$HOME/bin/lock" &
fi

# No xconsole to close here: /etc/X11/xenodm/Xsetup_0 (shipped by this repo)
# no longer starts one. That has to be fixed there, because xenodm owns the
# process as root/_x11 and this session runs as an unprivileged user.

exec spectrwm
