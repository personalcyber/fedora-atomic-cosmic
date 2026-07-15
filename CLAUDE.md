# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A bootc/rpm-ostree "Containerfile" build for a custom Fedora Atomic image: Fedora COSMIC
Atomic (`quay.io/fedora-ostree-desktops/cosmic-atomic:44`) as the base, layered with a
FreeIPA-joinable, developer-oriented desktop configuration. There is no application source
code here — this repo *is* the build definition for an OS image. All changes take effect by
rebuilding the container image, not by running a program.

## Build & test commands

There's no local unit test suite. "Testing" a change means building the image and checking
the build log / resulting container.

```bash
# Build the image locally (requires podman)
podman build -t fedora-atomic-cosmic .

# Syntax-check the build script before pushing (cheap, no image build required)
bash -n build_files/build.sh

# Validate a justfile recipe change without needing the ujust/ublue-os-just RPM installed
# (install `just` locally first: apt-get install just / brew install just)
just --justfile system_files/usr/share/ublue-os/just/60-custom.just --list
just --justfile system_files/usr/share/ublue-os/just/60-custom.just --dry-run <recipe>
```

Building a bootable installer ISO (not part of CI) uses a separate tool, `bootc-image-builder`,
run against the built container image — see the "Building an ISO installer" section in
`README.md` for the full command; it's not something `podman build` or this repo's own files
produce directly.

CI (`.github/workflows/build.yml`) builds on every push to `main`, on PRs (build-only, no
push), weekly (Monday 05:20 UTC, to pick up upstream base-image/package updates), and on
manual dispatch. It pushes `latest`, `44`, and a date tag to
`ghcr.io/nativetexan70/fedora-atomic-cosmic` on non-PR events.

There is no local dry-run of the full GitHub Actions build; the fastest real feedback loop is
pushing to a branch/PR and reading the Actions log, since RPM/COPR resolution failures only
surface inside the actual `dnf` transaction in the container build.

## Architecture

Three pieces compose the image, wired together by `Containerfile`:

1. **`Containerfile`** — pulls the base image (version pinned via `FEDORA_VERSION` build
   arg), `COPY`s `system_files/` onto `/`, then `COPY`s and runs `build_files/build.sh`.
2. **`build_files/build.sh`** — the only place packages get installed and repos get enabled.
   Runs as a single `RUN` step with `set -euxo pipefail`; **order matters** — repo-enabling
   `dnf install`/`dnf copr enable` calls must happen in their own command *before* a later
   `dnf install` that pulls packages from that newly-enabled repo, because dnf doesn't
   retroactively see repos added mid-transaction. Ends with `ostree container commit`.
3. **`system_files/`** — a literal overlay onto `/`: systemd units, `/etc` defaults,
   `/etc/profile.d` + fish `vendor_conf.d` shell snippets, and `/usr/libexec` helper scripts.
   Whatever exists here at a given path simply becomes that file in the image.

### The `/root` and `/home` symlink trap

Fedora Atomic images ship `/root -> /var/roothome` and `/home -> /var/home` as symlinks whose
*targets* don't exist until first boot. Anything in `build_files/build.sh` that touches
`$HOME` (Homebrew's installer writes to `$HOME/.cache`) will fail with a confusing
`mkdir: cannot create directory '/root': File exists` unless the target directory is
pre-created first (see `mkdir -p /var/roothome` / `mkdir -p /var/home` near the top of
`build.sh`). If you add another tool that writes under `$HOME` or `~`, this bites again.

### Homebrew: build-time install, first-boot unpack

Homebrew can't live in the read-only `/usr` tree, so `build.sh` installs it during the build,
tars the prefix into `/usr/share/homebrew.tar.zst`, then deletes the live copy. The systemd
oneshot `brew-setup.service` (unit in `system_files/usr/lib/systemd/system/`, script in
`system_files/usr/libexec/brew-setup.sh`) unpacks that tarball into `/var/home/linuxbrew` on
first boot and `chown`s it to UID 1000 (the primary/first-created user) — Homebrew requires a
single owning user. `/etc/profile.d/brew.sh` and the fish equivalent put `brew` on every
user's `PATH` regardless of who owns the prefix.

### `/etc` vs `/var`: only one of them survives the build

`ostree container commit` includes `/usr` and `/etc` in the image. `/var` is excluded
entirely — treated like a Docker `VOLUME`, not committed at all — so anything written under
`/var` during the `RUN` step in `Containerfile` is silently discarded and never reaches the
deployed system. Before configuring a tool at build time, check where its *actual* persistent
state lives, not just whether it has a config file that looks build-time-safe:

- **Safe to configure directly in `build.sh`**: firewalld's default zone
  (`firewall-offline-cmd --set-default-zone`, writes `/etc/firewalld/firewalld.conf`),
  container registry shortnames, `/etc/gitconfig`, SSH client config, `rpm-ostreed.conf` —
  all genuinely live under `/etc`, which is part of the commit and gets a 3-way merge on
  every deployment.
- **Not safe at build time**: Flatpak's system installation (`/var/lib/flatpak`) — this
  covers both the remote registration *and* any installed apps, since app data also lives
  under `/var/lib/flatpak/app/`. An earlier version of this repo ran `flatpak remote-add
  --system` directly in `build.sh`, reasoning (incorrectly) that it'd persist the same way
  `/etc`-based config does. It doesn't — the remote registration lives in
  `/var/lib/flatpak/repo/config`, gets discarded at commit time, and the deployed system
  boots with no Flathub remote at all (confirmed via a real-world migration where Flathub
  wasn't actually enabled after deploying). `flathub-setup.service` / `flathub-setup.sh` run
  `flatpak remote-add` *and* `flatpak install` for this image's default app set at first
  boot instead, same pattern as `brew-setup.service`. If you're tempted to "simplify" a
  first-boot service into a
  build-time `RUN` command, check whether the tool's state lives under `/var` first.

### GDM, not cosmic-greeter

The base image's default login manager, `cosmic-greeter`, is deliberately disabled in
`build.sh` in favor of `gdm`. This isn't a preference — `cosmic-greeter` has a confirmed
upstream bug ([pop-os/cosmic-greeter#376](https://github.com/pop-os/cosmic-greeter/issues/376))
where a manually-typed domain (FreeIPA/AD) username never reaches PAM/SSSD at all; it silently
opens a session for a different local account with no error. Verified via a live
`journalctl -u cosmic-greeter -u cosmic-greeter-daemon` capture during a failed login: no
`pam_sss` line anywhere. SSSD config (enumeration, HBAC) was checked and ruled out first —
this is a client-side defect, not something fixable from this repo's config. If upstream fixes
it, reverting to `cosmic-greeter` means re-enabling `cosmic-greeter.service` +
`cosmic-greeter-daemon.service` and disabling `gdm.service`; don't do that without confirming
the fix actually landed.

### `ujust` recipes

`system_files/usr/share/ublue-os/just/60-custom.just` is the one file that matters for
`ujust`. It's not a standalone justfile — the `ublue-os-just` package (from the
`ublue-os/packages` COPR) generates a master justfile at build time that
`import?`s this file, so recipe syntax must be valid `just` syntax but the file itself is
never invoked directly on a running system. `README.md` has the recipe table describing what
each one does; keep it in sync when adding/renaming recipes here.

### Non-Fedora-default package sources

Several packages here don't come from Fedora's stock repos — check `build.sh`'s `### COPR
repos` / `### RPM Fusion` / `### Tailscale repo` sections before assuming a package is a
plain `dnf install`:
- **RPM Fusion** (free + nonfree, installed via direct RPM URL from `mirrors.rpmfusion.org`)
  for `ffmpeg` and `mesa-va-drivers-freeworld`.
- **`atim/starship` COPR** — `starship` was removed from Fedora's official repos at F37.
- **`ublue-os/packages` COPR** — `ujust`/`ugum`.
- **Tailscale's own repo** — fetched directly via `curl` of their official `.repo` file.

If a `dnf install` fails with "No match for argument" in CI, check whether the package
actually needs one of these non-default sources, or whether the exact package name has
changed/split (this has happened before: `mesa-vdpau-drivers-freeworld` doesn't exist as a
distinct package on Fedora 44).

## Versioning

`FEDORA_VERSION` is set in two places that must stay in sync: the `ARG` default in
`Containerfile` and the `env.FEDORA_VERSION` in `.github/workflows/build.yml`. `build.sh` gets
the Fedora release number dynamically via `rpm -E %fedora` for RPM Fusion's URL, so it doesn't
need updating separately.
