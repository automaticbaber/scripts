#!/usr/bin/env bash
# workspace-startup.sh
# Sets up 4 GNOME workspaces: browser | terminal | browser | browser
# Ubuntu 24.04 · GNOME 46 · Wayland
#
# Tune these if windows land on the wrong workspace (slower machines
# need higher values — Firefox cold-start can take 10+ seconds).
FIREFOX_FIRST_WAIT=8   # workspace 1: Firefox launching from scratch
FIREFOX_NEXT_WAIT=3    # workspaces 3 & 4: sending --new-window to running instance
TERM_WAIT=2

set -euo pipefail

# Switch to workspace N (0-indexed) via GNOME Shell DBus.
# org.gnome.Shell.Eval is available on stock Ubuntu 24.04 GNOME 46;
# if it ever gets restricted, replace the body with:
#   ydotool key super+<N+1>   (requires ydotool installed & running)
switch_ws() {
    gdbus call --session \
        --dest org.gnome.Shell \
        --object-path /org/gnome/Shell \
        --method org.gnome.Shell.Eval \
        "global.workspace_manager.get_workspace_by_index($1).activate(0)" \
        >/dev/null
}

# ── 1. Ensure 4 static workspaces exist ──────────────────────────
gsettings set org.gnome.mutter dynamic-workspaces false
gsettings set org.gnome.desktop.wm.preferences num-workspaces 4
sleep 0.5   # let Mutter register the workspace count before switching

# ── 2. Workspace 1 — browser ─────────────────────────────────────
switch_ws 0
firefox --new-window &
sleep "$FIREFOX_FIRST_WAIT"

# ── 3. Workspace 2 — terminal ────────────────────────────────────
switch_ws 1
gnome-terminal &
sleep "$TERM_WAIT"

# ── 4. Workspace 3 — browser ─────────────────────────────────────
switch_ws 2
firefox --new-window &
sleep "$FIREFOX_NEXT_WAIT"

# ── 5. Workspace 4 — browser ─────────────────────────────────────
switch_ws 3
firefox --new-window &
sleep "$FIREFOX_NEXT_WAIT"

# ── 6. Land back on workspace 1 ──────────────────────────────────
switch_ws 0
echo "Done — 4 workspaces ready."
