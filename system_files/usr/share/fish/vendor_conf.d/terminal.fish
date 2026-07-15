# Decorative terminal setup for fish: Starship prompt, eza/bat as ls/cat
# replacements, and a fastfetch banner. Interactive shells only.
if not status is-interactive
    return
end

if command -v starship >/dev/null 2>&1
    starship init fish | source
end

if command -v eza >/dev/null 2>&1
    alias ls='eza --icons'
    alias ll='eza -l --icons --git'
    alias la='eza -la --icons --git'
end

if command -v bat >/dev/null 2>&1
    alias cat='bat --paging=never'
end

if command -v fastfetch >/dev/null 2>&1
    fastfetch
end
