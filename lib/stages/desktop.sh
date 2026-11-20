#!/bin/sh
# lib/stages/desktop.sh — dotfiles, theme, wallpaper, user directories.

stage_desktop() {
	say "desktop: dotfiles, amber theme, fonts"

	init_backup
	(
		cd "$REPO/home" || exit 1
		find . -type f | while IFS= read -r rel; do
			backup_path "$GUEST_HOME/${rel#./}"
		done
	)

	run_shell "tar -C '$REPO/home' -cf - . | tar -C '$GUEST_HOME' -xpf -"
	run chown -R "$GUEST_USER:$GUEST_USER" "$GUEST_HOME"
	run_shell "chmod 755 '$GUEST_HOME/bin/'* '$GUEST_HOME/.xsession' '$GUEST_HOME/.xinitrc'"
	run_shell "chmod 755 '$GUEST_HOME/.config/spectrwm/bar.sh' '$GUEST_HOME/.config/lf/open' '$GUEST_HOME/.config/lf/preview'"

	# ── user directories ─────────────────────────────────────────────────
	for d in Music Videos/Downloads Pictures/Screenshots Games/roms Games/bios \
		.local/share/mpd/playlists .local/share/ncmpcpp .local/share/lyrics \
		.cache/lf .config/zathura .config/retroarch/saves .config/retroarch/states; do
		run mkdir -p "$GUEST_HOME/$d"
	done
	run chown -R "$GUEST_USER:$GUEST_USER" \
		"$GUEST_HOME/Music" "$GUEST_HOME/Videos" "$GUEST_HOME/Pictures" \
		"$GUEST_HOME/Games" "$GUEST_HOME/.local" "$GUEST_HOME/.cache" \
		"$GUEST_HOME/.config/retroarch" 2>/dev/null || true

	# Some configs keep $HOME for readability; bake the real path so they work
	# regardless of variable expansion behavior. Re-running is a no-op once absolute.
	for _f in "$GUEST_HOME/.spectrwm.conf" "$GUEST_HOME/.cwmrc"; do
		if [ -f "$_f" ]; then
			run_shell "sed 's|[\$]HOME|$GUEST_HOME|g' '$_f' > '$_f.new' && mv '$_f.new' '$_f'"
		fi
	done

	# ── theme ────────────────────────────────────────────────────────────
	run_shell "printf 'amber\n' > '$GUEST_HOME/.cache/theme'"
	run chown "$GUEST_USER:$GUEST_USER" "$GUEST_HOME/.cache/theme"
	run install -m 644 -o "$GUEST_USER" -g "$GUEST_USER" \
		"$REPO/home/Pictures/wallpapers/amber.png" \
		"$GUEST_HOME/Pictures/wallpapers/amber.png"

	# rofi must be pointed at the amber palette, not a leftover theme name.
	run_shell "sed 's|^@theme .*|@theme \"amber\"|' '$GUEST_HOME/.config/rofi/config.rasi' > '$GUEST_HOME/.config/rofi/config.rasi.new' && mv '$GUEST_HOME/.config/rofi/config.rasi.new' '$GUEST_HOME/.config/rofi/config.rasi'"
	run chown "$GUEST_USER:$GUEST_USER" "$GUEST_HOME/.config/rofi/config.rasi"

	as_user "fc-cache -f >/dev/null 2>&1 || true"

	info "Super+space: command menu   Super+Shift+/: keybindings"
}
