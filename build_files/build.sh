#!/usr/bin/env bash
# Build script for the fedora-atomic-cosmic image.
# Runs inside the container build on top of quay.io/fedora-ostree-desktops/cosmic-atomic.
set -euxo pipefail

# On Fedora Atomic, /root and /home are symlinks into /var (roothome, home),
# which only get populated at first boot. Create the roothome target now so
# tools that write under $HOME (e.g. the Homebrew installer's cache dir)
# don't choke on a dangling symlink during the build.
mkdir -p /var/roothome

### RPM Fusion ##################################################################
# Free + nonfree repos for patent-encumbered codecs and hardware video accel
# drivers - the single most common manual step on any Fedora desktop.
#
# CI has repeatedly hit individual RPM Fusion mirrors timing out or failing
# DNS resolution (mirrors.rpmfusion.org is a redirector that hands out a
# mirror per request - a bad one can make dnf's own retry-across-mirrors
# exhaust its attempts). curl --retry re-queries the redirector fresh on each
# attempt, so it can land on a different, working mirror instead.
# --max-time bounds each attempt's total wall-clock time (not just connect
# time) - a mirror that accepts the connection but drips data arbitrarily
# slowly would otherwise hang well past what --connect-timeout catches.
curl --retry 5 --retry-all-errors --retry-delay 3 --connect-timeout 15 --max-time 40 -fsSL \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    -o /tmp/rpmfusion-free-release.rpm
curl --retry 5 --retry-all-errors --retry-delay 3 --connect-timeout 15 --max-time 40 -fsSL \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" \
    -o /tmp/rpmfusion-nonfree-release.rpm
dnf -y install /tmp/rpmfusion-free-release.rpm /tmp/rpmfusion-nonfree-release.rpm
rm -f /tmp/rpmfusion-free-release.rpm /tmp/rpmfusion-nonfree-release.rpm

### Tailscale repo ##############################################################
curl -fsSL https://pkgs.tailscale.com/stable/fedora/tailscale.repo \
    -o /etc/yum.repos.d/tailscale.repo

### COPR repos ###################################################################
# - ublue-os/packages: ujust/ugum and the composable
#   /usr/share/ublue-os/just/*.just recipe mechanism (our recipes live in
#   60-custom.just below)
# - atim/starship: starship was removed from Fedora's official repos at F37,
#   this is the community-maintained COPR build used ever since
dnf -y install dnf5-plugins
dnf -y copr enable ublue-os/packages
dnf -y copr enable atim/starship

### Layered packages ##########################################################
# - freeipa-client / krb5-workstation / oddjob-mkhomedir: FreeIPA enrollment
#   support (run `ipa-client-install --mkhomedir` on a deployed machine)
# - distrobox: mutable container distros for every user
# - git-core / zstd: needed to install and package Homebrew below
# - ffmpeg / mesa-va-drivers-freeworld: full RPM Fusion codec + hardware
#   video accel (replaces the patent-limited *-free builds shipped by
#   default; there's no separate freeworld VDPAU package on Fedora 44)
# - intel-media-driver / libva-intel-driver / libva-utils: VA-API (DRM)
#   hardware video decode/encode for Intel integrated graphics - iHD driver
#   for Broadwell (2014) and newer, legacy i965 driver for older chips
# - firewalld / avahi / nss-mdns / cups*: LAN discovery and network printing
# - tailscale: VPN mesh client (service enabled below; run `tailscale up`
#   after first boot to authenticate against your tailnet)
# - jetbrains-mono-fonts / fira-code-fonts: monospace coding fonts
# - starship / eza / bat / fastfetch: decorative terminal setup (prompt,
#   `ls`/`cat` replacements, startup system-info banner); wired up for every
#   user via /etc/profile.d and the fish vendor conf dir
# - ublue-os-just: ujust/ugum plus the recipe-import mechanism used by
#   system_files/usr/share/ublue-os/just/60-custom.just
# - gdm: replaces cosmic-greeter as the login manager (see the "Login
#   manager" section below) - cosmic-greeter has a confirmed upstream bug
#   where it never submits a manually-typed username to PAM/SSSD at all,
#   silently launching a session for the wrong local account instead
#   (https://github.com/pop-os/cosmic-greeter/issues/376), which breaks
#   FreeIPA/AD login entirely
dnf -y install --allowerasing \
    distrobox \
    ublue-os-just \
    freeipa-client \
    krb5-workstation \
    oddjob-mkhomedir \
    git-core \
    zstd \
    ffmpeg \
    mesa-va-drivers-freeworld \
    intel-media-driver \
    libva-intel-driver \
    libva-utils \
    firewalld \
    avahi \
    nss-mdns \
    cups \
    cups-filters \
    cups-browsed \
    tailscale \
    jetbrains-mono-fonts \
    fira-code-fonts \
    starship \
    eza \
    bat \
    fastfetch \
    gdm

### Homebrew ##################################################################
# Homebrew cannot live in the immutable /usr tree, so install it at build
# time, pack the prefix into a tarball shipped in /usr/share, and let
# brew-setup.service unpack it into /var/home/linuxbrew on first boot.
export HOMEBREW_NO_ANALYTICS=1
mkdir -p /var/home
# The Homebrew installer refuses to run as root unless it detects a container.
touch /.dockerenv
curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o /tmp/brew-install.sh
chmod +x /tmp/brew-install.sh
NONINTERACTIVE=1 /tmp/brew-install.sh
tar --zstd -cf /usr/share/homebrew.tar.zst -C /var/home linuxbrew
rm -rf /.dockerenv /tmp/brew-install.sh /var/home/linuxbrew

### Flatpak ####################################################################
# Deliberately NOT `flatpak remote-add` here: unlike /etc, /var is excluded
# from the ostree commit entirely (treated like a Docker VOLUME - see
# `ostree container commit`'s docs), so a remote registered during the build
# lives in /var/lib/flatpak/repo/config and is silently discarded, never
# reaching the deployed system. (Confirmed via a real-world migration where
# Flathub wasn't actually enabled after deploying.) flathub-setup.service
# below runs `flatpak remote-add` at first boot instead, when /var is real.

### Firewalld default zone #####################################################
# firewall-offline-cmd edits the on-disk zone config directly (no running
# daemon needed during the build). FedoraWorkstation is the zone Fedora
# Workstation itself uses: it permits mDNS/DNS-SD, SMB client, and SSH -
# the profile an actual desktop machine wants.
firewall-offline-cmd --set-default-zone=FedoraWorkstation

### Login manager: GDM instead of cosmic-greeter ###############################
# The base image defaults to cosmic-greeter, but it has a confirmed upstream
# bug breaking FreeIPA/AD login (see the package list comment above for the
# issue link). GDM correctly hands manually-typed domain usernames to
# PAM/SSSD, and still lets you pick the COSMIC session from its own session
# switcher - `systemctl enable gdm.service` retargets the display-manager.service
# alias, so cosmic-greeter no longer needs to be running to be inactive, but
# disable it explicitly for clarity and to stop cosmic-greeter-daemon
# starting alongside it.
systemctl disable cosmic-greeter.service cosmic-greeter-daemon.service || true

### Helper scripts and services ###############################################
chmod 0755 /usr/libexec/brew-setup.sh /usr/libexec/flathub-setup.sh
systemctl enable \
    brew-setup.service \
    flathub-setup.service \
    oddjobd.service \
    firewalld.service \
    avahi-daemon.service \
    cups.service \
    cups-browsed.service \
    tailscaled.service \
    rpm-ostreed-automatic.timer \
    gdm.service

### Cleanup ###################################################################
dnf clean all
rm -rf /var/cache/* /var/log/* /var/tmp/* 2>/dev/null || true
ostree container commit
