# Decorative terminal setup for bash/zsh: Starship prompt, eza/bat as ls/cat
# replacements, and a fastfetch banner. Interactive shells only, so this never
# touches non-interactive sessions (scp, rsync, ansible, CI-over-ssh, etc).
case $- in
    *i*) ;;
    *) return 0 2>/dev/null || exit 0 ;;
esac

if command -v starship >/dev/null 2>&1; then
    if [ -n "$BASH_VERSION" ]; then
        eval "$(starship init bash)"
    elif [ -n "$ZSH_VERSION" ]; then
        eval "$(starship init zsh)"
    fi
fi

if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons'
    alias ll='eza -l --icons --git'
    alias la='eza -la --icons --git'
fi

if command -v bat >/dev/null 2>&1; then
    alias cat='bat --paging=never'
fi

if command -v fastfetch >/dev/null 2>&1; then
    fastfetch
fi
