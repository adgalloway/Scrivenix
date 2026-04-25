#!/bin/bash
# =============================================================================
# Scrivenix — Scrivener 3 for Linux via Wine/Flatpak
# =============================================================================

# --- PATHS & ENVIRONMENT -----------------------------------------------------
export WINEPREFIX="$HOME/.var/app/com.local.Scrivenix/wine"
export WINEARCH=win64
export WINEDEBUG=-all

# Strip host Wine/gaming environment variables that bleed into the Flatpak
# sandbox from gaming or pro-audio setups and can interfere with wineboot,
# winetricks, or display connections. None of these are used by Scrivener.
unset WINEESYNC WINEFSYNC WINEDLLOVERRIDES LD_PRELOAD \
      WINE_LARGE_ADDRESS_AWARE MANGOHUD MANGOHUD_CONFIG \
      DXVK_STATE_CACHE_PATH PROTON_NO_ESYNC PROTON_NO_FSYNC \
      STAGING_SHARED_MEMORY STAGING_WRITECOPY WINEFSYNC_FUTEX2 \
      WINE_MONO_OVERRIDES GDK_BACKEND

# The Flatpak Wine base only ships 64-bit libraries (x86_64-unix/windows).
# /app/bin/wine is the 32-bit loader and will crash immediately because
# i386-unix/ntdll.so is absent. Force all Wine tools — including winetricks
# and the wineboot wrapper — to use wine64 by setting these three variables.
# The Compat.i386 extension declared in the manifest provides 32-bit libraries
# for child processes like Paddle.exe (Scrivener's license activation binary).
# Ensure /app/bin is on PATH so Wine binaries (wine, wine64, wineserver,
# winetricks, cabextract) are always findable regardless of how the script
# is invoked — e.g. via flatpak run --command=, desktop actions, or app drawer.
export PATH="/app/bin:$PATH"

export WINE=/app/bin/wine
# Wine 11 (shipped with the 24.08 runtime) unified wine and wine64 into a
# single binary under the new WoW64 architecture. /app/bin/wine64 no longer
# exists as a static file — it is only available as a wrapper set up by the
# Wine Flatpak base entry script during a normal launch. When the script is
# invoked via --command= (desktop actions, right-click menu), that entry
# script is bypassed and wine64 is unavailable. Point WINELOADER at the
# static /app/bin/wine binary, which handles 64-bit under Wine 11 WoW64.
export WINELOADER=/app/bin/wine
export WINESERVER=/app/bin/wineserver

CACHE_DIR="$HOME/.var/app/com.local.Scrivenix/cache"
SCRIV_EXE="$WINEPREFIX/drive_c/Program Files/Scrivener3/Scrivener.exe"
SETUP_DONE_FLAG="$WINEPREFIX/.setup_done"
SPEECH_DIR="$WINEPREFIX/drive_c/Program Files/Scrivener3/texttospeech"
# winetricks writes this file on successful dotnet48 completion.
# Used as the primary verification signal — more reliable than registry
# queries under Wine's WoW64 mode (Wine 11+), where the 64-bit registry
# view used by wine64 reg query may not reflect what the installer wrote.
DOTNET_WORKAROUND_FLAG="$WINEPREFIX/dosdevices/c:/windows/dotnet48.installed.workaround"

# --- HELPERS -----------------------------------------------------------------

notify() {
    zenity --notification --text="Scrivenix: $1" 2>/dev/null || true
}

info() {
    zenity --info \
        --title="Scrivenix" \
        --text="$1" \
        --width=400 \
        2>/dev/null
}

warn() {
    zenity --warning \
        --title="Scrivenix" \
        --text="$1" \
        --width=400 \
        2>/dev/null
}

error_exit() {
    zenity --error \
        --title="Scrivenix" \
        --text="$1" \
        --width=400 \
        2>/dev/null
    exit 1
}

# --- PERSISTENT SETUP PROGRESS WINDOW ---------------------------------------
# A single zenity progress window stays open for the entire first-run setup.
# Text updates tell the user what is happening at each step.
# The window is not dismissable — there is no OK/Cancel button.
# Percentage values are weighted by approximate real-world install time:
#
#   5%  — Wine prefix init        (~1 min)
#  10%  — Core Fonts              (~1-2 min)
#  15%  — .NET 4.8 starting       (~5-10 min — dominates total time)
#  45%  — .NET 4.8 complete
#  50%  — Windows 10 mode         (~30 sec)
#  65%  — Scrivener download      (~3-5 min)
#  85%  — Scrivener installer     (~2-3 min)
#  95%  — Cleanup and fonts       (~1 min)
# 100%  — Complete
#
# Usage:
#   setup_progress_open          — open the window
#   setup_progress_update N "msg" — set percentage and message
#   setup_progress_close         — close the window

setup_progress_open() {
    # Open a persistent write-only pipe to zenity.
    # DISPLAY is set explicitly to ensure the window appears whether launched
    # from a terminal or an app drawer.
    exec 3> >(DISPLAY="${DISPLAY:-:0}" zenity --progress \
        --auto-close \
        --no-cancel \
        --title="Scrivenix — First-Run Setup" \
        --text="Preparing..." \
        --percentage=0 \
        --width=480 \
        2>/dev/null)
    SETUP_PROGRESS_OPEN=1
}

setup_progress_update() {
    local PERCENT="$1"
    local MESSAGE="$2"
    if [ -n "$SETUP_PROGRESS_OPEN" ]; then
        # Sending a bare number sets the percentage.
        # A line starting with # updates the displayed text.
        echo "$PERCENT" >&3
        echo "# $MESSAGE" >&3
    fi
}

setup_progress_close() {
    if [ -n "$SETUP_PROGRESS_OPEN" ]; then
        echo "100" >&3
        exec 3>&-
        unset SETUP_PROGRESS_OPEN
    fi
}

# --- SPEECH-TO-TEXT REMOVAL --------------------------------------------------
# Scrivener enumerates SAPI/TTS voices during startup — even during the
# "Loading Fonts" phase — and will hang indefinitely on a bare Wine prefix
# if the texttospeech folder is present.
#
# Removing the directory eliminates the code path entirely so Scrivener
# bypasses the enumeration, allowing a smooth launch without needing
# the heavy Windows Speech API winetricks stub.

remove_speech_to_text() {
    if [ -d "$SPEECH_DIR" ]; then
        rm -rf "$SPEECH_DIR"
    fi
}

# --- FONT SMOOTHING CONFIGURATION --------------------------------------------
# Applied once during first-run setup. Sets ClearType (RGB subpixel)
# antialiasing and font smoothing flags. DPI/scaling is handled by the
# user via winecfg (Graphics tab) rather than programmatically, since
# Wine reads DPI differently depending on the display backend (X11 vs
# XWayland vs Wayland) and winecfg is the only reliable cross-distro method.
#
# Also callable on demand via --reconfigure-fonts to recover from a Scrivener
# update or Wine runtime change that resets font rendering settings.

configure_fonts() {
    winetricks fontsmooth=rgb >/dev/null 2>&1
    "$WINELOADER" reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothing            /t REG_SZ    /d 2    /f >/dev/null 2>&1
    "$WINELOADER" reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingType        /t REG_DWORD /d 2    /f >/dev/null 2>&1
    "$WINELOADER" reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingGamma       /t REG_DWORD /d 1000 /f >/dev/null 2>&1
    "$WINELOADER" reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingOrientation /t REG_DWORD /d 1    /f >/dev/null 2>&1
}

# --- WINECFG LAUNCHER --------------------------------------------------------
# Launched via the right-click "Display & Font Settings" desktop action.
# Opens Wine's built-in configuration tool directly against the Scrivenix
# prefix. The Graphics tab allows the user to set DPI/scaling, which is
# the reliable cross-distro method for adjusting Scrivener's UI size.

launch_winecfg() {
    "$WINELOADER" winecfg
}

# --- ARGUMENT HANDLING -------------------------------------------------------

case "$1" in
    --winecfg)
        launch_winecfg
        exit 0
        ;;
    --reconfigure-fonts)
        # Re-applies ClearType font smoothing settings to the Wine prefix.
        # Useful after a Scrivener update or Wine runtime change that resets
        # font rendering. Does not affect DPI — adjust that via --winecfg.
        configure_fonts
        info "Font configuration has been re-applied.\n\nClearType font smoothing settings have been restored.\nRestart Scrivener for the changes to take effect."
        exit 0
        ;;
esac

# --- WAYLAND / COMPOSITOR WARNING --------------------------------------------
# Shift, Ctrl, and Alt modifier keys do not work correctly in Wine when running
# under Cinnamon's Wayland compositor. This is a known bug in Cinnamon's
# XWayland implementation and cannot be fixed at the application level.
#
# This check targets Cinnamon + Wayland specifically. Other desktop
# environments (GNOME, KDE Plasma) have more mature Wayland/XWayland
# implementations and do not exhibit this problem, so we do NOT warn users
# on those desktops even if $WAYLAND_DISPLAY is set.

if [ -n "$WAYLAND_DISPLAY" ]; then
    CURRENT_DE="${XDG_CURRENT_DESKTOP:-unknown}"
    if echo "$CURRENT_DE" | grep -qi "cinnamon"; then
        zenity --warning \
            --title="Scrivenix — Keyboard Warning" \
            --text="You are running Cinnamon under Wayland.\n\nShift, Ctrl, and Alt keys do not work correctly in Wine applications under Cinnamon's Wayland compositor. This means you will not be able to type capital letters or use keyboard shortcuts in Scrivener.\n\nTo fix this:\n  1. Log out\n  2. On the login screen, click the session selector\n  3. Choose \"Cinnamon\" (the X11 version, not Wayland)\n  4. Log back in and relaunch Scrivenix\n\nNote for Cinnamon users: The right-click \"Display &amp; Font Settings\" menu item may not appear in Cinnamon. To adjust display scaling, open a terminal and run:\n  flatpak run --command=scrivenix-wrapper com.local.Scrivenix --winecfg\nThen go to the Graphics tab.\n\nScrivener will still launch, but keyboard input will be limited until you switch to an X11 session." \
            --width=500 \
            2>/dev/null
    fi
fi

# --- WINE PREFIX INITIALIZATION ----------------------------------------------

if [ ! -d "$WINEPREFIX/drive_c" ]; then
    mkdir -p "$WINEPREFIX"
    # Run wineboot silently before showing the welcome dialog.
    # No progress window here — this keeps the single persistent progress
    # window in the main setup block as the ONLY progress window the user
    # ever sees. wineserver -w ensures all Wine processes fully exit before
    # the welcome dialog appears so nothing from wineboot bleeds through.
    wine64 wineboot -i 2>/dev/null
    wineserver -w 2>/dev/null
fi

# --- FIRST-RUN SETUP ---------------------------------------------------------

if [ ! -f "$SETUP_DONE_FLAG" ]; then

    zenity --question \
        --title="Scrivenix — First-Run Setup" \
        --text="Welcome to Scrivenix!\n\nFirst-run setup will:\n\n  1. Install Core Fonts             (~1–2 min)\n  2. Install .NET 4.8               (~5–10 min, two Windows dialogs)\n  3. Configure Windows compatibility (~1 min)\n  4. Download Scrivener              (~3–5 min)\n  5. Install Scrivener               (~2–3 min, Windows dialog)\n  6. Configure font rendering        (~1 min)\n\nTotal estimated time: 15–20 minutes.\nPlease stay nearby — you will need to interact with\nWindows installer dialogs in steps 2 and 5.\n\nNOTE: Step 2 runs two installers back to back (.NET 4\nthen .NET 4.8). A harmless warning will appear before\nthe second installer — click Continue to proceed.\n\nClick Begin Setup when you are ready." \
        --ok-label="Begin Setup" \
        --cancel-label="Cancel" \
        --width=500 \
        2>/dev/null || exit 0

    mkdir -p "$CACHE_DIR"

    # Open ONE persistent progress window that stays open for the entire setup.
    # Interactive installer windows (.NET, Scrivener) appear on top of it —
    # there is no need to close and reopen. Closing and reopening was the cause
    # of multiple orphaned zenity windows being left open with no way to dismiss.
    setup_progress_open

    # Step 1 — Core Fonts
    setup_progress_update 10 "Step 1 of 6: Installing Core Fonts...\n\nDownloading and installing Windows core fonts.\nThis takes 1–2 minutes. Please wait."
    winetricks -q corefonts 2>/dev/null

    # Step 2 — .NET 4.8
    # --force ensures .NET installs fully even if winetricks thinks it is
    # already present. Without this, Paddle.exe (Scrivener's license activation
    # binary) throws "Object reference not set to an instance of an object"
    # and activation fails silently.
    #
    # After installation we verify the registry key was written correctly.
    # If verification fails we attempt one automatic retry before warning
    # the user. This makes the setup self-healing for interrupted installs.
    #
    # mscorsvw.exe (.NET Native Image Generator) is explicitly killed after
    # installation. In Wine it can run indefinitely, blocking wineserver -w.
    # It is safe to terminate — Scrivener does not need pre-compiled images.
    #
    # .NET 4.8 release registry value: 528040 (0x80EA8)
    # Any value >= 528040 confirms a successful dotnet48 installation.
    #
    # WINE 11 / WoW64 NOTE: Wine 11 (shipped with the 24.08 runtime) introduced
    # experimental WoW64 mode. Under WoW64, wine64 reg query reads the 64-bit
    # registry view, which may not reflect the location the .NET installer wrote
    # to. As a result the registry check alone is unreliable on Wine 11+.
    #
    # Primary check: winetricks workaround flag file. winetricks creates this
    # file (dotnet48.installed.workaround) only after a successful dotnet48
    # install. It is the most reliable cross-Wine-version signal available.
    # Registry query is retained as a secondary check for older Wine versions.
    #
    # The progress window stays open — the .NET installer will appear on top.

    install_dotnet() {
        setup_progress_update 15 "Step 2 of 6: Installing .NET 4.8...\n\nThis is the longest step — it typically takes 5–10 minutes.\nPlease be patient and do not close any windows.\n\nTwo Windows installers will run back to back:\n  → First: .NET 4 — click Install, then Finish\n  → Then: a warning will appear:\n     \"Windows Module Installer Service is not available\"\n     This is harmless — click Continue to proceed\n  → Second: .NET 4.8 — click Install, then Finish\n\nThe installer will appear on top of this window\nin 30–60 seconds."
        winetricks --force dotnet48 2>/dev/null

        # Kill mscorsvw.exe (.NET Native Image Generator) if still running.
        # This process compiles .NET assemblies to native code after installation
        # and can run for an extremely long time in Wine — sometimes indefinitely.
        # It is safe to terminate: it is a background optimiser and Scrivener
        # does not require pre-compiled native images to run or activate.
        setup_progress_update 35 "Step 2 of 6: Finalising .NET installation...\n\nTerminating background optimiser (mscorsvw.exe).\nThis is safe and expected. Please wait."
        wine64 taskkill /f /im mscorsvw.exe >/dev/null 2>&1 || true
        wine64 taskkill /f /im mscorsvc.exe >/dev/null 2>&1 || true
        # mscorsvw.exe can be restarted by the .NET service framework immediately
        # after taskkill returns. Force-terminate the entire Wine server so no
        # background .NET process can linger and block the Step 3 wineserver wait.
        wineserver -k 2>/dev/null || true
        sleep 2
    }

    verify_dotnet() {
        # Primary: winetricks workaround flag file — reliable under Wine 11+ WoW64
        if [ -f "$DOTNET_WORKAROUND_FLAG" ]; then
            return 0
        fi
        # Fallback: registry query — reliable on Wine 9/10, may fail on Wine 11+
        # WoW64 mode due to registry view differences between 32-bit and 64-bit.
        local RELEASE
        RELEASE=$(wine64 reg query \
            "HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full" \
            /v Release 2>/dev/null | grep -i "Release" | awk '{print $NF}')
        RELEASE=$(printf "%d" "$RELEASE" 2>/dev/null || echo 0)
        [ "$RELEASE" -ge 528040 ] 2>/dev/null
    }

    # First installation attempt
    install_dotnet

    # Verify — if failed, wait for wineserver to settle and retry once
    if ! verify_dotnet; then
        setup_progress_update 40 "Step 2 of 6: Verifying .NET installation...\n\nFirst attempt did not complete successfully.\nWaiting for Wine to settle before retrying.\nPlease wait — this may take a few minutes."
        wineserver -w 2>/dev/null
        setup_progress_update 45 "Step 2 of 6: Retrying .NET installation...\n\nRunning a second installation attempt.\nPlease follow the Windows installer prompts again if they appear."
        install_dotnet
        if ! verify_dotnet; then
            setup_progress_close
            error_exit ".NET 4.8 installation could not be verified.\n\nPlease wipe and retry using the clean reinstall commands in INSTALL.txt.\n\nIf this error persists, please report it at:\nhttps://github.com/adgalloway/Scrivenix/issues"
        fi
    fi

    # Step 3 — Set Windows 10 compatibility mode.
    # Required for Paddle.exe to communicate with the Scrivener license server.
    # Without this, activation fails even when .NET is correctly installed.
    #
    # install_dotnet already called wineserver -k to force-terminate all Wine
    # processes including any service-restarted mscorsvw.exe siblings. No wait
    # needed here. Direct registry writes used instead of winetricks win10 to
    # avoid winetricks triggering its own redundant wineserver -w.
    setup_progress_update 50 "Step 3 of 6: Configuring Windows compatibility mode...\n\nApplying Windows 10 settings. Please wait."
    "$WINELOADER" reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentVersion /t REG_SZ /d "10.0" /f >/dev/null 2>&1
    "$WINELOADER" reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentBuildNumber /t REG_SZ /d "19041" /f >/dev/null 2>&1
    "$WINELOADER" reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CSDVersion /t REG_SZ /d "" /f >/dev/null 2>&1
    "$WINELOADER" reg add "HKCU\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f >/dev/null 2>&1

    # Step 4 — Acquire Scrivener installer
    # Acquisition order (first match wins):
    #   1. Already cached from a previous run        → use it directly
    #   2. Pre-staged by user in ~/Downloads         → copy to cache
    #   3. Automatic download from Literature & Latte → cache it
    #   4. Download failed → file picker dialog      → copy chosen file to cache
    #
    # A non-empty cached file persists across relaunches, so a failed partial
    # download or an interrupted setup does not require repeating steps 1–3.
    # -s tests for non-empty (-f alone would accept a 0-byte partial download).

    SCRIV_DL_URL="https://scrivener.s3.amazonaws.com/Scrivener-installer.exe"
    SCRIV_PRELOAD="$HOME/Downloads/Scrivener-installer.exe"

    acquire_scrivener_installer() {
        # 1. Valid cached file from a previous run or pre-staged copy
        if [ -s "$CACHE_DIR/scrivener-setup.exe" ]; then
            return 0
        fi

        # 2. User pre-staged the installer in ~/Downloads before running setup
        if [ -s "$SCRIV_PRELOAD" ]; then
            setup_progress_update 62 "Step 4 of 6: Using pre-downloaded installer...\n\nFound Scrivener-installer.exe in ~/Downloads.\nCopying to cache. Please wait."
            cp "$SCRIV_PRELOAD" "$CACHE_DIR/scrivener-setup.exe"
            [ -s "$CACHE_DIR/scrivener-setup.exe" ] && return 0
        fi

        # 3. Automatic download
        setup_progress_update 60 "Step 4 of 6: Downloading Scrivener 3...\n\nDownloading the Scrivener installer (~175 MB).\nThis may take several minutes depending on your connection.\nPlease wait."
        rm -f "$CACHE_DIR/scrivener-setup.exe"
        curl -L --silent \
            "$SCRIV_DL_URL" \
            -o "$CACHE_DIR/scrivener-setup.exe" 2>/dev/null

        # Validate — curl can exit 0 but write an empty file or an HTML error page
        if [ -s "$CACHE_DIR/scrivener-setup.exe" ]; then
            return 0
        fi

        # 4. Download failed — offer a file picker so the user can locate a
        #    manually downloaded copy. The progress window stays open in the
        #    background; the file picker appears alongside it.
        rm -f "$CACHE_DIR/scrivener-setup.exe"
        setup_progress_update 60 "Step 4 of 6: Download failed — waiting for your input...\n\nA dialog has appeared asking you to locate the\nScrivener installer. Please respond to that dialog."

        local MANUAL_PATH
        MANUAL_PATH=$(zenity --file-selection \
            --title="Scrivenix — Locate Scrivener Installer" \
            --filename="$HOME/Downloads/" \
            --file-filter="Windows Installer (*.exe) | *.exe" \
            --file-filter="All files | *" \
            2>/dev/null)

        # User cancelled the file picker
        if [ -z "$MANUAL_PATH" ]; then
            return 1
        fi

        if [ ! -s "$MANUAL_PATH" ]; then
            return 1
        fi

        setup_progress_update 62 "Step 4 of 6: Copying installer to cache...\n\nPlease wait."
        cp "$MANUAL_PATH" "$CACHE_DIR/scrivener-setup.exe"
        [ -s "$CACHE_DIR/scrivener-setup.exe" ] && return 0

        return 1
    }

    if ! acquire_scrivener_installer; then
        setup_progress_close
        error_exit "The Scrivener installer could not be obtained.\n\nTo continue, download the installer manually:\n  https://www.literatureandlatte.com/scrivener/download\n\nThen relaunch Scrivenix — you will be prompted to\nlocate the file. Steps 1–3 will not repeat.\n\nAlternatively, save the downloaded file as:\n  ~/Downloads/Scrivener-installer.exe\nand relaunch — Scrivenix will find it automatically."
    fi

    # Step 5 — Scrivener installer
    # Progress window stays open — installer appears on top of it.
    setup_progress_update 75 "Step 5 of 6: Installing Scrivener 3...\n\nThe Scrivener installer will appear on top of this\nwindow in a moment. Please wait.\n\nWhen the installer appears:\n  → Click Next / Install\n  → Wait for installation to complete\n  → Click Finish"
    wine "$CACHE_DIR/scrivener-setup.exe" 2>/dev/null

    # Verify the install succeeded before continuing
    if [ ! -f "$SCRIV_EXE" ]; then
        setup_progress_close
        warn "Scrivener.exe was not found after setup.\n\nIf you cancelled the installer, launch Scrivenix again to retry."
        exit 1
    fi

    # Step 6 — Compatibility fixes and font smoothing
    setup_progress_update 90 "Step 6 of 6: Applying final configuration...\n\nRemoving texttospeech folder and configuring font\nrendering. Almost done — please wait."
    remove_speech_to_text
    configure_fonts

    # Wait for all Wine processes from configure_fonts (winetricks, reg add) to
    # exit cleanly. Without this, wineserver is still busy when the winecfg
    # prompt fires immediately below, causing winecfg to deadlock on connection.
    setup_progress_update 95 "Step 6 of 6: Finalising configuration...\n\nWaiting for Wine to settle. Almost done — please wait."
    wineserver -w 2>/dev/null

    setup_progress_update 100 "Setup complete! Scrivener 3 is ready."
    setup_progress_close
    info "Setup complete!\n\nScrivener 3 has been installed successfully."

    touch "$SETUP_DONE_FLAG"

    # --- FIRST-RUN WINECFG PROMPT --------------------------------------------
    # Prompt the user to set their preferred display scaling before Scrivener
    # launches for the first time. winecfg's Graphics tab is the reliable
    # cross-distro method for adjusting DPI — registry writes alone are not
    # sufficient on all display backends (X11 vs XWayland vs Wayland).

    zenity --question \
        --title="Scrivenix — Display Scaling" \
        --text="Setup is complete! Before Scrivener launches, you may want to adjust display scaling.\n\nIn the Wine Configuration window that is about to open:\n\nGraphics tab:\n  1. Increase the DPI value if Scrivener's UI looks too small\n     (144 is a good starting point for most screens)\n  2. Click Apply\n\nApplications tab:\n  Windows 10 compatibility mode has been configured\n  automatically. You can verify it is set correctly here.\n\nScrivener will launch immediately after you close\nthe configuration window.\n\nIf everything looks fine at the default size, just click Skip." \
        --ok-label="Open Display Settings" \
        --cancel-label="Skip — Launch Scrivener Now" \
        --width=500 \
        2>/dev/null && {
            # Kill any lingering wineserver before winecfg connects.
            # After the wineserver -w above, the server process can still be in a
            # brief shutdown state on Wine 11 WoW64. If winecfg tries to start
            # while it is in that state it deadlocks, making Scrivenix appear hung.
            # Poll until the process is truly gone rather than using a fixed sleep,
            # which was unreliable across systems in testing.
            wineserver -k 2>/dev/null
            while pgrep -u "$USER" -x wineserver >/dev/null 2>&1; do sleep 0.5; done
            "$WINELOADER" winecfg
            # Wait for winecfg's registry writes (DPI value) to be flushed to
            # disk by wineserver before Scrivener reads the registry on launch.
            # Without this, the DPI change is written in memory but not yet
            # persisted, so Scrivener sees the old value and the change only
            # takes effect on the second launch.
            wineserver -w 2>/dev/null
        }

fi

# --- LAUNCH ------------------------------------------------------------------
# Re-check texttospeech on every launch — self-heals after a Scrivener update.

if [ ! -f "$SCRIV_EXE" ]; then
    error_exit "Scrivener executable not found.\n\nDelete the file:\n  $SETUP_DONE_FLAG\n\nThen relaunch Scrivenix to run setup again."
fi

remove_speech_to_text

# FREETYPE_PROPERTIES: use the older TrueType interpreter (v35) for better
# hinting at small sizes than the newer CFF-focused v40 engine.
exec env FREETYPE_PROPERTIES="truetype:interpreter-version=35" \
    WINEDLLOVERRIDES="cryptbase=b" \
    wine "$SCRIV_EXE" 2>/dev/null
