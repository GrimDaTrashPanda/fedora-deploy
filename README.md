# Fedora Workstation Baseline Deployment

A single, idempotent script that takes a fresh Fedora Workstation install (GNOME) to a provisioned baseline: base tooling, the shared app loadout, and an update launcher.

## Prerequisites

- Fedora Workstation already installed (current release)
- An internet connection

## Usage

    git clone https://github.com/GrimDaTrashPanda/fedora-deploy.git
    cd fedora-deploy
    bash deploy.sh

Run as your normal user, not root. It calls `sudo` where needed.

## What it does

1. Installs Intel microcode if applicable (AMD microcode ships inside `linux-firmware`)
2. Installs base tooling: git, curl, firefox, flatpak, fastfetch, duf, glances, and the Development Tools group
3. Makes sure Flathub is configured with no app filter (Fedora can ship it filtered)
4. Creates an `update-workstation.sh` script and a GNOME launcher that updates dnf packages and Flatpaks in one pass
5. Installs the app loadout from [clone-panda-msi](https://github.com/GrimDaTrashPanda/clone-panda-msi): its Flathub list, plus Discord, Kdenlive, OBS, Meld, and Telegram as Flatpaks

Firefox needs no Wayland setting on Fedora, since it's the default there.

## After running

Press **Super**, search "Update", and confirm the launcher appears.

## Why RPM Fusion isn't enabled

The apps that need patent-encumbered codecs (VLC, Kdenlive, OBS) come from Flathub and bring their own. Add RPM Fusion yourself if you hit a codec gap in a native package.

## Safe to re-run

Every install step checks for an existing package first. If one item fails, the script keeps going and lists the failures at the end.

## Changing the apps

The app list isn't in this repo. It lives in [clone-panda-msi](https://github.com/GrimDaTrashPanda/clone-panda-msi). Edit `pkglist-flatpak.txt` there and every deploy repo picks it up on its next run.
