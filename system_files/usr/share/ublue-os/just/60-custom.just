# Enroll this machine in a FreeIPA domain
ipa-enroll:
    #!/usr/bin/bash
    set -euo pipefail
    domain=$(ugum input --placeholder "IPA domain (e.g. example.com)")
    server=$(ugum input --placeholder "IPA server hostname (blank for DNS discovery)")
    if [ -n "${server}" ]; then
        sudo ipa-client-install --mkhomedir --domain "${domain}" --server "${server}"
    else
        sudo ipa-client-install --mkhomedir --domain "${domain}"
    fi
    # cosmic-greeter lists login-screen users via NSS/passwd enumeration
    # (unlike GDM, which can show a manually-typed username without a
    # directory listing), and SSSD has enumeration off by default for
    # IPA/AD domains - so IPA accounts silently don't appear on the login
    # screen even though login-by-username still works fine. Turn it on so
    # enrolled accounts actually show up. Trade-off: SSSD will periodically
    # sync the whole directory into its local cache, which is fine for a
    # small IPA deployment but adds directory-server load on a large one.
    if ! sudo grep -q '^enumerate' /etc/sssd/sssd.conf; then
        sudo sed -i "/^\[domain\/${domain}\]/a enumerate = True" /etc/sssd/sssd.conf
    fi
    # ipa-client-install rewrites sssd.conf/krb5.conf/PAM+NSS config, but
    # services already running (sssd, oddjobd, certmonger) have the old
    # config cached in memory - restart them so enrollment can actually
    # authenticate without waiting for a reboot.
    sudo systemctl restart sssd oddjobd certmonger
    echo "Enrolled. If login still doesn't authenticate, reboot."

# Remove this machine from its FreeIPA domain
ipa-unenroll:
    sudo ipa-client-install --uninstall

# Show whether Homebrew has been unpacked and who owns it
brew-status:
    #!/usr/bin/bash
    set -euo pipefail
    if [ -x /var/home/linuxbrew/.linuxbrew/bin/brew ]; then
        echo "Homebrew is installed, owned by: $(stat -c '%U' /var/home/linuxbrew)"
    else
        echo "Homebrew has not been unpacked yet (brew-setup.service runs at first boot)"
    fi

# Re-run the Homebrew first-boot unpack, e.g. after a home directory wipe
brew-resync:
    sudo /usr/libexec/brew-setup.sh

# Create and enter a distrobox container: ujust distrobox-create NAME IMAGE
distrobox-create name image:
    distrobox create --name {{name}} --image {{image}} --yes
    distrobox enter {{name}}

# Enable or disable the Tailscale VPN mesh client
toggle-tailscale:
    #!/usr/bin/bash
    set -euo pipefail
    if systemctl is-active --quiet tailscaled; then
        sudo systemctl disable --now tailscaled
        echo "Tailscale disabled"
    else
        sudo systemctl enable --now tailscaled
        echo "Tailscale enabled. Run 'tailscale up' to authenticate."
    fi

# Check whether Intel VA-API hardware video acceleration is working
verify-hwaccel:
    vainfo

# Switch the login manager between GDM and cosmic-greeter
# GDM is the default because cosmic-greeter has an upstream bug (pop-os/cosmic-greeter#376)
# where manually-typed FreeIPA/AD usernames never reach PAM/SSSD. Switch back to
# cosmic-greeter only after confirming the upstream fix has landed.
toggle-login-manager:
    #!/usr/bin/bash
    set -euo pipefail
    current=$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" 2>/dev/null || echo "unknown")
    if [ "${current}" = "gdm.service" ]; then
        echo "Switching from GDM to cosmic-greeter."
        echo "WARNING: cosmic-greeter has a known bug (pop-os/cosmic-greeter#376) where"
        echo "manually-typed FreeIPA/AD usernames never reach PAM/SSSD. Only proceed if"
        echo "you have confirmed the upstream fix is in your installed version."
        confirm=$(ugum confirm "Switch to cosmic-greeter?")
        if [ "${confirm}" != "true" ]; then
            echo "Cancelled."
            exit 0
        fi
        sudo systemctl disable gdm.service
        sudo systemctl enable cosmic-greeter.service cosmic-greeter-daemon.service
        echo "Switched to cosmic-greeter. Reboot to take effect."
    else
        echo "Switching from cosmic-greeter to GDM."
        sudo systemctl disable cosmic-greeter.service cosmic-greeter-daemon.service || true
        sudo systemctl enable gdm.service
        echo "Switched to GDM. Reboot to take effect."
    fi

# Toggle the default Starship/eza/bat/fastfetch terminal setup on or off
toggle-terminal-bling:
    #!/usr/bin/bash
    set -euo pipefail
    if [ -e /etc/profile.d/terminal.sh.disabled ]; then
        sudo mv /etc/profile.d/terminal.sh.disabled /etc/profile.d/terminal.sh
        sudo mv /usr/share/fish/vendor_conf.d/terminal.fish.disabled \
            /usr/share/fish/vendor_conf.d/terminal.fish 2>/dev/null || true
        echo "Terminal bling re-enabled. Open a new shell to see it."
    else
        sudo mv /etc/profile.d/terminal.sh /etc/profile.d/terminal.sh.disabled
        sudo mv /usr/share/fish/vendor_conf.d/terminal.fish \
            /usr/share/fish/vendor_conf.d/terminal.fish.disabled 2>/dev/null || true
        echo "Terminal bling disabled. Open a new shell to see the change."
    fi

# Update the base image, Flatpaks, and Homebrew packages in one shot
update:
    #!/usr/bin/bash
    set -euo pipefail
    echo "==> Updating base image"
    if command -v bootc >/dev/null 2>&1; then
        sudo bootc upgrade
    else
        sudo rpm-ostree upgrade
    fi
    echo "==> Updating Flatpaks"
    flatpak update -y
    if command -v brew >/dev/null 2>&1; then
        echo "==> Updating Homebrew packages"
        brew update && brew upgrade
    fi

# Interactively rebase to a different tag of this image
rebase-helper:
    #!/usr/bin/bash
    set -euo pipefail
    tag=$(ugum input --placeholder "Tag to rebase to (e.g. latest, 44)")
    if command -v bootc >/dev/null 2>&1; then
        sudo bootc switch "ghcr.io/nativetexan70/fedora-atomic-cosmic:${tag}"
    else
        sudo rpm-ostree rebase "ostree-unverified-registry:ghcr.io/nativetexan70/fedora-atomic-cosmic:${tag}"
    fi

# Remove old rpm-ostree deployments, unused podman images, and unused flatpak runtimes
clean-system:
    #!/usr/bin/bash
    set -euo pipefail
    sudo rpm-ostree cleanup -m
    podman image prune -af
    flatpak uninstall --unused -y
