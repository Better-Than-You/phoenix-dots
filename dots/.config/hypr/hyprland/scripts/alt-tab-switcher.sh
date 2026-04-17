#!/usr/bin/env bash

# Alt+Tab window switcher for Hyprland (workspace-grouped sorting)
# Usage: alt-tab-switcher.sh [next|prev]
# Cycles: all windows in workspace 1 -> workspace 2 -> workspace 3 -> ... -> back to workspace 1

direction="${1:-next}"

get_focused() {
    hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty' 2>/dev/null
}

# Get all windows sorted by workspace ID, maintaining order within each workspace
get_all_windows_sorted() {
    hyprctl clients -j 2>/dev/null | jq -r '[.[] | select(.hidden == false and .workspace.id >= 0) | {ws: .workspace.id, addr: .address}] | sort_by(.ws) | .[].addr' 2>/dev/null
}

case "$direction" in
    next)
        mapfile -t windows < <(get_all_windows_sorted)
        focused=$(get_focused)

        if [[ -z "$focused" || ${#windows[@]} -eq 0 ]]; then
            exit 0
        fi

        # Find current index
        current_idx=0
        for i in "${!windows[@]}"; do
            if [[ "${windows[$i]}" == "$focused" ]]; then
                current_idx=$i
                break
            fi
        done

        # Get next index (wrap around)
        next_idx=$(( (current_idx + 1) % ${#windows[@]} ))
        hyprctl dispatch focuswindow "address:${windows[$next_idx]}" 2>/dev/null
        ;;
    prev)
        mapfile -t windows < <(get_all_windows_sorted)
        focused=$(get_focused)

        if [[ -z "$focused" || ${#windows[@]} -eq 0 ]]; then
            exit 0
        fi

        # Find current index
        current_idx=0
        for i in "${!windows[@]}"; do
            if [[ "${windows[$i]}" == "$focused" ]]; then
                current_idx=$i
                break
            fi
        done

        # Get previous index (wrap around)
        next_idx=$(( (current_idx - 1 + ${#windows[@]}) % ${#windows[@]} ))
        hyprctl dispatch focuswindow "address:${windows[$next_idx]}" 2>/dev/null
        ;;
esac
