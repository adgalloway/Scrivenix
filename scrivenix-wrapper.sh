#!/bin/bash
# =============================================================================
# Scrivenix — Scrivener 3 for Linux via Wine/Flatpak
# =============================================================================

# --- PATHS & ENVIRONMENT -----------------------------------------------------
export WINEPREFIX="$HOME/.var/app/com.local.Scrivenix/wine"
export WINEARCH=win64
export WINEDEBUG=-all

# The Flatpak Wine base only ships 64-bit libraries (x86_64-unix/windows).
# /app/bin/wine is the 32-bit loader and will crash immediately because
# i386-unix/ntdll.so is absent. Force all Wine tools — including winetricks
# and the wineboot wrapper — to use wine64 by setting these three variables.
# The Compat.i386 extension declared in the manifest provides 32-bit libraries
# for child processes like Paddle.exe (Scrivener's license activation binary).
export WINE=/app/bin/wine
export WINELOADER=/app/bin/wine64
export WINESERVER=/app/bin/wineserver

CACHE_DIR="$HOME/.var/app/com.local.Scrivenix/cache"
SCRIV_EXE="$WINEPREFIX/drive_c/Program Files/Scrivener3/Scrivener.exe"
SETUP_DONE_FLAG="$WINEPREFIX/.setup_done"
SPEECH_DIR="$WINEPREFIX/drive_c/Program Files/Scrivener3/texttospeech"

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
#   3%  — Wine prefix init        (~1 min)
#   8%  — Core Fonts              (~1-2 min)
#  13%  — SAPI                    (~1-2 min)
#  18%  — GDI+                    (~1-2 min)
#  23%  — .NET 4.8 starting       (~5-10 min — dominates total time)
#  55%  — .NET 4.8 complete
#  58%  — Windows 10 mode         (~30 sec)
#  75%  — Scrivener download      (~3-5 min)
#  88%  — Scrivener installer     (~2-3 min)
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
# if the texttospeech folder is present and no SAPI stub is available.
#
# Two-layer fix (belt and suspenders):
#   1. winetricks sapi  — installs a COM stub so the enumeration call returns
#   2. Remove the folder — eliminates the code path entirely so a broken or
#      missing SAPI stub can never re-trigger the hang after a Scrivener update

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

configure_fonts() {
    winetricks fontsmooth=rgb >/dev/null 2>&1
    wine64 reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothing            /t REG_SZ    /d 2    /f >/dev/null 2>&1
    wine64 reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingType        /t REG_DWORD /d 2    /f >/dev/null 2>&1
    wine64 reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingGamma       /t REG_DWORD /d 1000 /f >/dev/null 2>&1
    wine64 reg add "HKCU\\Control Panel\\Desktop" /v FontSmoothingOrientation /t REG_DWORD /d 1    /f >/dev/null 2>&1
}

# --- WINECFG LAUNCHER --------------------------------------------------------
# Launched via the right-click "Display & Font Settings" desktop action.
# Opens Wine's built-in configuration tool directly against the Scrivenix
# prefix. The Graphics tab allows the user to set DPI/scaling, which is
# the reliable cross-distro method for adjusting Scrivener's UI size.

launch_winecfg() {
    wine64 winecfg
}

# --- ARGUMENT HANDLING -------------------------------------------------------

case "$1" in
    --winecfg)
        launch_winecfg
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
            --text="You are running Cinnamon under Wayland.\n\nShift, Ctrl, and Alt keys do not work correctly in Wine applications under Cinnamon's Wayland compositor. This means you will not be able to type capital letters or use keyboard shortcuts in Scrivener.\n\nTo fix this:\n  1. Log out\n  2. On the login screen, click the session selector\n  3. Choose \"Cinnamon\" (the X11 version, not Wayland)\n  4. Log back in and relaunch Scrivenix\n\nNote for Cinnamon users: The right-click \"Display &amp; Font Settings\" menu item may not appear in Cinnamon. To adjust display scaling, open a terminal and run:\n  flatpak run --command=wine64 com.local.Scrivenix winecfg\nThen go to the Graphics tab.\n\nScrivener will still launch, but keyboard input will be limited until you switch to an X11 session." \
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
        --text="Welcome to Scrivenix!\n\nFirst-run setup will:\n\n  1. Install Core Fonts             (~1–2 min)\n  2. Install SAPI                    (~1–2 min)\n  3. Install GDI+                    (~1–2 min)\n  4. Install .NET 4.8               (~5–10 min, Windows dialogs)\n  5. Download &amp; Install Scrivener  (~5–10 min, Windows dialog)\n  6. Configure font rendering        (~1 min)\n\nTotal estimated time: 15–25 minutes.\nPlease stay nearby — you will need to interact with\nthe Windows installer dialogs in steps 4 and 5.\n\nClick Begin Setup when you are ready." \
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
    setup_progress_update 8 "Step 1 of 8: Installing Core Fonts...\n\nDownloading and installing Windows core fonts.\nThis takes 1–2 minutes. Please wait."
    winetricks -q corefonts 2>/dev/null

    # Step 2 — SAPI stub
    # Provides a COM implementation for Windows Speech API so Scrivener's
    # font-loading phase does not block on TTS voice enumeration.
    setup_progress_update 13 "Step 2 of 8: Installing SAPI...\n\nInstalling the Speech API component.\nThis prevents a hang on the Scrivener loading screen.\nThis takes 1–2 minutes. Please wait."
    winetricks -q sapi 2>/dev/null

    # Step 3 — GDI+
    # Improves Wine's GDI font rendering pipeline for sharper text in Scrivener.
    setup_progress_update 18 "Step 3 of 8: Installing GDI+...\n\nInstalling graphics components for improved font rendering.\nThis takes 1–2 minutes. Please wait."
    winetricks -q gdiplus 2>/dev/null

    # Step 4 — .NET 4.8
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
    # The progress window stays open — the .NET installer will appear on top.

    install_dotnet() {
        setup_progress_update 23 "Step 4 of 8: Installing .NET 4.8...\n\nThis is the longest step — it typically takes 5–10 minutes.\nPlease be patient and do not close any windows.\n\nThe Windows installer is loading and will appear on top\nof this window in 30–60 seconds.\n\nIMPORTANT: You may see a warning that says:\n\"Windows Module Installer Service is not available\"\nThis is harmless — click Continue to proceed normally.\n\nWhen the installer appears:\n  → Click Install (or Continue past the warning first)\n  → Wait for installation to complete\n  → Click Finish"
        winetricks --force dotnet48 2>/dev/null

        # Kill mscorsvw.exe (.NET Native Image Generator) if still running.
        # This process compiles .NET assemblies to native code after installation
        # and can run for an extremely long time in Wine — sometimes indefinitely.
        # It is safe to terminate: it is a background optimiser and Scrivener
        # does not require pre-compiled native images to run or activate.
        setup_progress_update 38 "Step 4 of 8: Finalising .NET installation...\n\nTerminating background optimiser (mscorsvw.exe).\nThis is safe and expected. Please wait."
        wine64 taskkill /f /im mscorsvw.exe >/dev/null 2>&1 || true
        wine64 taskkill /f /im mscorsvc.exe >/dev/null 2>&1 || true
    }

    verify_dotnet() {
        local RELEASE
        RELEASE=$(wine64 reg query             "HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full"             /v Release 2>/dev/null | grep -i "Release" | awk '{print $NF}')
        # Convert hex (0x80EA8) to decimal
        RELEASE=$(printf "%d" "$RELEASE" 2>/dev/null || echo 0)
        [ "$RELEASE" -ge 528040 ] 2>/dev/null
    }

    # First installation attempt
    install_dotnet

    # Verify — if failed, wait for wineserver to settle and retry once
    if ! verify_dotnet; then
        setup_progress_update 40 "Step 4 of 8: Verifying .NET installation...\n\nFirst attempt did not complete successfully.\nWaiting for Wine to settle before retrying.\nPlease wait — this may take a few minutes."
        wineserver -w 2>/dev/null
        setup_progress_update 42 "Step 4 of 8: Retrying .NET installation...\n\nRunning a second installation attempt.\nPlease follow the Windows installer prompts again if they appear."
        install_dotnet
        if ! verify_dotnet; then
            setup_progress_close
            error_exit ".NET 4.8 installation could not be verified.\n\nPlease wipe and retry using the clean reinstall commands in INSTALL.txt.\n\nIf this error persists, please report it at:\nhttps://github.com/adgalloway/Scrivenix/issues"
        fi
    fi

    # Step 5 — Wait for .NET background work to finish, then set Windows 10 mode
    # Required for Paddle.exe to communicate with the Scrivener license server.
    # Without this, activation fails even when .NET is correctly installed.
    #
    # When the .NET installer UI closes, .NET continues running background tasks
    # inside Wine (registering COM components, writing assembly caches, running
    # post-install scripts) for several minutes with no visible UI. We wait
    # explicitly for all Wine processes to finish before applying the Windows
    # version change, ensuring nothing is written to a partially-configured
    # prefix. Direct registry writes are used instead of winetricks win10 to
    # avoid winetricks triggering its own redundant wineserver -w call on top.
    setup_progress_update 50 "Step 5 of 8: Waiting for .NET to finish...\n\nThe .NET installer is completing background tasks.\nThis is normal and may take several minutes.\n\nPlease do not close any windows or restart your computer.\nScrivenix will continue automatically when finished."
    wineserver -w 2>/dev/null
    setup_progress_update 58 "Step 5 of 8: Configuring Windows compatibility mode...\n\nSetting Windows version to 10. Please wait."
    wine64 reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentVersion /t REG_SZ /d "10.0" /f >/dev/null 2>&1
    wine64 reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentBuildNumber /t REG_SZ /d "19041" /f >/dev/null 2>&1
    wine64 reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CSDVersion /t REG_SZ /d "" /f >/dev/null 2>&1
    wine64 reg add "HKCU\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f >/dev/null 2>&1

    # Step 6 — Download Scrivener (skip if already cached from a previous run)
    if [ ! -f "$CACHE_DIR/scrivener-setup.exe" ]; then
        setup_progress_update 60 "Step 6 of 8: Downloading Scrivener 3...\n\nDownloading the Scrivener installer (~175 MB).\nThis may take several minutes depending on your connection.\nPlease wait."
        curl -L --silent \
            "https://scrivener.s3.amazonaws.com/Scrivener-installer.exe" \
            -o "$CACHE_DIR/scrivener-setup.exe" 2>/dev/null
        if [ ! -f "$CACHE_DIR/scrivener-setup.exe" ]; then
            setup_progress_close
            error_exit "Scrivener download failed.\n\nCheck your internet connection and try again."
        fi
    fi

    # Step 7 — Scrivener installer
    # Progress window stays open — installer appears on top of it.
    setup_progress_update 75 "Step 7 of 8: Installing Scrivener 3...\n\nThe Scrivener installer will appear on top of this\nwindow in a moment. Please wait.\n\nWhen the installer appears:\n  → Click Next / Install\n  → Wait for installation to complete\n  → Click Finish"
    wine "$CACHE_DIR/scrivener-setup.exe" 2>/dev/null

    # Verify the install succeeded before continuing
    if [ ! -f "$SCRIV_EXE" ]; then
        setup_progress_close
        warn "Scrivener.exe was not found after setup.\n\nIf you cancelled the installer, launch Scrivenix again to retry."
        exit 1
    fi

    # Step 8 — Compatibility fixes and font smoothing
    setup_progress_update 88 "Step 8 of 8: Applying final configuration...\n\nRemoving texttospeech folder and configuring font\nrendering. Almost done — please wait."
    remove_speech_to_text
    configure_fonts

    setup_progress_update 100 "Setup complete! Scrivener 3 is ready."
    sleep 2
    setup_progress_close

    touch "$SETUP_DONE_FLAG"

    # --- FIRST-RUN WINECFG PROMPT --------------------------------------------
    # Prompt the user to set their preferred display scaling before Scrivener
    # launches for the first time. winecfg's Graphics tab is the reliable
    # cross-distro method for adjusting DPI — registry writes alone are not
    # sufficient on all display backends (X11 vs XWayland vs Wayland).

    zenity --question \
        --title="Scrivenix — Display Scaling" \
        --text="Setup is complete! Before Scrivener launches, you may want to adjust display scaling.\n\nScrivener's UI elements (menus, toolbar, sidebar) may appear small on some screens. The Wine Configuration window that is about to open lets you fix this.\n\n  1. Click the Graphics tab\n  2. Increase the DPI value (144 is a good starting point for most screens)\n  3. Click Apply, then OK\n\nScrivener will launch immediately after you close the configuration window.\n\nIf everything looks fine at the default size, just click Skip." \
        --ok-label="Open Display Settings" \
        --cancel-label="Skip — Launch Scrivener Now" \
        --width=500 \
        2>/dev/null && wine64 winecfg

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
    wine "$SCRIV_EXE" 2>/dev/null
