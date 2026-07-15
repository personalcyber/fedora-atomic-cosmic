# fedora-atomic-cosmic

A custom [Fedora Atomic (bootc)](https://docs.fedoraproject.org/en-US/bootc/) image
based on the official **Fedora COSMIC Atomic** desktop, with:

- **COSMIC desktop** — from the `quay.io/fedora-ostree-desktops/cosmic-atomic`
  base image
- **FreeIPA client** — `freeipa-client`, `krb5-workstation`, and
  `oddjob-mkhomedir` baked in, ready for domain enrollment
- **Homebrew for all users** — installed at image build time and unpacked to
  `/var/home/linuxbrew` on first boot; `/etc/profile.d/brew.sh` (and a fish
  snippet) put `brew` on every user's PATH
- **Distrobox** — available to all users for mutable container distros
- **Flathub** — configured as a system-wide flatpak remote at image build time
- **RPM Fusion (free + nonfree)** — full `ffmpeg` and hardware video
  acceleration (`mesa-*-freeworld`) instead of the patent-limited defaults
- **Intel integrated graphics** — `intel-media-driver` (Broadwell/2014+) and
  `libva-intel-driver` (legacy) for VA-API hardware video decode/encode
  through the kernel DRM stack, plus `libva-utils` (`vainfo`) for diagnostics
- **Container registry shortnames** — `docker.io`/`ghcr.io`/`quay.io` are
  pre-configured as unqualified-search registries for Podman/Distrobox
- **Automatic staged updates** — `rpm-ostreed-automatic.timer` is enabled with
  `AutomaticUpdatePolicy=stage`, so machines pick up new image builds without
  a manual `bootc upgrade`
- **LAN discovery + printing** — `avahi`/`nss-mdns`, `cups` + `cups-browsed`,
  and `firewalld`'s default zone set to `FedoraWorkstation`
- **Tailscale** — repo + package installed and `tailscaled` enabled; run
  `tailscale up` after first boot to authenticate
- **Developer defaults** — JetBrains Mono / Fira Code fonts, `init.defaultBranch
  = main` in `/etc/gitconfig`, and SSH keepalive tuning in
  `/etc/ssh/ssh_config.d/`
- **Decorative terminal** — Starship prompt, `eza`/`bat` as `ls`/`cat`
  replacements, and a `fastfetch` banner on shell open, wired up for every
  user (bash, zsh, and fish) in interactive shells only

The image is built weekly (and on every push to `main`) by GitHub Actions and
published to GHCR.

## Installing / rebasing

From any existing Fedora Atomic or bootc system:

```bash
sudo bootc switch ghcr.io/nativetexan70/fedora-atomic-cosmic:latest
```

or with rpm-ostree:

```bash
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/nativetexan70/fedora-atomic-cosmic:latest
```

then reboot.

## Joining a FreeIPA domain

After deploying, enroll the machine into your IPA realm:

```bash
sudo ipa-client-install --mkhomedir
```

`oddjobd` is already enabled, so home directories are created automatically on
first login for IPA users.

## Homebrew notes

Homebrew's prefix (`/var/home/linuxbrew/.linuxbrew`) is owned by the primary
user (UID 1000), who can `brew install` packages. All other users get the
installed binaries on their PATH automatically. To let another user manage
packages too, grant them write access to the prefix (e.g. via a shared group).

## Building locally

```bash
podman build -t fedora-atomic-cosmic .
```

## Layout

| Path | Purpose |
|---|---|
| `Containerfile` | Image definition (base image + overlays + build script) |
| `build_files/build.sh` | Package installs, Homebrew packaging, service enablement |
| `system_files/` | Files overlaid onto `/` (systemd units, profile scripts, helpers, `/etc` defaults) |
| `.github/workflows/build.yml` | CI build and push to GHCR |
