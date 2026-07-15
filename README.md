# fedora-atomic-cosmic

A custom [Fedora Atomic (bootc)](https://docs.fedoraproject.org/en-US/bootc/) image
based on the official **Fedora COSMIC Atomic** desktop, with:

- **COSMIC desktop** — from the `quay.io/fedora/fedora-cosmic-atomic` base image
- **FreeIPA client** — `freeipa-client`, `krb5-workstation`, and
  `oddjob-mkhomedir` baked in, ready for domain enrollment
- **Homebrew for all users** — installed at image build time and unpacked to
  `/var/home/linuxbrew` on first boot; `/etc/profile.d/brew.sh` (and a fish
  snippet) put `brew` on every user's PATH
- **Distrobox** — available to all users for mutable container distros
- **Flathub** — configured as a system-wide flatpak remote at image build time

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
| `system_files/` | Files overlaid onto `/` (systemd units, profile scripts, helpers) |
| `.github/workflows/build.yml` | CI build and push to GHCR |
