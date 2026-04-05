# Scrivenix

**Scrivener 3 for Linux — automated Flatpak installer and launcher**

Scrivenix is a Flatpak application that automatically downloads, installs, and launches [Scrivener 3 for Windows](https://www.literatureandlatte.com/scrivener/) on any Linux machine that supports Flatpak and Wine. It handles the full setup process — Wine prefix initialization, dependency installation, font rendering configuration, and license activation support — through a guided graphical interface with no terminal interaction required after the initial build.

> **A valid Scrivener 3 for Windows license is required.** Scrivenix is a wrapper and installer tool, not a distribution of Scrivener. Scrivener is proprietary software developed and sold by [Literature & Latte](https://www.literatureandlatte.com).

---

## Status

**Beta** — Confirmed working on:
- Fedora (Wayland / GNOME)
- Linux Mint (X11 / Cinnamon)

Testing on additional distributions is ongoing. See [Known Issues](#known-issues) before installing.

---

## What Scrivenix Does

- Initializes a Wine 64-bit prefix isolated to the Scrivenix Flatpak sandbox
- Installs Windows core fonts, SAPI, GDI+, and .NET 4.8 via winetricks
- Downloads the official Scrivener 3 installer directly from Literature & Latte
- Removes the `texttospeech` folder that causes Scrivener to hang on "Loading Fonts"
- Configures ClearType font smoothing for readable text rendering
- Supports license activation via Scrivener's built-in Paddle licensing system
- Provides a guided display scaling tool (via winecfg) for adjusting UI size
- Maps your `~/Documents` folder into the Wine prefix so your projects are accessible
- Self-heals after Scrivener updates by re-checking compatibility fixes on every launch

---

## Requirements

- Linux with Flatpak support
- `flatpak-builder` installed
- ~3 GB free disk space (1.5 GB runtimes + Wine prefix + Scrivener)
- A valid Scrivener 3 for Windows license
- Internet connection during setup

---

## Installation

### Step 1 — Install Flatpak and flatpak-builder

Most distros include Flatpak but not flatpak-builder. Install both:

```bash
# Debian / Ubuntu / Linux Mint
sudo apt install flatpak flatpak-builder

# Fedora
sudo dnf install flatpak flatpak-builder

# Arch
sudo pacman -S flatpak flatpak-builder
```

### Step 2 — Add Flathub and install required runtimes

Run each command one at a time. Choose **user** when asked which installation to use.

Scrivenix uses the freedesktop 24.08 runtime, which is a current supported release. You should not see any end-of-life warnings during this step.

```bash
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

flatpak install --user flathub org.freedesktop.Platform//24.08

flatpak install --user flathub org.freedesktop.Sdk//24.08

flatpak install --user flathub org.winehq.Wine//stable-24.08

flatpak install --user flathub org.freedesktop.Platform.Compat.i386//24.08
```

> Total download is approximately 1.5 GB.

### Step 3 — Download and build Scrivenix

Download this repository as a ZIP file (click the green **Code** button → **Download ZIP**), extract it, open a terminal in the extracted folder, and run:

```bash
flatpak-builder --force-clean --install --user build-dir com.local.Scrivenix.yml
```

### Step 4 — Launch

Launch Scrivenix from your application menu, or run:

```bash
flatpak run com.local.Scrivenix
```

A setup wizard will guide you through the rest. See [INSTALL.txt](INSTALL.txt) for a detailed walkthrough of each setup step.

---

## Display Scaling

Scrivener's UI elements (menus, toolbar, sidebar) may appear small on some screens. After setup completes, Scrivenix prompts you to adjust display scaling via Wine Configuration. You can also access this at any time by right-clicking the Scrivenix icon in your application menu and choosing **Display & Font Settings**.

In the Wine Configuration window, go to the **Graphics** tab and increase the DPI value. 144 DPI is a good starting point for most screens.

> **Cinnamon users:** The right-click menu option may not appear in Cinnamon. If so, run:
> ```bash
> flatpak run --command=wine64 com.local.Scrivenix winecfg
> ```

---

## Cloud Storage

Scrivener projects stored in Dropbox, Google Drive, OneDrive, or any other cloud sync folder are accessible from within Scrivener — your full home directory is available inside the Flatpak sandbox. Navigate to your sync folder using Scrivener's file browser as you normally would.

---

## Known Issues

**Cinnamon + Wayland:** Shift, Ctrl, and Alt keys do not work correctly in Scrivener when running Linux Mint or any Cinnamon-based desktop under a Wayland session. This is a bug in Cinnamon's XWayland implementation and cannot be fixed at the application level. The solution is to log out and select a **Cinnamon (X11)** session from the login screen.

To check whether this affects you:
```bash
echo $XDG_CURRENT_DESKTOP $WAYLAND_DISPLAY
```
If the output contains both `Cinnamon` and a display value, switch to an X11 session. If `WAYLAND_DISPLAY` is blank, you are already on X11 and this does not apply.

**Silent exit after setup:** If Scrivener exits immediately and silently the first time it launches after setup completes, this can be caused by a Wine prefix that was built with an older version of Wine becoming incompatible with the current runtime. Use the clean reinstall commands in [Starting Fresh](#starting-fresh) to resolve it.

---

## Uninstalling

```bash
flatpak uninstall com.local.Scrivenix -y
rm -rf ~/.var/app/com.local.Scrivenix
```

---

## Starting Fresh

If setup fails or you want a completely clean reinstall, run all of
these commands from your Scrivenix project directory:

```bash
flatpak uninstall com.local.Scrivenix -y
rm -rf ~/.var/app/com.local.Scrivenix
rm -rf build-dir .flatpak-builder repo
flatpak-builder --force-clean --install --user build-dir com.local.Scrivenix.yml
flatpak run com.local.Scrivenix
```

The first two commands wipe the installed app and all Wine/Scrivener
data. The third removes the build artifacts. The fourth rebuilds and
reinstalls Scrivenix from scratch. The fifth launches it to begin
the setup wizard again.

---

## Relationship to Lutris

Scrivenix was inspired by the [Lutris](https://lutris.net) install script for Scrivener, which has been the standard method for running Scrivener on Linux. Scrivenix takes a different approach: it packages everything as a self-contained Flatpak rather than relying on a system Wine installation, which means it works consistently across distributions without requiring the user to manage Wine versions or dependencies manually.

---

## License

Scrivenix (the wrapper scripts, manifest, and supporting files) is released under the Mozilla Public License 2.0. See [LICENSE](LICENSE) for details.

Scrivener 3 is proprietary software © Literature & Latte Ltd. A valid license is required. Scrivenix does not distribute or modify Scrivener in any way.

---

## Contributing

Bug reports and feedback are welcome via [GitHub Issues](https://github.com/adgalloway/Scrivenix/issues). Please include your distro name and version, your session type (X11 or Wayland), and the full terminal output if reporting a setup failure.
