#!/usr/bin/env bash
#
# Fedora Workstation Baseline Deployment
# Run AFTER first boot into an installed Fedora Workstation (GNOME).
# Safe to re-run. Keeps going if one item fails and lists failures at the end.
set -uo pipefail

FAILED=()
info() { echo -e "\033[1m\033[0;32m==>\033[0m $1"; }
warn() { echo -e "\033[1m\033[1;33m==>\033[0m $1"; }

if [ "$(id -u)" -eq 0 ]; then
  echo "Don't run this as root. Run as your normal user; it calls sudo where needed." >&2
  exit 1
fi
if ! command -v dnf &>/dev/null; then
  echo "dnf not found. This script is for Fedora." >&2
  exit 1
fi

echo ""
echo "Fedora Baseline Deployment"
echo "──────────────────────────────────────────"
echo ""

# ── Phase 1: CPU microcode ────────────────────────────────────────────────
info "Detecting CPU vendor..."
CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
case "$CPU_VENDOR" in
  GenuineIntel)
    info "Intel CPU: installing microcode_ctl"
    sudo dnf install -y microcode_ctl </dev/null || FAILED+=("microcode_ctl")
    ;;
  AuthenticAMD)
    info "AMD CPU: microcode ships inside linux-firmware, nothing to install"
    ;;
  *)
    warn "Could not determine CPU vendor. Skipping microcode."
    ;;
esac
echo ""

# ── Phase 2: Base packages ────────────────────────────────────────────────
info "Installing base tooling..."
install_rpm() {
  local pkg="$1"
  if rpm -q "$pkg" &>/dev/null; then
    echo "  [skip] $pkg"
  else
    echo "  [install] $pkg"
    sudo dnf install -y "$pkg" </dev/null || FAILED+=("$pkg")
  fi
}
for pkg in git curl firefox flatpak fastfetch duf glances; do
  install_rpm "$pkg"
done
sudo dnf install -y @development-tools </dev/null || FAILED+=("development-tools group")
echo ""

# ── Phase 3: Flathub (unfiltered) ─────────────────────────────────────────
info "Setting up Flathub..."
if flatpak remote-list | grep -q '^flathub'; then
  # Fedora can ship Flathub with a filter that hides some apps; remove it.
  sudo flatpak remote-modify --no-filter flathub 2>/dev/null || true
else
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
    || FAILED+=("flathub remote")
fi
echo ""

# ── Phase 4: Update workflow (one script, one launcher) ──────────────────
info "Setting up update launcher..."
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

cat > "$HOME/.local/bin/update-workstation.sh" << 'SCRIPT_EOF'
#!/usr/bin/env bash
clear
echo "=== Updating system (dnf) ==="
sudo dnf upgrade --refresh -y
echo ""
echo "=== Updating Flatpaks ==="
flatpak update -y
echo ""
echo "Press Enter to close..."
read -r
SCRIPT_EOF
chmod +x "$HOME/.local/bin/update-workstation.sh"

if command -v ptyxis &>/dev/null; then
  TERM_EXEC="ptyxis --"
elif command -v gnome-terminal &>/dev/null; then
  TERM_EXEC="gnome-terminal --"
elif command -v kgx &>/dev/null; then
  TERM_EXEC="kgx -e"
else
  TERM_EXEC="xterm -e"
fi

cat << DESKTOP_EOF > "$HOME/.local/share/applications/update-workstation.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Update Workstation
Comment=Updates system packages and Flatpaks
Exec=$TERM_EXEC "$HOME/.local/bin/update-workstation.sh"
Terminal=false
Icon=system-software-update
Categories=System;Settings;
Keywords=update;upgrade;dnf;flatpak;
DESKTOP_EOF
update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
echo ""

# ── Phase 5: App loadout (shared with clone-panda-msi) ───────────────────
info "Installing app loadout from clone-panda-msi..."
LOADOUT_DIR="$HOME/.local/share/clone-panda-msi"
if [ -d "$LOADOUT_DIR/.git" ]; then
  git -C "$LOADOUT_DIR" pull --ff-only
else
  git clone https://github.com/GrimDaTrashPanda/clone-panda-msi.git "$LOADOUT_DIR"
fi
bash "$LOADOUT_DIR/install-loadout.sh" || FAILED+=("app loadout")
echo ""

if [ ${#FAILED[@]} -gt 0 ]; then
  warn "Deployment finished, but these failed:"
  printf '  %s\n' "${FAILED[@]}"
else
  info "Deployment complete."
fi
echo ""
echo "Next: press Super, search 'Update', and confirm the launcher appears."
