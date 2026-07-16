# Fedora Atomic COSMIC — Documentation

A custom [Fedora Atomic (bootc)](https://docs.fedoraproject.org/en-US/bootc/) image based on
**Fedora COSMIC Atomic**, pre-configured for FreeIPA domain membership, developer tooling, and
daily-driver desktop use.

## Quick links

| Topic | Page |
|---|---|
| Installing or rebasing | [Installation](Installation.md) |
| Joining a FreeIPA / AD domain | [FreeIPA Integration](FreeIPA-Integration.md) |
| Login manager (GDM vs cosmic-greeter) | [Login Manager](Login-Manager.md) |
| Lock screen | [Login Manager § Lock screen](Login-Manager.md#lock-screen) |
| Homebrew for all users | [Homebrew](Homebrew.md) |
| Flatpak and default apps | [Flatpak and Flathub](Flatpak-and-Flathub.md) |
| Terminal setup (Starship / eza / bat / fastfetch) | [Terminal Setup](Terminal-Setup.md) |
| Intel hardware video acceleration | [Hardware Acceleration](Hardware-Acceleration.md) |
| Tailscale VPN | [Tailscale](Tailscale.md) |
| `ujust` recipes | [ujust Recipes](ujust-Recipes.md) |
| Building the image locally | [Building the Image](Building-the-Image.md) |
| Building a bootable ISO installer | [ISO Installer](ISO-Installer.md) |
| Homebrew vs Nix — package manager comparison | [Package Manager Comparison](Package-Manager-Comparison.md) |

## What's in the image

- **COSMIC desktop** — from `quay.io/fedora-ostree-desktops/cosmic-atomic:44`, with GDM as
  the login manager (see [Login Manager](Login-Manager.md))
- **FreeIPA client** — `freeipa-client`, `krb5-workstation`, `oddjob-mkhomedir`
- **Homebrew** — installed at build time, unpacked to `/var/home/linuxbrew` on first boot
- **Distrobox** — mutable container distros for every user
- **Flathub + default apps** — Firefox, Thunderbird, Flatseal, Warehouse, DejaDup, Mission
  Center, GNOME Connections (installed on first boot)
- **RPM Fusion** — full `ffmpeg` and `mesa-va-drivers-freeworld`
- **Intel VA-API** — `intel-media-driver` + `libva-intel-driver` + `libva-utils`
- **Tailscale** — repo + package + `tailscaled` enabled
- **Automatic staged updates** — `rpm-ostreed-automatic.timer`
- **LAN discovery + printing** — avahi, cups, firewalld (FedoraWorkstation zone)
- **Developer defaults** — JetBrains Mono / Fira Code fonts, git `defaultBranch = main`,
  SSH keepalive tuning
- **Decorative terminal** — Starship, eza, bat, fastfetch
- **`ujust` recipes** — custom recipe set (see [ujust Recipes](ujust-Recipes.md))

## Registry

```
ghcr.io/nativetexan70/fedora-atomic-cosmic:latest
```

Built weekly (Monday 05:20 UTC) and on every push to `main`.
