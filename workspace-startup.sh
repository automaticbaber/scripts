#!/usr/bin/env bash
# workspace-startup.sh — GNOME 46 · Ubuntu 24.04 · Wayland
# Layout: WS1=browser | WS2=terminal | WS3=browser | WS4=browser
#
# Fix for windows all landing on the same workspace:
#   Old approach relied on sleep timing to place windows — unreliable on Wayland
#   because new windows go to whichever workspace is active when they *map*,
#   not when the process was started.
#
#   New approach: snapshot window IDs before each launch, poll until a new
#   window actually appears, then call MetaWindow.change_workspace_by_index()
#   to pin it explicitly. Correctness no longer depends on timing.
#
# Requires: org.gnome.Shell.Eval (available on stock Ubuntu 24.04 GNOME 46).
# If Shell.Eval is ever disabled, switch_ws() can be replaced with:
#   ydotool key super+<N>   (requires ydotoold running + Super+1-4 shortcuts set)

set -euo pipefail

MAX_WAIT=25   # seconds to wait for a new window before giving up

###############################################################################
# GNOME Shell JS bridge via org.gnome.Shell.Eval
###############################################################################

_gdbus() {
    gdbus call --session \
        --dest org.gnome.Shell \
        --object-path /org/gnome/Shell \
        --method org.gnome.Shell.Eval \
        "$1" 2>/dev/null
}

# Evaluate "JSON.stringify(<expr>)" and return the unwrapped value.
_js_json() {
    local raw
    raw=$(_gdbus "JSON.stringify($1)")
    raw="${raw#*\'}"   # strip through the opening single-quote
    raw="${raw%\'*}"   # strip from the closing single-quote onward
    [[ -z "$raw" ]] && echo "[]" || echo "$raw"
}

# Switch active workspace to 0-based index N.
switch_ws() {
    _gdbus "global.workspace_manager.get_workspace_by_index($1).activate(0)" >/dev/null
    sleep 0.5   # let Mutter finish the compositor transition
}

# Return a JSON integer array of window IDs for windows matching JS predicate on `w`.
win_ids() {
    _js_json "global.get_window_actors()
        .map(a=>a.meta_window)
        .filter(w=>$1)
        .map(w=>w.get_id())"
}

# Poll until a window NOT in $2 (JSON int array) appears that satisfies filter $1.
wait_new_win() {
    local filter=$1 before=$2 t=0 result
    while (( t < MAX_WAIT )); do
        result=$(_gdbus "(function(){
            let b = new Set(${before});
            return global.get_window_actors().some(function(a) {
                let w = a.meta_window;
                return ($filter) && !b.has(w.get_id());
            });
        })()")
        [[ "$result" == *"true"* ]] && return 0
        sleep 1; (( t++ ))
    done
    echo "  [warn] no new window after ${MAX_WAIT}s — continuing anyway" >&2
    return 1
}

# Move every window NOT in $2 (JSON int array) that satisfies filter $1 to workspace $3.
move_new_wins() {
    local filter=$1 before=$2 ws=$3
    _gdbus "(function(){
        let b = new Set(${before});
        global.get_window_actors()
            .map(a=>a.meta_window)
            .filter(function(w){ return ($filter) && !b.has(w.get_id()); })
            .forEach(function(w){ w.change_workspace_by_index($ws, false); });
    })()" >/dev/null
}

###############################################################################
# Preflight check
###############################################################################

if ! _gdbus "true" | grep -q 'true'; then
    echo "ERROR: org.gnome.Shell.Eval is not accessible." >&2
    echo "Ensure you are running inside a GNOME Wayland session." >&2
    exit 1
fi

###############################################################################
# JS window-filter constants
###############################################################################

FF="(w.get_wm_class()||'').toLowerCase()==='firefox'"
TERM="(w.get_wm_class()||'').toLowerCase().includes('gnome-terminal')"

###############################################################################
# Helper: switch to workspace, launch a command, wait for its window, pin it.
###############################################################################

launch_and_pin() {
    local label=$1 ws=$2 filter=$3
    shift 3   # "$@" is now the command + args

    echo "→ WS$((ws+1)): $label"
    switch_ws "$ws"

    local ids
    ids=$(win_ids "$filter")   # snapshot existing window IDs of this type

    "$@" &                     # launch in background

    wait_new_win "$filter" "$ids" || true
    move_new_wins "$filter" "$ids" "$ws"
    echo "   pinned to WS$((ws+1)) ✓"
}

###############################################################################
# Configure 4 static workspaces
###############################################################################

echo "Configuring 4 static workspaces..."
gsettings set org.gnome.mutter dynamic-workspaces false
gsettings set org.gnome.desktop.wm.preferences num-workspaces 4
sleep 0.8   # give Mutter time to register the new workspace count

###############################################################################
# Launch and pin each app to its workspace
###############################################################################

launch_and_pin "Firefox"        0 "$FF"   firefox --new-window
launch_and_pin "gnome-terminal" 1 "$TERM" gnome-terminal
launch_and_pin "Firefox"        2 "$FF"   firefox --new-window
launch_and_pin "Firefox"        3 "$FF"   firefox --new-window

# Land back on workspace 1
switch_ws 0
echo "Done — 4 workspaces ready."
