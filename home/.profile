# ~/.profile - login shell environment.
export EDITOR=nvim
export VISUAL=nvim
export PAGER=less
export PATH="$HOME/bin:/usr/local/bin:/usr/X11R6/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export ENV="$HOME/.kshrc"

# TUI polish. bat's ansi theme follows st's amber palette instead of dragging
# in a foreign syntax theme.
export BAT_THEME=ansi
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --color=bg+:#2a241b,bg:#0f0e0c,fg:#e6ded0,hl:#ffb000,fg+:#f5efe4,hl+:#ffc94d,info:#8a8175,prompt:#9aa66b,pointer:#ffb000,marker:#b8849a,spinner:#ffb000,header:#8a8175'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# Make GTK apps match the dark desktop.
export GTK_THEME=Adwaita:dark

# OpenBSD browser/terminal defaults. The chromium package installs its
# launcher as `chrome` (/usr/local/bin/chrome), not `chromium`; ~/bin/browser
# wraps it so xdg-open and super+shift+b skip the first-run terms dialog.
export BROWSER="$HOME/bin/browser"
export TERMINAL=st

# terminfo: prefer st-256color when installed, but fall back to xterm-256color
# so colours still work in a vanilla st or before the rebuilt st is installed.
if infocmp st-256color >/dev/null 2>&1; then
	export TERM=st-256color
else
	export TERM=xterm-256color
fi

# No MPRIS on OpenBSD; players that look for one stay quiet.
unset XDG_SESSION_TYPE 2>/dev/null || true

# Persisted audio output hint (set by ~/bin/audio-output).
if [ -z "${AUDIODEVICE:-}" ] && [ -f "$HOME/.config/audio-device" ]; then
	AUDIODEVICE=$(sed -n '1p' "$HOME/.config/audio-device" 2>/dev/null)
	case ${AUDIODEVICE:-} in ''|default) ;; *) export AUDIODEVICE ;; esac
fi

# ksh: load ~/.kshrc for interactive shells and keep persistent history.
case $- in
*i*)
	[ -f "$HOME/.kshrc" ] && . "$HOME/.kshrc"
	;;
esac
export HISTFILE="$HOME/.ksh_history"
export HISTSIZE=5000
export HISTCONTROL=ignoredups
export SAVEHIST=$HISTSIZE
