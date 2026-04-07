#!/usr/bin/env bash

STATE_FILE="$HOME/.local/state/quickshell/states.json"
STATE_JSON_PATH=".screenRecord.active"

VAAPI_DEVICE="/dev/dri/renderD128"
RECORDING_DIR="$HOME/Videos/Recordings"

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}

getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}

start_timer() {
    (
        while true; do
            sleep 1
            local seconds=$(($(date +%s) - START_TIME))
            jq ".screenRecord.seconds = $seconds" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        done
    ) &
    TIMER_PID=$!
}

stop_timer() {
    if [[ -n "$TIMER_PID" ]]; then
        kill "$TIMER_PID" 2>/dev/null
        wait "$TIMER_PID" 2>/dev/null
        jq ".screenRecord.seconds = 0" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
}

trap stop_timer EXIT

ARGS=("$@")
MANUAL_REGION=""
FULLSCREEN_FLAG=0

for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
        else
            notify-send "Recording cancelled" "No region specified" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    fi
done

if pgrep wf-recorder > /dev/null; then
    notify-send "Recording stopped" "$(date '+%H:%M:%S')" -a 'Recorder' & disown
    jq "$STATE_JSON_PATH = false" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    pkill wf-recorder
else
    START_TIME=$(date +%s)

    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        notify-send "Recording" "$(date '+%H:%M:%S')" -a 'Recorder' & disown
        jq "$STATE_JSON_PATH = true" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        start_timer
        wf-recorder --codec h264_vaapi --device "$VAAPI_DEVICE" -o "$(getactivemonitor)" -f "./recording_$(getdate).mp4"
    else
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection cancelled" -a 'Recorder' & disown
                exit 1
            fi
        fi

        pos="${region%% *}"
        size="${region##* }"
        x="${pos%,*}"
        y="${pos#*,}"
        geometry="${x},${y} ${size}"

        notify-send "Recording" "$(date '+%H:%M:%S')" -a 'Recorder' & disown
        jq "$STATE_JSON_PATH = true" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        start_timer
        wf-recorder --codec h264_vaapi --device "$VAAPI_DEVICE" -o "$(getactivemonitor)" -f "./recording_$(getdate).mp4" --geometry "$geometry"
    fi
fi
