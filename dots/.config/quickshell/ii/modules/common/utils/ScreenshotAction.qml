pragma ComponentBehavior: Bound
pragma Singleton
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell

Singleton {
    id: root

    enum Action {
        Copy,
        Edit,
        Search,
        CharRecognition,
        Record,
        RecordWithSound
    }

    property string imageSearchEngineBaseUrl: Config.options.search.imageSearch.imageSearchEngineBaseUrl
    property string fileUploadApiEndpoint: "https://uguu.se/upload"

    function getCommand(x, y, width, height, screenshotPath, action, saveDir = "") {
        // Set command for action
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.round(width);
        const rh = Math.round(height);
        const cropBase = `magick ${StringUtils.shellSingleQuoteEscape(screenshotPath)} `
            + `-crop ${rw}x${rh}+${rx}+${ry}`
        const cropToStdout = `${cropBase} -`
        const cropInPlace = `${cropBase} '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`
        const cleanup = `rm '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`
        const slurpRegion = `${rx},${ry} ${rw}x${rh}`
        const uploadAndGetUrl = (filePath) => {
            return `curl -sF files[]=@'${StringUtils.shellSingleQuoteEscape(filePath)}' ${root.fileUploadApiEndpoint} | jq -r '.files[0].url'`
        }
        const useSatty = Config.options.regionSelector.annotation.useSatty;
        switch (action) {
            case ScreenshotAction.Action.Copy:
                if (saveDir === "") {
                    // not saving the screenshot, just copy to clipboard
                    return ["bash", "-c", `${cropToStdout} | wl-copy && ${cleanup}`]
                    break;
                }
                return [
                    "bash", "-c",
                    `mkdir -p '${StringUtils.shellSingleQuoteEscape(saveDir)}' && \
                    saveFileName="screenshot-$(date '+%Y-%m-%d_%H.%M.%S').png" && \
                    savePath="${saveDir}/$saveFileName" && \
                    ${cropToStdout} | tee >(wl-copy) > "$savePath"; \
                    ${cleanup}; \
                    [ -f "$savePath" ] && notify-send "Screenshot saved" "$savePath" -a "Shell" -i "image-x-generic"`
                ]

                break;
            case ScreenshotAction.Action.Edit:
                if (useSatty) {
                    // Satty: we can specify the output file
                    if (saveDir === "") {
                        return ["bash", "-c", `${cropToStdout} | satty -f -; ${cleanup}`]
                    }
                    return [
                        "bash", "-c",
                        `mkdir -p '${StringUtils.shellSingleQuoteEscape(saveDir)}' && \
                        saveFileName="screenshot-$(date '+%Y-%m-%d_%H.%M.%S').png" && \
                        savePath="${saveDir}/$saveFileName" && \
                        ${cropToStdout} | satty -f - --output-filename "$savePath"; \
                        ${cleanup}; \
                        [ -f "$savePath" ] && notify-send "Screenshot saved" "$savePath" -a "Shell" -i "image-x-generic"`
                    ]
                } else {
                    // Swappy: uses its own config save_dir, early_exit=true closes after Ctrl+S
                    // Check for newest file in save_dir to detect if save happened
                    return [
                        "bash", "-c",
                        `swappyDir="$HOME/Pictures/Screenshots"; \
                        mkdir -p "$swappyDir"; \
                        beforeCount=$(ls -1 "$swappyDir" 2>/dev/null | wc -l); \
                        ${cropToStdout} | swappy -f -; \
                        ${cleanup}; \
                        afterCount=$(ls -1 "$swappyDir" 2>/dev/null | wc -l); \
                        if [ "$afterCount" -gt "$beforeCount" ]; then \
                            newest=$(ls -t "$swappyDir" | head -1); \
                            notify-send "Screenshot saved" "$swappyDir/$newest" -a "Shell" -i "image-x-generic"; \
                        fi`
                    ]
                }
                break;
            case ScreenshotAction.Action.Search:
                return ["bash", "-c", `${cropInPlace} && xdg-open "${root.imageSearchEngineBaseUrl}$(${uploadAndGetUrl(screenshotPath)})" && ${cleanup}`]
                break;
            case ScreenshotAction.Action.CharRecognition:
                return ["bash", "-c", `${cropInPlace} && tesseract '${StringUtils.shellSingleQuoteEscape(screenshotPath)}' stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\\n' '+' | sed 's/\\+$/\\n/') | wl-copy && ${cleanup}`]
                break;
            case ScreenshotAction.Action.Record:
                return ["bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}'`]
                break;
            case ScreenshotAction.Action.RecordWithSound:
                return ["bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}' --sound`]
                break;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                return;
        }
    }
}
