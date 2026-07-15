#!/usr/bin/env bash
# Make sure the system-wide Flathub remote exists so every user can install
# flatpaks from it. Must run at first boot, not at image build time: /var
# (where flatpak's system installation actually lives) is excluded from the
# ostree commit, so a remote registered during the build never ships.
set -euo pipefail

if flatpak remotes --system --columns=name | grep -qx flathub; then
    exit 0
fi

flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
