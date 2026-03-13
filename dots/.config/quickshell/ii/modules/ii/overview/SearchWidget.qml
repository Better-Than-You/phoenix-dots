pragma ComponentBehavior: Bound

import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item { // Wrapper
    id: root

    readonly property string xdgConfigHome: Directories.config
    readonly property int typingDebounceInterval: 200
    readonly property int typingResultLimit: 15 // Should be enough to cover the whole view

    property string searchingText: LauncherSearch.query
    property bool showResults: searchingText != ""
    property string overviewPosition: "top" // REALLYFIXME: a fallback value for now, its not used anymore
    property bool isFileSearchMode: searchingText.startsWith(Config.options.search.prefix.fileSearch) 
    property bool isClipboardMode: searchingText.startsWith(Config.options.search.prefix.clipboard)
    readonly property string selectedClipboardRawEntry: {
        const selectedEntry = appResults.currentItem?.entry;
        const raw = selectedEntry?.rawValue ?? "";
        const type = selectedEntry?.type ?? "";
        return raw && /^#\d+/.test(type) ? raw : "";
    }
    readonly property int clipboardPinnedCount: Cliphist.entries.filter(entry => Cliphist.isPinned(entry)).length
    readonly property int clipboardUnpinnedCount: Cliphist.entries.length - clipboardPinnedCount
    implicitWidth: searchWidgetContent.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: searchWidgetContent.implicitHeight + searchBar.verticalPadding * 2 + Appearance.sizes.elevationMargin * 2

    function focusFirstItem() {
        appResults.currentIndex = 0;
    }

    function focusSearchInput() {
        searchBar.forceFocus();
    }

    function disableExpandAnimation() {
        searchBar.animateWidth = false;
    }

    function cancelSearch() {
        searchBar.searchInput.selectAll();
        LauncherSearch.query = "";
        searchBar.animateWidth = true;
    }

    function setSearchingText(text) {
        searchBar.searchInput.text = text;
        LauncherSearch.query = text;
    }

    Keys.onPressed: event => {
        // Prevent Esc and Backspace from registering
        if (event.key === Qt.Key_Escape)
            return;

        // Handle Backspace: focus and delete character if not focused
        if (event.key === Qt.Key_Backspace) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                if (event.modifiers & Qt.ControlModifier) {
                    // Delete word before cursor
                    let text = searchBar.searchInput.text;
                    let pos = searchBar.searchInput.cursorPosition;
                    if (pos > 0) {
                        // Find the start of the previous word
                        let left = text.slice(0, pos);
                        let match = left.match(/(\s*\S+)\s*$/);
                        let deleteLen = match ? match[0].length : 1;
                        searchBar.searchInput.text = text.slice(0, pos - deleteLen) + text.slice(pos);
                        searchBar.searchInput.cursorPosition = pos - deleteLen;
                    }
                } else {
                    // Delete character before cursor if any
                    if (searchBar.searchInput.cursorPosition > 0) {
                        searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition - 1) + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                        searchBar.searchInput.cursorPosition -= 1;
                    }
                }
                // Always move cursor to end after programmatic edit
                searchBar.searchInput.cursorPosition = searchBar.searchInput.text.length;
                event.accepted = true;
            }
            // If already focused, let TextField handle it
            return;
        }

        // Only handle visible printable characters (ignore control chars, arrows, etc.)
        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20) // ignore control chars like Backspace, Tab, etc.
        {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                // Insert the character at the cursor position
                searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition) + event.text + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                searchBar.searchInput.cursorPosition += 1;
                event.accepted = true;
                root.focusFirstItem();
            }
        }
    }

    StyledRectangularShadow {
        target: searchWidgetContent
    }
    Rectangle { // Background
        id: searchWidgetContent
        clip: true
        implicitWidth: gridLayout.implicitWidth
        implicitHeight: gridLayout.implicitHeight
        radius: searchBar.height / 2 + searchBar.verticalPadding
        color: Appearance.colors.colBackgroundSurfaceContainer

        Behavior on implicitHeight {
            id: searchHeightBehavior
            enabled: GlobalStates.overviewOpen && root.showResults
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        GridLayout {
            id: gridLayout
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 1

            // clip: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: searchWidgetContent.width
                    height: searchWidgetContent.width
                    radius: searchWidgetContent.radius
                }
            }

            SearchBar {
                id: searchBar
                property real verticalPadding: 4
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 4
                Layout.topMargin: verticalPadding
                Layout.bottomMargin: verticalPadding
                Layout.row: root.overviewPosition == "bottom" ? 2 : 0
                Synchronizer on searchingText {
                    property alias source: root.searchingText
                }
            }

            Rectangle {
                // Separator
                visible: root.showResults
                Layout.fillWidth: true
                height: 1
                color: Appearance.colors.colOutlineVariant
                Layout.row: 1
            }

            ListView { // App results - single column (non-file search)
                id: appResults
                visible: root.showResults && !root.isFileSearchMode
                Layout.fillWidth: true
                implicitHeight: Math.min(600, appResults.contentHeight + topMargin + bottomMargin)
                clip: true
                topMargin: 10
                bottomMargin: 10
                spacing: 2
                KeyNavigation.up: searchBar
                highlightMoveDuration: 100
                Layout.row: root.overviewPosition == "bottom" ? 0 : 2

                onFocusChanged: {
                    if (focus)
                        appResults.currentIndex = 1;
                }

                Connections {
                    target: root
                    function onSearchingTextChanged() {
                        if (appResults.count > 0)
                            appResults.currentIndex = 0;
                    }
                }

                Timer {
                    id: debounceTimer
                    interval: root.typingDebounceInterval
                    onTriggered: {
                        resultModel.values = LauncherSearch.results ?? [];
                    }
                }

                Connections {
                    target: LauncherSearch
                    function onResultsChanged() {
                        resultModel.values = LauncherSearch.results.slice(0, root.typingResultLimit);
                        root.focusFirstItem();
                        debounceTimer.restart();
                    }
                }

                model: ScriptModel {
                    id: resultModel
                    objectProp: "key"
                }

                delegate: SearchItem {
                    id: searchItem
                    // The selectable item for each search result
                    required property var modelData
                    anchors.left: parent?.left
                    anchors.right: parent?.right
                    entry: modelData
                    query: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch, Config.options.search.prefix.fileSearch])

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            if (LauncherSearch.results.length === 0)
                                return;
                            const tabbedText = searchItem.modelData.name;
                            LauncherSearch.query = tabbedText;
                            searchBar.searchInput.text = tabbedText;
                            event.accepted = true;
                            root.focusSearchInput();
                        }
                    }
                }
            }

            Rectangle {
                visible: root.showResults && root.isClipboardMode && !root.isFileSearchMode
                Layout.fillWidth: true
                height: 1
                color: Appearance.colors.colOutlineVariant
                Layout.row: 3
            }

            RowLayout {
                visible: root.showResults && root.isClipboardMode && !root.isFileSearchMode
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.bottomMargin: 10
                Layout.row: 4
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: Translation.tr("Pinned: %1").arg(root.clipboardPinnedCount)
                }

                RippleButton {
                    enabled: root.selectedClipboardRawEntry !== ""
                    implicitHeight: 34
                    implicitWidth: 34
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: {
                        if (root.selectedClipboardRawEntry !== "")
                            Cliphist.togglePinned(root.selectedClipboardRawEntry);
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.selectedClipboardRawEntry !== "" && Cliphist.isPinned(root.selectedClipboardRawEntry) ? "keep_off" : "keep"
                        font.pixelSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledToolTip {
                        text: root.selectedClipboardRawEntry !== "" && Cliphist.isPinned(root.selectedClipboardRawEntry) ? Translation.tr("Unpin selected") : Translation.tr("Pin selected")
                    }
                }

                RippleButton {
                    enabled: root.clipboardUnpinnedCount > 0
                    implicitHeight: 34
                    implicitWidth: 34
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: Cliphist.clearUnpinned()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "delete_sweep"
                        font.pixelSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledToolTip {
                        text: Translation.tr("Delete all")
                    }
                }
            }

            // Two-column layout for file search
            RowLayout {
                id: fileSearchColumns
                visible: root.showResults && root.isFileSearchMode
                Layout.fillWidth: true
                Layout.row: root.overviewPosition == "bottom" ? 0 : 2
                spacing: 1

                // Folders column
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        height: 28
                        color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: Translation.tr("Folders")
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                        }
                    }

                    ListView {
                        id: folderResults
                        Layout.fillWidth: true
                        Layout.preferredWidth: 400
                        implicitHeight: Math.min(400, folderResults.contentHeight + topMargin + bottomMargin)
                        clip: true
                        topMargin: 4
                        bottomMargin: 10
                        spacing: 2
                        interactive: true
                        currentIndex: -1
                        highlightFollowsCurrentItem: true
                        highlightMoveDuration: 100

                        model: ScriptModel {
                            id: folderModel
                            objectProp: "key"
                        }

                        delegate: SearchItem {
                            id: folderItem
                            required property var modelData
                            anchors.left: parent?.left
                            anchors.right: parent?.right
                            entry: modelData
                            query: StringUtils.cleanPrefix(root.searchingText, Config.options.search.prefix.fileSearch)
                        }
                    }
                }

                // Separator
                Rectangle {
                    Layout.fillHeight: true
                    width: 1
                    color: Appearance.colors.colOutlineVariant
                }

                // Files column
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        height: 28
                        color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: Translation.tr("Files")
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                        }
                    }

                    ListView {
                        id: fileResults
                        Layout.fillWidth: true
                        Layout.preferredWidth: 400
                        implicitHeight: Math.min(400, fileResults.contentHeight + topMargin + bottomMargin)
                        clip: true
                        topMargin: 4
                        bottomMargin: 10
                        spacing: 2
                        interactive: true
                        currentIndex: -1
                        highlightFollowsCurrentItem: true
                        highlightMoveDuration: 100

                        model: ScriptModel {
                            id: fileModel
                            objectProp: "key"
                        }

                        delegate: SearchItem {
                            id: fileItem
                            required property var modelData
                            anchors.left: parent?.left
                            anchors.right: parent?.right
                            entry: modelData
                            query: StringUtils.cleanPrefix(root.searchingText, Config.options.search.prefix.fileSearch)
                        }
                    }
                }

                // Update file search models when results change
                Connections {
                    target: LauncherSearch
                    function onResultsChanged() {
                        if (root.isFileSearchMode) {
                            const allResults = LauncherSearch.results ?? [];
                            // Filter by checking the iconName property
                            const folders = [];
                            const files = [];
                            for (const r of allResults) {
                                if (r && r.iconName === "folder") {
                                    folders.push(r);
                                } else if (r && r.iconName === "file_open") {
                                    files.push(r);
                                }
                            }
                            folderModel.values = folders;
                            fileModel.values = files;
                        }
                    }
                }
            }
        }
    }
}
