ARG FEDORA_VERSION=44

FROM quay.io/fedora-ostree-desktops/cosmic-atomic:${FEDORA_VERSION}

# Overlay static system files (systemd units, profile scripts, helpers)
COPY system_files/ /

# Run the build script (package installs, Homebrew packaging, service enablement)
COPY build_files/build.sh /tmp/build.sh
RUN chmod +x /tmp/build.sh && /tmp/build.sh
