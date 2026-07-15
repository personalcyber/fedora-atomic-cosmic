#!/usr/bin/env bash
# Build script for the fedora-atomic-cosmic image.
# Runs inside the container build on top of quay.io/fedora-ostree-desktops/cosmic-atomic.
set -euxo pipefail

# On Fedora Atomic, /root and /home are symlinks into /var (roothome, home),
# which only get populated at first boot. Create the roothome target now so
# tools that write under $HOME (e.g. the Homebrew installer's cache dir)
# don't choke on a dangling symlink during the build.
mkdir -p /var/roothome

### Layered packages ##########################################################
# - freeipa-client / krb5-workstation / oddjob-mkhomedir: FreeIPA enrollment
#   support (run `ipa-client-install --mkhomedir` on a deployed machine)
# - distrobox: mutable container distros for every user
# - git-core / zstd: needed to install and package Homebrew below
dnf -y install \
    distrobox \
    freeipa-client \
    krb5-workstation \
    oddjob-mkhomedir \
    git-core \
    zstd

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
# /etc is part of the ostree commit (and 3-way merged on every deployment), so
# a remote added here is present for every user on first login with no
# first-boot service needed.
flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

### Helper scripts and services ###############################################
chmod 0755 /usr/libexec/brew-setup.sh
systemctl enable \
    brew-setup.service \
    oddjobd.service

### Cleanup ###################################################################
dnf clean all
rm -rf /var/cache/* /var/log/* /var/tmp/* 2>/dev/null || true
ostree container commit
