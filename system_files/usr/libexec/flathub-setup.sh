#!/usr/bin/env bash
# Make sure the system-wide Flathub remote exists, and install this image's
# default app set. Must run at first boot, not at image build time: /var
# (where flatpak's system installation actually lives) is excluded from the
# ostree commit, so anything registered/installed during the build never
# ships - see CLAUDE.md's "/etc vs /var" note.
set -euo pipefail

if ! flatpak remotes --system --columns=name | grep -qx flathub; then
    flatpak remote-add --system --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
fi

# Default app set for this image. `flatpak install -y` is a no-op for
# already-installed apps, so this is safe to run on every boot.
flatpak install -y --system --noninteractive flathub \
    org.mozilla.firefox \
    org.mozilla.Thunderbird \
    com.github.tchx84.Flatseal \
    io.github.flattool.Warehouse \
    org.gnome.DejaDup \
    io.missioncenter.MissionCenter \
    org.gnome.Connections
