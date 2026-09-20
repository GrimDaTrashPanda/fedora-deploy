# Fedora Workstation Baseline Deployment

A single, idempotent script that takes a fresh Fedora Workstation install (GNOME) to a provisioned baseline: base tooling, RPM Fusion and codecs, the shared app loadout, and an update launcher.

## Prerequisites

- Fedora Workstation already installed (current release, dnf5)
- An internet connection

## Usage

    git clone https://github.com/GrimDaTrashPanda/fedora-deploy.git
    cd fedora-deploy
    bash deploy.sh

Run as your normal user, not root. It calls `sudo` where needed.

## What it does

1. Installs Intel microcode if applicable (AMD microcode ships inside `linux-firmware`)
2. Installs base tooling: git, curl, firefox, flatpak, fastfetch, duf, glances, pciutils, and the Development Tools group
3. Makes sure Flathub is configured with no app filter (Fedora can ship it filtered)
4. Enables RPM Fusion (Free and Nonfree) and Fedora's OpenH264 repo, swaps `ffmpeg-free` for the full `ffmpeg`, installs the `multimedia` and `sound-and-video` groups, and adds the VA-API driver for your GPU (Intel: `intel-media-driver`, AMD: `mesa-va-drivers-freeworld`)
5. Creates an `update-workstation.sh` script and a GNOME launcher that updates dnf packages and Flatpaks in one pass
6. Installs the app loadout from [clone-panda-msi](https://github.com/GrimDaTrashPanda/clone-panda-msi): its Flathub list, plus Discord, Kdenlive, OBS, Meld, and Telegram as Flatpaks

Firefox needs no Wayland setting on Fedora, since it's the default there.

## After running

Press **Super**, search "Update", and confirm the launcher appears.

## GPU notes

NVIDIA drivers are not installed by this script. If it detects an NVIDIA GPU it says so and stops there. `akmod-nvidia` from RPM Fusion is the usual route, and it's a decision worth making by hand (Secure Boot needs key enrollment for it).

## Safe to re-run

Every install step checks for an existing package first. If one item fails, the script keeps going and lists the failures at the end.

## Changing the apps

The app list isn't in this repo. It lives in [clone-panda-msi](https://github.com/GrimDaTrashPanda/clone-panda-msi). Edit `pkglist-flatpak.txt` there and every deploy repo picks it up on its next run.
