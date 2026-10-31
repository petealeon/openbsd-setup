# ~/.kshrc
set -o emacs
PS1='\u@\h:\w\$ '
export HISTFILE="$HOME/.ksh_history"
export HISTSIZE=10000

alias ll='ls -lh'
alias la='ls -A'
alias ..='cd ..'
alias ...='cd ../..'
