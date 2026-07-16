# Homebrew

Homebrew is installed at image build time and made available to all users without requiring
each user to install it themselves.

## How it works

Because Homebrew can't live in the read-only `/usr` tree, the build process:

1. Installs Homebrew into `/var/home/linuxbrew/.linuxbrew` during the container build
2. Tars the prefix into `/usr/share/homebrew.tar.zst` (which is part of the image)
3. Deletes the live copy

On first boot, `brew-setup.service` unpacks the tarball back into
`/var/home/linuxbrew/.linuxbrew` and sets ownership to UID 1000 (the primary user).

`/etc/profile.d/brew.sh` (and a fish equivalent) add the Homebrew bin directory to `PATH`
for every user automatically.

## Package management

The primary user (UID 1000) owns the prefix and can install packages:

```bash
brew install <package>
brew update && brew upgrade
```

All users can run Homebrew-installed binaries — only the primary user can install or update
packages. To grant another user install rights, give them write access to the prefix:

```bash
sudo chown -R <username>: /var/home/linuxbrew/.linuxbrew
# or add them to a shared group with group write on the prefix
```

## Status and maintenance

```bash
# Check whether Homebrew is unpacked and who owns it
ujust brew-status

# Re-run the first-boot unpack (e.g. after a home directory wipe)
ujust brew-resync

# Update Homebrew and all installed packages (also part of `ujust update`)
brew update && brew upgrade
```

## Note on system updates

Homebrew lives in `/var`, which is separate from the ostree image. A `bootc upgrade` does not
modify or reset Homebrew — your installed packages persist across image updates. The tarball
in the image is only used on first boot (or after `ujust brew-resync`).

## Homebrew vs Nix

Nix (with Home Manager) is an alternative to Homebrew for user-level package management that
offers declarative package specs, exact version pinning via `flake.lock`, and per-user
rollback via Nix generations. The current release uses Homebrew; Nix is under consideration
for a future variant.

See [Package Manager Comparison](Package-Manager-Comparison.md) for a full side-by-side
analysis, including what Nix can and cannot replace on a Fedora Atomic base, how the
`/nix` store interacts with OSTree, and the rationale for the current choice.
