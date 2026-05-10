# Mac SSD Symlink Manager

A simple, interactive Bash script designed to free up space on smaller Mac internal drives (like the 256GB Mac Mini) by safely offloading heavy directories to an external SSD. 

Instead of dealing with the complexities of moving your entire macOS home directory to an external drive, this script selectively targets large directories (like `Downloads`, `Movies`, Xcode DerivedData, Docker volumes, and caches) and replaces them with a transparent symlink to the external SSD.

## Features

- **Interactive Menu:** Easily select which folders to offload and which to skip.
- **Smart Detection:** Automatically detects available external drives and calculates space requirements before copying.
- **Safe Copying:** Uses `rsync` for reliable copying, and keeps a local backup of the original directory until you verify the new link works.
- **Fully Reversible:** Includes a "Restore" option that pulls the data back to your internal drive and removes the symlink, returning your Mac to its original state.
- **No App Disruption:** Because it uses system-level symlinks, apps (like Xcode, Docker, Safari) read and write to these directories completely normally, unaware that the data actually lives on an external SSD.

## Installation

You can clone this directory or simply place the script in a convenient location like `~/tools/mac-ssd-linker`.

Make sure the script is executable:

```bash
chmod +x ssd_linker.sh
```

## Usage

Run the script from your terminal:

```bash
./ssd_linker.sh
```

The script will:
1. Show you a list of connected external SSDs to choose from.
2. Present a status board showing the current size of all common space-hogging directories.
3. Show you whether those directories are currently local or already symlinked.
4. Let you press `l` to **Link** directories to the SSD or `r` to **Restore** them back to local storage.

## Important Notes & Best Practices

- **Drive Names:** macOS mounts external drives based on their name (e.g., `/Volumes/Samsung_T7`). Once you set up symlinks, **do not rename your external SSD**, otherwise the links will break.
- **Rebooting:** The symlinks are permanent. However, when you reboot your Mac, the external SSD might take a few seconds to mount. If you click a symlinked folder before the drive mounts, macOS might throw a "destination cannot be found" error. It will fix itself the moment the drive finishes mounting.
- **Do not unplug while in use:** If you abruptly unplug the external SSD while an application (like Docker or Xcode) is actively writing to a symlinked folder, that application will likely crash.

## Disclaimer

Use at your own risk. Always ensure you have a Time Machine backup of your Mac before performing mass file migrations.
