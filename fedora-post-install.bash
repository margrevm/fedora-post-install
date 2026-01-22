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
  printf "\n\033[1;34m[%s]\033[0m\n" "$1"
  prompt_continue "Continue"
}

log_step() {
  printf "\033[0;34m➜ %s\033[0m\n" "$1"
}

log_warn() {
  printf "\033[1;33mWARN: %s\033[0m\n" "$1"
  prompt_continue "Continue anyway"
}


set_gsetting() {
  local schema="$1"
  local key="$2"
  local value="$3"
  local desc="${4:-}"

  if [[ -n "$desc" ]]; then
    log_step "$desc"
  fi

  if gsettings writable "$schema" "$key" >/dev/null 2>&1; then
    gsettings set "$schema" "$key" "$value"
  else
    log_warn "gsettings key not available: $schema $key"
  fi
}

FEDORA_VERSION="$(rpm -E %fedora)"

# LOAD CONFIGURATION
CONFIG_FILE="${CONFIG_FILE:-$(dirname "$0")/pc-mike.cfg}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
else
  printf "Config file not found: %s\n" "$CONFIG_FILE" >&2
  exit 1
fi

# ---------------------------------------------------
# Select hostname
# ---------------------------------------------------
log_section "Setting hostname"

NEW_HOSTNAME="pc-mike"

log_step "Set hostname to $NEW_HOSTNAME..."

prompt_continue "Run: sudo hostnamectl set-hostname $NEW_HOSTNAME"
sudo hostnamectl set-hostname "$NEW_HOSTNAME"

# ---------------------------------------------------
# Creating folder structure
# ---------------------------------------------------
log_section "Creating the folder structure"

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
#log_section "Symbolic links"

# ... nothing here yet ...

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

log_step "Adding non-default repositories..."

# Microsoft VS Code repo:
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" \
  | sudo tee /etc/yum.repos.d/vscode.repo

log_step "Refreshing and upgrading system packages..."
sudo dnf upgrade --refresh

log_step "Installing packages..."
sudo dnf install "${DNF_INSTALL_PACKAGES[@]}"

log_step "Installing multimedia codecs (RPM Fusion)..."
sudo dnf group install --with-optional multimedia --allowerasing

log_step "Removing unwanted packages (if present)..."
for pkg in "${DNF_REMOVE_PACKAGES[@]}"; do
  rpm -q "$pkg" && sudo dnf remove "$pkg" || printf "➜ Skipping %s (not installed)\n" "$pkg"
done

log_step "Removing unused dependencies..."
sudo dnf autoremove

# ---------------------------------------------------
# Fonts
# ---------------------------------------------------
log_section "Installing fonts"

if command -v fc-match >/dev/null 2>&1 && fc-match -f '%{family}\n' 'Arial' | grep -qi 'Arial'; then
  log_step "Arial font found; skipping ms-core-fonts install"
else
  sudo lpf update || true

  log_step "lpf install ms-core-fonts"
  sudo lpf install ms-core-fonts

  log_step "Updating font cache..."
  sudo fc-cache -f
fi

# ---------------------------------------------------
# Drivers
# ---------------------------------------------------
# NVIDIA drivers (RTX 4060)
log_section "NVIDIA drivers (RTX 4060)"

log_step "Checking Secure Boot status (mokutil)..."
mokutil --sb-state || log_warn "mokutil not available; cannot check Secure Boot status."

if rpm -q akmod-nvidia xorg-x11-drv-nvidia >/dev/null 2>&1; then
  log_step "NVIDIA driver packages already installed"
fi

if lsmod | grep -Eq '^nvidia|^nvidia_drm|^nvidia_uvm|^nvidia_modeset'; then
  log_step "NVIDIA driver modules already loaded; skipping akmods/dracut"
else
  log_step "Building NVIDIA kernel module (akmods)..."
  sudo akmods --force

  log_step "Regenerating initramfs (dracut)..."
  sudo dracut --force

  log_warn "Reboot is strongly recommended after NVIDIA driver installation (and may be required, especially with Secure Boot)."
fi

# ---------------------------------------------------
# Installing flatpak packages
# ---------------------------------------------------
log_section "Installing flatpak packages"

FLATHUB_REMOTE_URL="https://flathub.org/repo/flathub.flatpakrepo"

log_step "Add flatpak repositories..."
sudo flatpak remote-add --if-not-exists flathub "$FLATHUB_REMOTE_URL"

log_step "Install flatpak packages..."
sudo flatpak install --system "${FLATPAK_INSTALL_PACKAGES[@]}"

log_step "Update flatpak packages..."
sudo flatpak update

# ---------------------------------------------------
# Custom installs
# ---------------------------------------------------
# log_section "Custom installs"

# ... nothing here yet ...

# ---------------------------------------------------
# Tailscale
# ---------------------------------------------------
log_section "Tailscale"

if ! command -v tailscale >/dev/null 2>&1; then
  log_warn "Tailscale not installed; skipping"
else
  if systemctl is-active --quiet tailscaled; then
    log_step "tailscaled already running"
  else
    log_step "Enable and start tailscaled..."
    sudo systemctl enable --now tailscaled || log_warn "Failed to enable/start tailscaled"
  fi

  if tailscale status >/dev/null 2>&1; then
    log_step "Tailscale already authenticated; skipping login"
  else
    log_step "Authenticate Tailscale (opens browser for login)"
    sudo tailscale up || log_warn "tailscale up failed (authentication may be required)"
  fi
fi

# ---------------------------------------------------
# GNOME settings
# ---------------------------------------------------
log_section "GNOME settings"

log_step "Enable Gnome extensions..."
gnome-extensions enable gsconnect@andyholmes.github.io || log_warn "Failed to enable GSConnect (extension may not be installed for this user/session, or gnome-extensions may not be available)."

log_step "General GNOME settings..."
set_gsetting org.gnome.desktop.sound event-sounds false "Alert sounds: off"
set_gsetting org.gnome.desktop.interface enable-hot-corners false "Hot corner: off"
set_gsetting org.gnome.desktop.notifications show-in-lock-screen false "Lock screen notifications: off"
set_gsetting org.gnome.desktop.session idle-delay 900 "Power saving idle delay: 15 minutes"
set_gsetting org.gnome.desktop.screensaver lock-delay 300 "Screen lock delay: 5 minutes"
set_gsetting org.gnome.desktop.interface power-profile "performance" "Power profile: performance"
set_gsetting org.gnome.system.locale region "fr_BE.UTF-8" "Formats: Belgium"

log_step "Files (Nautilus) settings"
set_gsetting org.gnome.nautilus.preferences sort-directories-first true "Sort folders before files"
set_gsetting org.gnome.nautilus.preferences recursive-search "always" "Search all locations"
set_gsetting org.gnome.nautilus.preferences show-image-thumbnails "always" "Enable thumbnails for all folders"

log_section "Text Editor settings"
set_gsetting org.gnome.TextEditor show-line-numbers true "Display line numbers: on"
set_gsetting org.gnome.TextEditor highlight-current-line true "Highlight current line: on"
set_gsetting org.gnome.TextEditor show-overview-map true "Display overview map: on"
set_gsetting org.gnome.TextEditor indent-style "'space'" "Indentation: spaces"
set_gsetting org.gnome.TextEditor tab-width 4 "Spaces per tab: 4"
set_gsetting org.gnome.TextEditor indent-width 4 "Spaces per indent: 4"

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

git clone git@github.com:margrevm/fedora-post-install.git || log_warn "Clone failed (already exists or access issue)."
git clone git@github.com:margrevm/fedora-update.git || log_warn "Clone failed (already exists or access issue)."
git clone git@github.com:margrevm/housekeep.git || log_warn "Clone failed (already exists or access issue)."

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

printf "\n[Installation completed!]\n"
log_step "Now reboot..."
cd "$HOME"
