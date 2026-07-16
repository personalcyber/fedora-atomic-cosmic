# Package Manager Comparison: Homebrew vs Nix

This image currently uses **Homebrew** for user-level packages. Nix (with Home Manager) is a
viable alternative for a future release. This page documents both approaches, why Homebrew was
chosen for the current build, and what a Nix-based build would look like.

---

## Current approach: Homebrew

Homebrew is installed at image build time, packaged into `/usr/share/homebrew.tar.zst`, and
unpacked into `/var/home/linuxbrew` by `brew-setup.service` on first boot. See
[Homebrew](Homebrew.md) for operational details.

**What Homebrew provides in this image:**

- A familiar, macOS-compatible package manager available to all users without per-user setup
- A starting point for the primary user to add their own packages (`brew install …`)
- Coexistence with the RPM layer: Homebrew supplements it, not replaces it

**What it does not provide:**

- Version pinning — `brew install` always fetches the current formula
- Rollback — there is no "generation" concept for Homebrew installs
- Declarative config — packages are installed imperatively, not declared in a file

---

## Alternative: Nix with Home Manager

[Nix](https://nixos.org/explore/) is a purely functional package manager with a 90,000+
package repository (nixpkgs). [Home Manager](https://github.com/nix-community/home-manager)
layers on top to manage dotfiles, shell configuration, and user packages declaratively from a
single `flake.nix`.

### What Nix can and cannot replace

This is the key constraint: Nix can replace Homebrew for user-level packages, but it
**cannot** replace the RPM layer for system-level packages. The following packages must remain
as RPMs regardless of which user package manager is chosen:

| Package group | Why RPM, not Nix |
|---|---|
| `freeipa-client`, `sssd`, PAM/NSS modules | Deep PAM, NSS, and systemd integration |
| `gdm` | systemd service + PAM stack |
| `intel-media-driver`, `mesa-va-drivers-freeworld` | Kernel DRM path integration |
| `avahi`, `cups`, `firewalld` | System services with kernel/socket integration |
| `tailscale` | systemd daemon + kernel netfilter |
| `distrobox` | Relies on system Podman/container runtime |

The choice between Homebrew and Nix only affects the *user-level* layer: terminal tools
(`starship`, `eza`, `bat`, `fastfetch`), developer utilities, and shell configuration.

### The `/nix` store on Fedora Atomic

Nix stores all packages in `/nix/store`. On Fedora Atomic, the root filesystem is a read-only
OSTree commit — `/nix` can't simply be created in `build.sh` and used at runtime. The
practical solution, used by the Universal Blue (Bluefin/Aurora) images, is the
[Determinate Systems installer](https://github.com/DeterminateSystems/nix-installer): it
generates systemd mount units that mount the Nix store from a persistent location
(`/var/lib/nix`) at boot. This trades `brew-setup.service` for an equivalent Nix setup
service — the first-boot complexity is similar, but Nix manages its own lifecycle after that.

### What the build would change

**In `build.sh`:**

- Drop Homebrew: remove the tarball packaging block (`touch /.dockerenv`, `brew-install.sh`,
  `tar --zstd …`, `rm -rf /var/home/linuxbrew`)
- Drop COPR packages that Nix provides: `starship`, `eza`, `bat`, `fastfetch` are all in
  nixpkgs and don't need the `atim/starship` COPR
- Add Nix setup: either pre-install the Determinate daemon artifacts or provide a
  `ujust install-nix` recipe that runs the installer on demand
- All system-level RPMs remain unchanged

**In `system_files/`:**

- Drop `brew.sh`, `brew.fish`, the manual aliases in `terminal.sh` / `terminal.fish`
- Add a default `flake.nix` declaring the Home Manager configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, home-manager, ... }: {
    homeConfigurations."default" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [{
        home.stateVersion = "24.11";
        home.packages = with pkgs; [ fastfetch ];
        programs.starship.enable = true;
        programs.eza = {
          enable = true;
          enableBashIntegration = true;
          icons = "auto";
          git = true;
        };
        programs.bat.enable = true;
        programs.bash.shellAliases.cat = "bat --paging=never";
      }];
    };
  };
}
```

Users apply the config with `home-manager switch --flake /path/to/flake`. Adding or removing
packages means editing the flake and re-running the switch — no `brew install` at all.

---

## Side-by-side comparison

| | Homebrew (current) | Nix + Home Manager |
|---|---|---|
| **System packages** (FreeIPA, VA-API, GDM) | DNF, baked in | DNF, baked in — no change |
| **User packages** (starship, eza, bat, …) | Homebrew tarball, first-boot unpack | Home Manager flake, user-activated |
| **Dotfiles / shell config** | `system_files/` file drop | Home Manager modules (co-located with packages) |
| **Package pinning** | Loose — formula version at install time | Exact — `flake.lock` pins to a nixpkgs commit |
| **Rollback** | None | Nix generations (`home-manager generations`) |
| **COPR dependency** | `atim/starship`, `ublue-os/packages` | Only `ublue-os/packages` (for ujust) |
| **First-boot services** | `brew-setup`, `flathub-setup` | `nix-setup`, `flathub-setup` |
| **Image size** | Larger (homebrew.tar.zst in image) | Smaller image; larger runtime store |
| **Runtime store size** | Grows with `brew install` | Grows unbounded without periodic `nix gc` |
| **SELinux** | Clean | Requires policy tuning for non-standard ELF paths |
| **Learning curve** | Low — standard shell + DNF | High — Nix language, flakes, HM module system |
| **Package availability** | ~7,000 formulae | ~90,000 packages in nixpkgs |
| **Weekly CI update coverage** | RPM packages only | RPM packages only (Nix pins don't auto-update) |

---

## Why Homebrew for the current release

For a home lab image targeting FreeIPA and developer tooling, the deciding factors were:

1. **Familiar mental model.** Homebrew is widely understood by developers, especially those
   coming from macOS. The `brew install` workflow requires no new language or tooling to learn.

2. **Simpler build.** The tarball approach is straightforward bash — install, tar, delete. A
   Nix-on-ostree setup requires understanding how the Determinate installer interacts with
   systemd and OSTree, and how to debug Nix daemon failures on a non-NixOS system.

3. **No SELinux friction.** Fedora enforces SELinux by default. Nix binaries use
   `/nix/store/…/lib/ld-linux-x86-64.so.2` as their ELF interpreter, which generates SELinux
   AVC denials without policy additions. Homebrew binaries use the system loader — no policy
   changes needed.

4. **Weekly CI covers the RPM layer.** The image rebuilds weekly picking up upstream RPM
   updates. Homebrew packages update when the user runs `brew upgrade`. Nix packages would
   also require the user to run `nix flake update` + `home-manager switch` — neither approach
   provides automatic user-level package updates, so this is a wash.

---

## Nix as a future option

Nix is a realistic path for a future release variant, particularly for users who already work
with Nix or want declarative, pinned, rollback-capable user environments. The system-level
RPM layer is unchanged; only the user package and configuration layer differs.

A practical intermediate step: ship a `ujust install-nix` recipe that runs the Determinate
installer on demand, letting individual users opt in to Nix without changing the base image
for everyone.

The Universal Blue project's
[Bluefin](https://github.com/ublue-os/bluefin) and
[Aurora](https://github.com/ublue-os/aurora) images (which share the same Fedora Atomic +
COSMIC/GNOME base model) offer working examples of Nix integration on immutable Fedora.
