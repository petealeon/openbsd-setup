# ~/.kshrc - interactive ksh (sourced for interactive shells via $ENV).
case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac

set -o emacs

# ── history ─────────────────────────────────────────────────────────────────
# Persistent history across sessions. ksh writes history on exit when
# HISTFILE/HISTSIZE are set in the shell.
HISTFILE="${HISTFILE:-$HOME/.ksh_history}"
HISTSIZE="${HISTSIZE:-5000}"
export HISTFILE HISTSIZE
if [ -z "${HISTCONTROL:-}" ]; then
	HISTCONTROL=ignoredups
	export HISTCONTROL
fi

# ── prompt ──────────────────────────────────────────────────────────────────
# user@host:cwd with git/got branch when inside a repo. ANSI escapes follow
# the terminal palette. Avoid shell printf format backslash parsing on dynamic
# strings to prevent "unknown escape sequence" warnings in some ksh builds.
_prompt_dir() {
	case $PWD in
	"$HOME") print -r -- '~' ;;
	"$HOME"/*) print -r -- "~/${PWD#"$HOME"/}" ;;
	*) print -r -- "$PWD" ;;
	esac
}

_vcs_branch() {
	b=
	if command -v git >/dev/null 2>&1; then
		b=$(git symbolic-ref --short -q HEAD 2>/dev/null ||
			git describe --tags --exact-match 2>/dev/null ||
			git rev-parse --short HEAD 2>/dev/null) || b=
		if [ -n "$b" ]; then
			print -r -- " (git:$b)"
			return 0
		fi
	fi
	if command -v got >/dev/null 2>&1; then
		b=$(got branch 2>/dev/null | awk '/^\*/{print $2; exit}') || b=
		[ -n "$b" ] && print -r -- " (got:$b)"
	fi
	return 0
}

_prompt_host() {
	hostname -s 2>/dev/null || hostname 2>/dev/null || print -r -- "${HOSTNAME:-openbsd}"
}

_prompt_end() {
	if [ "$(id -u)" -eq 0 ]; then
		print -r -- '# '
	else
		print -r -- ' '
	fi
}

case ${TERM:-} in
dumb|linux|vt100|vt220)
	PS1='$(_prompt_dir)$(_vcs_branch)$(_prompt_end)'
	;;
*)
	PS1='$(u=$(id -un); h=$(_prompt_host); d=$(_prompt_dir); v=$(_vcs_branch); p=$(_prompt_end); e=$(printf "\033"); print -nr -- "${e}[33m${u}@${h}${e}[0m:${e}[36m${d}${e}[0m${v}${p}")'
	;;
esac
export PS1

# ── aliases ─────────────────────────────────────────────────────────────────
if command -v eza >/dev/null 2>&1; then
	alias ls='eza --color=auto'
	alias ll='eza -lah --git'
	alias la='eza -lah'
	alias lt='eza --tree --level=2'
else
	alias ls='ls -F'
	alias ll='ls -lah'
	alias la='ls -A'
fi
if command -v bat >/dev/null 2>&1; then
	alias cat='bat --paging=never'
fi
alias grep='grep --color=auto'
if command -v nvim >/dev/null 2>&1; then
	alias vi='nvim'
	alias vim='nvim'
fi
if command -v btop >/dev/null 2>&1; then
	alias top='btop'
fi
alias music='music'
alias games='games'
alias art='music'
alias now='mpc current'
alias pause='mpc toggle'
alias next='mpc next'
alias prev='mpc prev'
alias ..='cd ..'
alias ...='cd ../..'
alias df='df -h'
alias du='du -h'
alias mv='mv -i'
alias rm='rm -i'
alias hist='fc -l 1'
alias keys='keybinds'
alias walk='lf'
alias wttr='curl -s wttr.in/?format=3'
