# Installed from arch-install/zsh/.zshrc
setopt AUTO_CD
setopt INTERACTIVE_COMMENTS
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt EXTENDED_HISTORY
setopt HIST_REDUCE_BLANKS

HISTFILE=${HOME}/.zsh_history
HISTSIZE=50000
SAVEHIST=50000

export EDITOR=${EDITOR:-nvim}
export VISUAL=${VISUAL:-${EDITOR}}
typeset -U path
path=(${HOME}/.local/bin ${HOME}/.cargo/bin ${HOME}/.grok/bin $path)

alias ls='ls --color=auto'
alias grep='grep --color=auto'

fpath=(/usr/share/zsh/site-functions $fpath)
autoload -Uz compinit
compinit

[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -r /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh

if command -v zoxide >/dev/null 2>&1; then
	eval "$(zoxide init zsh)"
fi

[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] &&
	source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

[[ -r /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]] &&
	source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
[[ -n ${terminfo[kcuu1]} ]] && bindkey "${terminfo[kcuu1]}" history-substring-search-up
[[ -n ${terminfo[kcud1]} ]] && bindkey "${terminfo[kcud1]}" history-substring-search-down

# syntax-highlighting must be last
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] &&
	source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

PROMPT='%F{cyan}%~%f %# '
