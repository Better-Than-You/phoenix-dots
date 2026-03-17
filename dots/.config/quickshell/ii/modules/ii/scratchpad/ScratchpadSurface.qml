pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root
    visible: true
    color: "transparent"
    WlrLayershell.namespace: "quickshell:scratchpad"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    required property ShellScreen screen
    signal dismiss()

    property var strokes: []
    property var currentStroke: null
    property color penColor: "#ff4444"
    property int penWidth: 4
    property bool eraserMode: false
    property string saveDir: `${Directories.pictures}/Screenshots`

    function undo() {
        if (root.strokes.length === 0) return;
        let s = root.strokes.slice();
        s.pop();
        root.strokes = s;
        drawCanvas.requestPaint();
    }

    function clearAll() {
        root.strokes = [];
        drawCanvas.requestPaint();
    }

    function copyToClipboard() {
        // Render final image: grab the screencopy + canvas overlay
        screenshotArea.grabToImage(function(result) {
            let tmpPath = `/tmp/quickshell/media/scratchpad-${Date.now()}.png`;
            result.saveToFile(tmpPath);
            copyProc.command = ["bash", "-c", `wl-copy < '${tmpPath}' && rm '${tmpPath}'`];
            copyProc.running = true;
            root.dismiss();
        });
    }

    function saveToFile() {
        screenshotArea.grabToImage(function(result) {
            let timestamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH.mm.ss");
            let savePath = `${root.saveDir}/Annotation_${timestamp}.png`;
            result.saveToFile(savePath);
            saveNotifyProc.command = ["notify-send", "Annotation saved", savePath, "-a", "Scratchpad", "-i", "document-save"];
            saveNotifyProc.running = true;
            // Also copy to clipboard
            copyProc.command = ["bash", "-c", `wl-copy < '${savePath}'`];
            copyProc.running = true;
            root.dismiss();
        });
    }

    Process {
        id: copyProc
    }

    Process {
        id: saveNotifyProc
    }

    Process {
        id: mkdirProc
        running: true
        command: ["mkdir", "-p", root.saveDir]
    }

    // Frozen screenshot background + drawing canvas (this gets captured for export)
    Item {
        id: screenshotArea
        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                root.dismiss();
            } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
                root.undo();
            } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                root.copyToClipboard();
            } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                root.saveToFile();
            }
        }

        ScreencopyView {
            id: screenCapture
            anchors.fill: parent
            live: false
            captureSource: root.screen
        }

        // Dim overlay on top of screenshot
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.15
        }

        Canvas {
            id: drawCanvas
            anchors.fill: parent
            renderStrategy: Canvas.Threaded

            onPaint: {
                let ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.lineCap = "round";
                ctx.lineJoin = "round";

                // Draw completed strokes
                for (let i = 0; i < root.strokes.length; i++) {
                    let stroke = root.strokes[i];
                    if (!stroke || stroke.points.length < 2) continue;
                    drawStroke(ctx, stroke);
                }

                // Draw in-progress stroke
                if (root.currentStroke && root.currentStroke.points.length >= 2) {
                    drawStroke(ctx, root.currentStroke);
                }

                ctx.globalCompositeOperation = "source-over";
            }

            function drawStroke(ctx, stroke) {
                if (stroke.eraser) {
                    ctx.globalCompositeOperation = "destination-out";
                    ctx.strokeStyle = "rgba(0,0,0,1)";
                } else {
                    ctx.globalCompositeOperation = "source-over";
                    ctx.strokeStyle = stroke.color;
                }
                ctx.lineWidth = stroke.width;

                ctx.beginPath();
                ctx.moveTo(stroke.points[0].x, stroke.points[0].y);
                for (let j = 1; j < stroke.points.length; j++) {
                    ctx.lineTo(stroke.points[j].x, stroke.points[j].y);
                }
                ctx.stroke();
            }
        }
    }

    // Drawing input area (covers everything except the toolbar)
    MouseArea {
        id: drawArea
        anchors.fill: parent
        anchors.bottomMargin: toolbar.height + toolbar.anchors.bottomMargin
        cursorShape: Qt.CrossCursor
        acceptedButtons: Qt.LeftButton

        onPressed: (mouse) => {
            root.currentStroke = {
                points: [{ x: mouse.x, y: mouse.y }],
                color: root.penColor.toString(),
                width: root.eraserMode ? root.penWidth * 4 : root.penWidth,
                eraser: root.eraserMode
            };
        }

        onPositionChanged: (mouse) => {
            if (!root.currentStroke) return;
            root.currentStroke.points.push({ x: mouse.x, y: mouse.y });
            drawCanvas.requestPaint();
        }

        onReleased: {
            if (!root.currentStroke) return;
            if (root.currentStroke.points.length >= 2) {
                let s = root.strokes.slice();
                s.push(root.currentStroke);
                root.strokes = s;
            }
            root.currentStroke = null;
            drawCanvas.requestPaint();
        }
    }

    // Toolbar
    Rectangle {
        id: toolbar
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 32
        }
        width: toolbarRow.implicitWidth + 24
        height: toolbarRow.implicitHeight + 16
        color: Appearance.m3colors.m3surfaceContainer
        radius: Appearance.rounding.large
        border.color: Appearance.colors.colOutlineVariant
        border.width: 1

        // Prevent draw input from going through the toolbar
        MouseArea {
            anchors.fill: parent
            onPressed: (mouse) => mouse.accepted = true
        }

        RowLayout {
            id: toolbarRow
            anchors.centerIn: parent
            spacing: 6

            // Color presets
            Repeater {
                model: [
                    { col: "#ff4444", name: "Red" },
                    { col: "#44ff44", name: "Green" },
                    { col: "#4488ff", name: "Blue" },
                    { col: "#ffffff", name: "White" },
                    { col: "#ffff44", name: "Yellow" },
                    { col: "#ff44ff", name: "Pink" },
                    { col: "#000000", name: "Black" }
                ]
                delegate: RippleButton {
                    id: colorBtn
                    required property var modelData
                    required property int index
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    toggled: !root.eraserMode && root.penColor.toString() === modelData.col

                    onClicked: {
                        root.eraserMode = false;
                        root.penColor = modelData.col;
                    }

                    contentItem: Rectangle {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        radius: 9
                        color: colorBtn.modelData.col
                        border.width: 2
                        border.color: colorBtn.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    }
                }
            }

            ToolbarSeparator {}

            // Stroke width buttons
            Repeater {
                model: [
                    { w: 2, label: "Thin" },
                    { w: 4, label: "Medium" },
                    { w: 8, label: "Thick" }
                ]
                delegate: RippleButton {
                    id: widthBtn
                    required property var modelData
                    required property int index
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    toggled: root.penWidth === modelData.w

                    onClicked: root.penWidth = modelData.w

                    contentItem: Item {
                        anchors.centerIn: parent
                        Rectangle {
                            anchors.centerIn: parent
                            width: 18
                            height: widthBtn.modelData.w
                            radius: widthBtn.modelData.w / 2
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    StyledToolTip {
                        text: widthBtn.modelData.label
                    }
                }
            }

            ToolbarSeparator {}

            // Eraser
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                toggled: root.eraserMode

                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                colRippleToggled: Appearance.colors.colSecondaryContainerActive

                onClicked: root.eraserMode = !root.eraserMode

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "ink_eraser"
                    iconSize: 20
                    color: Appearance.colors.colOnSurface
                }

                StyledToolTip {
                    text: Translation.tr("Eraser")
                }
            }

            // Undo
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                enabled: root.strokes.length > 0

                onClicked: root.undo()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "undo"
                    iconSize: 20
                    color: parent.enabled ? Appearance.colors.colOnSurface : Appearance.colors.colOutlineVariant
                }

                StyledToolTip {
                    text: Translation.tr("Undo (Ctrl+Z)")
                }
            }

            // Clear all
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                enabled: root.strokes.length > 0

                onClicked: root.clearAll()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "delete"
                    iconSize: 20
                    color: parent.enabled ? Appearance.colors.colOnSurface : Appearance.colors.colOutlineVariant
                }

                StyledToolTip {
                    text: Translation.tr("Clear all")
                }
            }

            ToolbarSeparator {}

            // Copy to clipboard
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16

                onClicked: root.copyToClipboard()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "content_copy"
                    iconSize: 20
                    color: Appearance.colors.colOnSurface
                }

                StyledToolTip {
                    text: Translation.tr("Copy to clipboard (Ctrl+C)")
                }
            }

            // Save to file
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16

                onClicked: root.saveToFile()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "save"
                    iconSize: 20
                    color: Appearance.colors.colOnSurface
                }

                StyledToolTip {
                    text: Translation.tr("Save to file (Ctrl+S)")
                }
            }

            // Close / discard
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16

                onClicked: root.dismiss()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 20
                    color: Appearance.colors.colOnSurface
                }

                StyledToolTip {
                    text: Translation.tr("Discard (Escape)")
                }
            }
        }
    }

    component ToolbarSeparator: Rectangle {
        implicitWidth: 1
        Layout.fillHeight: true
        Layout.topMargin: 6
        Layout.bottomMargin: 6
        color: Appearance.colors.colOutlineVariant
    }
}
