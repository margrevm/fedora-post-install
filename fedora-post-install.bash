#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Post-installation configuration script for Fedora Workstation
#
# Copyright (c) 2026 Mike Margreve (mike.margreve@outlook.com)
# Licensed under the MIT License. You may copy, modify, and distribute this
# script under the terms of that license.
#
# Purpose
#   Automates common post-install steps on a freshly installed workstation to
#   establish a consistent baseline for development and daily use.
#
# Usage
#   1) Review the script before running and adjust variables to your needs.
#   2) Execute:
#        chmod +x post-install.sh
#        ./post-install.sh
#
# Notes
#   - This script is intentionally interactive and will prompt before major
#     phases and on non-fatal errors.
#   - Administrative privileges (sudo) are required for system changes.
# -----------------------------------------------------------------------------

prompt_continue() {
  local prompt="${1:-Continue?}"
  printf "%s [y/N]: " "$prompt"
  read -r ans
  case "${ans:-}" in
    y|Y|yes|YES) return 0 ;;
    *) echo "Aborted by user."; exit 1 ;;
  esac
}

log_section() {
  printf "\n[%s]\n" "$1"
  prompt_continue "Continue"
}

log_step() {
  printf "➜ %s\n" "$1"
}

log_warn() {
  printf "WARN: %s\n" "$1"
  prompt_continue "Continue anyway"
}

FEDORA_VERSION="$(rpm -E %fedora)"

# ---------------------------------------------------
# Creating folder structure
# ---------------------------------------------------
log_section "Creating the folder structure"

CREATE_DIRS=(
  "$HOME/projects"
  "$HOME/scripts"
  "$HOME/src"
  "$HOME/tmp"
)

REMOVE_DIRS=(
)

log_step "Creating directories..."
mkdir -pv "${CREATE_DIRS[@]}"

log_step "Removing default directories if empty..."
for d in "${REMOVE_DIRS[@]}"; do
  if [[ -d "$d" ]]; then
    if [[ -z "$(ls -A "$d")" ]]; then
      rmdir -v "$d"
    else
      printf "➜ Skipping %s (not empty)\n" "$d"
    fi
  fi
done

# ---------------------------------------------------
# Symbolic links
# ---------------------------------------------------
log_section "Symbolic links"

log_step "Linking GVFS mountpoint to ~/smb (if available)..."
if [[ -e "$HOME/smb" ]]; then
  log_warn "$HOME/smb already exists; will not overwrite."
else
  ln -s "/run/user/$UID/gvfs" "$HOME/smb" || log_warn "Failed to create ~/smb symlink (GVFS may not be running)."
fi

# ---------------------------------------------------
# DNF repositories and packages
# ---------------------------------------------------
log_section "Installing DNF packages"

log_step "Installing DNF plugin helpers (dnf-plugins-core)..."
sudo dnf install dnf-plugins-core

log_step "Enabling RPM Fusion (free + nonfree)..."
sudo dnf install \
  "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
  "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"

log_step "Adding Microsoft VS Code repository..."
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" \
  | sudo tee /etc/yum.repos.d/vscode.repo

log_step "Refreshing and upgrading system packages..."
sudo dnf upgrade --refresh

# Main packages (no gedit, no xclip; Wayland clipboard via wl-clipboard)
DNF_INSTALL_PACKAGES=(
  tree
  fastfetch
  htop

  gnome-tweaks
  gnome-shell-extension-gsconnect

  python3
  python3-pip
  git
  curl
  wget
  unzip
  less
  vim
  colordiff
  stow
  net-tools
  nmap

  wl-clipboard

  java-latest-openjdk
  java-latest-openjdk-devel

  libreoffice
  drawing
  pdfarranger
  xournalpp

  heif-pixbuf-loader

  chromium
  code
  lutris
  steam

  bat

  flatpak
  tailscale
)

log_step "Installing packages..."
sudo dnf install "${DNF_INSTALL_PACKAGES[@]}"

log_step "Installing multimedia codecs (RPM Fusion)..."
sudo dnf group upgrade --with-optional Multimedia --allowerasing

DNF_REMOVE_PACKAGES=(
  geary
  gnome-contacts
)

log_step "Removing unwanted packages (if present)..."
for pkg in "${DNF_REMOVE_PACKAGES[@]}"; do
  rpm -q "$pkg" && sudo dnf remove "$pkg" || printf "➜ Skipping %s (not installed)\n" "$pkg"
done

log_step "Removing unused dependencies..."
sudo dnf autoremove

# ---------------------------------------------------
# Microsoft core fonts (Option A)
# ---------------------------------------------------
log_section "Installing Microsoft core fonts (lpf-mscore-fonts)"

log_step "Installing lpf-mscore-fonts (RPM Fusion nonfree)..."
sudo dnf install lpf-mscore-fonts

log_step "Running lpf update (downloads/builds/installs fonts)..."
sudo lpf update

log_step "Updating font cache..."
sudo fc-cache -f

# ---------------------------------------------------
# NVIDIA drivers (RTX 4060) - RPM Fusion akmod
# ---------------------------------------------------
log_section "NVIDIA drivers (RTX 4060)"

log_step "Checking Secure Boot status (mokutil)..."
mokutil --sb-state || log_warn "mokutil not available; cannot check Secure Boot status."

log_step "Installing build prerequisites for akmods..."
sudo dnf install kernel-devel kernel-headers gcc make akmods dkms

log_step "Installing NVIDIA driver stack (akmod-nvidia)..."
sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda nvidia-settings

log_step "Building NVIDIA kernel module (akmods)..."
sudo akmods --force

log_step "Regenerating initramfs (dracut)..."
sudo dracut --force

log_warn "Reboot is strongly recommended after NVIDIA driver installation (and may be required, especially with Secure Boot)."

# ---------------------------------------------------
# Installing flatpak packages
# ---------------------------------------------------
log_section "Installing flatpak packages"

FLATPAK_INSTALL_PACKAGES=(
  com.bitwarden.desktop
  com.stremio.Stremio
  com.spotify.Client
  org.ferdium.Ferdium
  com.discordapp.Discord
  net.cozic.joplin_desktop
  com.mattjakeman.ExtensionManager
  com.synology.SynologyDrive
)

log_step "Add flatpak repositories..."
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

log_step "Install flatpak packages..."
sudo flatpak install --system "${FLATPAK_INSTALL_PACKAGES[@]}"

log_step "Update flatpak packages..."
sudo flatpak update

# ---------------------------------------------------
# Custom installs
# ---------------------------------------------------
log_section "Custom installs"

# ---------------------------------------------------
# Tailscale
# ---------------------------------------------------
log_section "Tailscale"

log_step "Enable and start tailscaled..."
sudo systemctl enable --now tailscaled
log_warn "Run 'sudo tailscale up' manually to authenticate this machine."

# ---------------------------------------------------
# GNOME extensions (enable GSConnect only)
# ---------------------------------------------------
log_section "GNOME extensions"

log_step "Enable GSConnect extension..."
gnome-extensions enable gsconnect@andyholmes.github.io || log_warn "Failed to enable GSConnect (extension may not be installed for this user/session, or gnome-extensions may not be available)."

# ---------------------------------------------------
# Create SSH key
# ---------------------------------------------------
log_section "Create SSH key"

mkdir -p "$HOME/.ssh"

if [[ -f "$HOME/.ssh/id_rsa" || -f "$HOME/.ssh/id_rsa.pub" ]]; then
  log_warn "SSH key ~/.ssh/id_rsa already exists; not overwriting."
else
  log_step "Generating SSH key..."
  ssh-keygen -t rsa -b 4096 -C "mike.margreve@outlook.com"
fi

log_step "Starting ssh-agent and adding key..."
eval "$(ssh-agent -s)"
ssh-add "$HOME/.ssh/id_rsa"

log_step "Copying public key to clipboard with wl-copy..."
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  wl-copy < "$HOME/.ssh/id_rsa.pub" || log_warn "wl-copy failed. Is wl-clipboard installed and are you in a Wayland session?"
else
  log_warn "WAYLAND_DISPLAY not set (likely not a Wayland session). Skipping clipboard copy."
  printf "➜ Your public key is at: %s\n" "$HOME/.ssh/id_rsa.pub"
fi

log_step "Opening GitHub SSH key page..."
xdg-open https://github.com/settings/ssh/new

# ---------------------------------------------------
# Clone git repos
# ---------------------------------------------------
log_section "Cloning git repos"

cd "$HOME/scripts"

git clone git@github.com:margrevm/ubuntu-post-install.git || log_warn "Clone failed (already exists or access issue)."
git clone git@github.com:margrevm/ubuntu-update.git || log_warn "Clone failed (already exists or access issue)."
git clone git@github.com:margrevm/ubuntu-cleanup.git || log_warn "Clone failed (already exists or access issue)."

# ---------------------------------------------------
# Dotfiles via stow
# ---------------------------------------------------
log_section "Dotfiles (stow)"

cd "$HOME/scripts"
git clone git@github.com:margrevm/dotfiles.git || log_warn "Clone failed (already exists or access issue)."

log_step "Stowing dotfiles with --adopt..."
stow -d "$HOME/scripts/dotfiles" -t "$HOME" . --adopt

log_step "Resetting dotfiles repo to clean state..."
cd "$HOME/scripts/dotfiles"
git reset --hard

# ---------------------------------------------------
# Summary + reboot-required check
# ---------------------------------------------------
log_section "Summary"

log_step "System info..."
fastfetch

log_step "Checking if a reboot is required..."
set +e
sudo dnf needs-restarting -r
rc=$?
set -e

case "$rc" in
  0) printf "➜ Reboot not required.\n" ;;
  1) printf "➜ Reboot is recommended.\n" ;;
  *) printf "➜ needs-restarting failed with exit code %d\n" "$rc"; exit "$rc" ;;
esac

printf "\n[Installation completed!]\n"
cd "$HOME"
