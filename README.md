# Fedora Atomic with Cosmic Desktop

A custom [Fedora Atomic (bootc)](https://docs.fedoraproject.org/en-US/bootc/) image
based on the official **Fedora COSMIC Atomic** desktop, with:

- **COSMIC desktop** — from the `quay.io/fedora-ostree-desktops/cosmic-atomic`
  base image, with **GDM** as the login manager instead of the default
  `cosmic-greeter` (see below) — the COSMIC session is still selectable from
  GDM's own session switcher
- **FreeIPA client** — `freeipa-client`, `krb5-workstation`, and
  `oddjob-mkhomedir` baked in, ready for domain enrollment
- **Homebrew for all users** — installed at image build time and unpacked to
  `/var/home/linuxbrew` on first boot; `/etc/profile.d/brew.sh` (and a fish
  snippet) put `brew` on every user's PATH
- **Distrobox** — available to all users for mutable container distros
- **Flathub + default apps** — the Flathub remote is configured and a curated app set is
  installed on first boot (must run at first boot, not build time: `/var`, where flatpak's
  system installation lives, isn't part of the ostree commit): Firefox, Thunderbird,
  Flatseal, Warehouse, DejaDup, Mission Center, and GNOME Connections
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
- **`ujust` recipes** — `ujust`/`ugum` (from the
  [`ublue-os/packages`](https://copr.fedorainfracloud.org/coprs/ublue-os/packages/)
  COPR) plus a custom recipe set for this image (see below)

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

After deploying, enroll the machine into your IPA realm (or run `ujust ipa-enroll`, which
does the same thing interactively and also restarts the affected services):

```bash
sudo ipa-client-install --mkhomedir
sudo systemctl restart sssd oddjobd certmonger
```

`oddjobd` is already enabled, so home directories are created automatically on first login
for IPA users. `ipa-client-install` rewrites `sssd.conf`/`krb5.conf`/PAM+NSS config, but
already-running services have the old config cached in memory — restarting them usually
avoids needing a reboot before authentication works, though a reboot may still be required
in some cases.

### IPA accounts not showing on the COSMIC login screen

`cosmic-greeter` lists login-screen users via NSS/passwd enumeration — unlike GDM, which can
show a manually-typed username without needing a directory listing. SSSD has enumeration off
by default for IPA/AD domains (it's expensive against a large directory), so enrolled IPA
accounts silently don't appear on the greeter even though logging in by typing the username
still works. `ujust ipa-enroll` sets `enumerate = True` in the domain's `sssd.conf` section
automatically; doing it by hand looks like:

```bash
sudo sed -i "/^\[domain\/YOUR.DOMAIN\]/a enumerate = True" /etc/sssd/sssd.conf
sudo systemctl restart sssd
```

This is fine for a small IPA deployment, but full enumeration means SSSD periodically syncs
the entire directory into its local cache — on a large corporate directory that adds real
load, so treat it as a deliberate choice rather than a default for production environments.

If accounts still don't show after enabling enumeration, check your IPA server's assigned
UID range (`ipa idrange-show`) — FreeIPA often auto-assigns UID ranges in the billions to
avoid cross-domain collisions, which can fall outside whatever "human user" range a greeter
filters to.

### Why GDM instead of cosmic-greeter

`cosmic-greeter` (COSMIC's own login manager) has a confirmed upstream bug affecting FreeIPA
and Active Directory alike: manually typing a domain username that isn't in its enumerated
list never actually gets submitted to PAM/SSSD for authentication at all — it silently opens
a session for a different local account instead, with no error shown. Verified via
`journalctl -u cosmic-greeter -u cosmic-greeter-daemon` during a live failed attempt: no
`pam_sss` invocation appears anywhere in the log. See
[pop-os/cosmic-greeter#376](https://github.com/pop-os/cosmic-greeter/issues/376) — this is
an upstream defect, not something fixable via `sssd.conf`, HBAC, or IPA configuration (both
were checked and ruled out before concluding this).

This image installs and enables `gdm` instead, which correctly authenticates manually-typed
domain usernames. GDM's own session switcher still lists the COSMIC session — enrolling in
IPA doesn't require giving up the COSMIC desktop, just its default greeter. If upstream fixes
`cosmic-greeter`, this can be reverted.

## Homebrew notes

Homebrew's prefix (`/var/home/linuxbrew/.linuxbrew`) is owned by the primary
user (UID 1000), who can `brew install` packages. All other users get the
installed binaries on their PATH automatically. To let another user manage
packages too, grant them write access to the prefix (e.g. via a shared group).

## `ujust` recipes

Run `ujust --choose` for an interactive picker, or `ujust <recipe>` directly:

| Recipe | Description |
|---|---|
| `update` | Updates the base image, Flatpaks, and Homebrew packages in one shot |
| `rebase-helper` | Interactively rebase to a different tag of this image |
| `clean-system` | Removes old rpm-ostree deployments, unused podman images, and unused flatpak runtimes |
| `ipa-enroll` | Prompts for an IPA domain/server, runs `ipa-client-install --mkhomedir`, enables SSSD enumeration (so accounts show on the COSMIC login screen), and restarts the affected services |
| `ipa-unenroll` | Removes this machine from its FreeIPA domain |
| `brew-status` | Shows whether Homebrew has been unpacked and who owns it |
| `brew-resync` | Re-runs the Homebrew first-boot unpack (e.g. after a home directory wipe) |
| `distrobox-create NAME IMAGE` | Creates and enters a distrobox container |
| `toggle-tailscale` | Enables/disables the Tailscale VPN mesh client |
| `verify-hwaccel` | Runs `vainfo` to check Intel VA-API hardware video acceleration |
| `toggle-terminal-bling` | Turns the default Starship/eza/bat/fastfetch terminal setup on or off |

## Building locally

```bash
podman build -t fedora-atomic-cosmic .
```

## Building an ISO installer

For a bootable installer ISO (e.g. bare-metal installs), use
[`bootc-image-builder`](https://github.com/osbuild/bootc-image-builder). It runs privileged
since it partitions/formats a disk image.

```bash
mkdir -p output
sudo podman run --rm -it --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v ./output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type iso \
    --rootfs ext4 \
    ghcr.io/nativetexan70/fedora-atomic-cosmic:latest
```

The resulting `install.iso` lands in `./output/bootiso/`. `--rootfs ext4` is required since
this image doesn't set a default root filesystem.

To build against a local `podman build` image instead of the published GHCR one, reference it
with the `containers-storage:` prefix instead of the registry path:

```bash
    containers-storage:localhost/fedora-atomic-cosmic
```

### Unattended installs

For an unattended installer (disk partitioning, network config, etc. baked in), use
`--type anaconda-iso` with a kickstart override in `config.toml`:

```bash
sudo podman run --rm -it --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v ./config.toml:/config.toml:ro \
    -v ./output:/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type anaconda-iso \
    --rootfs ext4 \
    ghcr.io/nativetexan70/fedora-atomic-cosmic:latest
```

```toml
# config.toml
[customizations.installer.kickstart]
contents = """
text --non-interactive
zerombr
clearpart --all --initlabel --disklabel=gpt
autopart --noswap --type=lvm
network --bootproto=dhcp --device=link --activate --onboot=on
"""
```

`bootc-image-builder` appends the container install step to the kickstart automatically —
don't duplicate it. On SELinux-enforcing hosts, the `osbuild-selinux` package must be
installed.

## Layout

| Path | Purpose |
|---|---|
| `Containerfile` | Image definition (base image + overlays + build script) |
| `build_files/build.sh` | Package installs, Homebrew packaging, service enablement |
| `system_files/` | Files overlaid onto `/` (systemd units, profile scripts, helpers, `/etc` defaults) |
| `.github/workflows/build.yml` | CI build and push to GHCR |
