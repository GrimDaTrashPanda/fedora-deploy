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
for pkg in git curl firefox flatpak fastfetch duf glances pciutils; do
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

# ── Phase 4: RPM Fusion + codecs ──────────────────────────────────────────
info "Setting up RPM Fusion and codecs..."
FEDORA_VER=$(rpm -E %fedora)
if rpm -q rpmfusion-free-release rpmfusion-nonfree-release &>/dev/null; then
  echo "  [skip] RPM Fusion already enabled"
else
  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" \
    </dev/null || FAILED+=("RPM Fusion repos")
fi

# Cisco OpenH264 (Fedora-managed repo, disabled by default)
sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1 </dev/null || FAILED+=("openh264 repo")
for pkg in openh264 gstreamer1-plugin-openh264 mozilla-openh264; do
  install_rpm "$pkg"
done

# Full ffmpeg replaces Fedora's codec-limited ffmpeg-free
if rpm -q ffmpeg &>/dev/null; then
  echo "  [skip] full ffmpeg already installed"
else
  echo "  [install] ffmpeg (swapping out ffmpeg-free)"
  sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing </dev/null \
    || sudo dnf install -y ffmpeg --allowerasing </dev/null \
    || FAILED+=("ffmpeg swap")
fi

# GStreamer codec groups
sudo dnf group install -y multimedia sound-and-video \
  --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin </dev/null \
  || FAILED+=("multimedia codec groups")

# Hardware video acceleration, matched to the GPU
for pkg in ffmpeg-libs libva libva-utils; do
  install_rpm "$pkg"
done
GPU_INFO=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)
if echo "$GPU_INFO" | grep -qi 'intel'; then
  install_rpm intel-media-driver
fi
if echo "$GPU_INFO" | grep -qiE 'advanced micro devices|radeon'; then
  install_rpm mesa-va-drivers-freeworld
fi
if echo "$GPU_INFO" | grep -qi 'nvidia'; then
  warn "NVIDIA GPU detected. Drivers are not installed by this script (akmod-nvidia from RPM Fusion is the usual route)."
fi
echo ""

# ── Phase 5: Update workflow (one script, one launcher) ──────────────────
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

# ── Phase 6: App loadout (shared with clone-panda-msi) ───────────────────
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
