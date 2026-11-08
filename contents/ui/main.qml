/*
 A modern and informative window switcher layout for KWin.

 SPDX-FileCopyrightText: 2011 Martin Gräßlin <mgraesslin@kde.org>
 SPDX-FileCopyrightText: 2023 Mélanie Chauvel (ariasuni) <perso@hack-libre.org>

 SPDX-License-Identifier: GPL-2.0-or-later
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kwin as KWin

KWin.TabBoxSwitcher {
    id: tabBox
    currentIndex: compactListView.currentIndex

    /**
     * Map of window ID (cleaned UUID string) and caption to screen name.
     */
    property var windowScreenMap: ({})
    property var seenDelegateScreens: ({})
    property int delegateScreenCount: 0
    property bool multiScreenActive: false

    readonly property bool isPreviewMode: {
        return typeof KWin === "undefined" || !KWin.Workspace;
    }

    readonly property bool isAllScreens: {
        if (isPreviewMode) {
            return true;
        }
        if (!KWin.Workspace.screens || KWin.Workspace.screens.length <= 1) {
            return false;
        }
        if (typeof tabBox.allScreens !== "undefined") {
            return tabBox.allScreens;
        }
        return multiScreenActive;
    }

    function cleanId(id) {
        if (!id) return "";
        return String(id).replace(/[{}]/g, "").trim().toLowerCase();
    }

    function getWindowList() {
        if (typeof KWin === "undefined" || !KWin.Workspace) {
            return [];
        }
        var wins = KWin.Workspace.windows;
        if (wins && wins.length > 0) {
            return wins;
        }
        wins = KWin.Workspace.stackingOrder;
        if (wins && wins.length > 0) {
            return wins;
        }
        if (typeof KWin.Workspace.windowList === "function") {
            return KWin.Workspace.windowList();
        }
        return [];
    }

    function refreshScreenMap() {
        var map = {};
        var wins = getWindowList();
        for (var i = 0; i < wins.length; i++) {
            var w = wins[i];
            if (!w) continue;
            var sName = (w.output && w.output.name) ? w.output.name : "";
            if (!sName && KWin.Workspace && KWin.Workspace.screens) {
                var wx = w.x !== undefined ? (w.x + (w.width || 0) / 2) : 0;
                var wy = w.y !== undefined ? (w.y + (w.height || 0) / 2) : 0;
                for (var s = 0; s < KWin.Workspace.screens.length; s++) {
                    var scr = KWin.Workspace.screens[s];
                    if (scr && scr.geometry) {
                        var g = scr.geometry;
                        if (wx >= g.x && wx < g.x + g.width && wy >= g.y && wy < g.y + g.height) {
                            sName = scr.name;
                            break;
                        }
                    }
                }
            }
            var cid = cleanId(w.internalId);
            if (cid) {
                map[cid] = sName;
            }
            if (w.caption && !map["cap:" + w.caption]) {
                map["cap:" + w.caption] = sName;
            }
        }
        windowScreenMap = map;
    }

    function screenNameForWindow(winId, winCaption, itemIndex) {
        if (isPreviewMode) {
            if (Qt.application && Qt.application.screens && Qt.application.screens.length > 0) {
                var idx = (itemIndex !== undefined && itemIndex >= 0) ? (itemIndex % Qt.application.screens.length) : 0;
                var qScreen = Qt.application.screens[idx];
                if (qScreen && qScreen.name && qScreen.name.length > 0) {
                    return qScreen.name;
                }
            }
            return (itemIndex !== undefined && itemIndex % 2 === 1) ? "HDMI-A-1" : "DP-1";
        }
        var cid = cleanId(winId);
        if (cid && windowScreenMap[cid]) {
            return windowScreenMap[cid];
        }
        if (winCaption && windowScreenMap["cap:" + winCaption]) {
            return windowScreenMap["cap:" + winCaption];
        }
        return "";
    }

    function registerDelegateScreen(name) {
        if (!name) return;
        if (!seenDelegateScreens[name]) {
            seenDelegateScreens[name] = true;
            delegateScreenCount++;
            if (delegateScreenCount > 1) {
                multiScreenActive = true;
            }
        }
    }

    function updateScreenInfo() {
        if (isPreviewMode) {
            multiScreenActive = true;
            return;
        }

        refreshScreenMap();
        seenDelegateScreens = {};
        delegateScreenCount = 0;

        if (!KWin.Workspace || !KWin.Workspace.screens || KWin.Workspace.screens.length <= 1) {
            multiScreenActive = false;
            return;
        }

        var switcherScreens = {};
        var uniqueCount = 0;
        var activeOutputName = KWin.Workspace.activeScreen ? KWin.Workspace.activeScreen.name : "";
        var hasWindowOnOtherScreen = false;

        var count = tabBox.model ? (typeof tabBox.model.rowCount === "function" ? tabBox.model.rowCount() : compactListView.count) : 0;
        for (var i = 0; i < count; i++) {
            var ind = tabBox.model.index(i, 0);
            var wid = tabBox.model.data(ind, 261); // WIdRole = Qt::UserRole + 5
            var cap = tabBox.model.data(ind, 257); // CaptionRole = Qt::UserRole + 1
            var sName = screenNameForWindow(wid, cap, i);
            if (sName) {
                if (!switcherScreens[sName]) {
                    switcherScreens[sName] = true;
                    uniqueCount++;
                }
                if (activeOutputName && sName !== activeOutputName) {
                    hasWindowOnOtherScreen = true;
                }
            }
        }

        // 1. If switcher contains windows on multiple screens or a window not on active screen,
        // filtering by screen is disabled.
        if (uniqueCount > 1 || hasWindowOnOtherScreen) {
            multiScreenActive = true;
            return;
        }

        // 2. Check if other screens in workspace have switcher-eligible windows
        var allWins = getWindowList();
        var otherScreensHaveWindows = false;
        for (var j = 0; j < allWins.length; j++) {
            var w = allWins[j];
            if (w && w.output && w.normalWindow && !w.skipSwitcher) {
                if (activeOutputName && w.output.name !== activeOutputName) {
                    otherScreensHaveWindows = true;
                    break;
                }
            }
        }

        // If windows exist on other screens, but none are in switcher,
        // then filtering by screen is ENABLED.
        if (otherScreensHaveWindows) {
            multiScreenActive = false;
            return;
        }

        // If all open windows are on current screen in a multi-monitor environment,
        // treat as multi-screen active when filtering by screen is disabled (default).
        multiScreenActive = true;
    }

    /**
    * Returns the caption with adjustments for minimized items.
    * @param caption the original caption
    * @param mimized whether the item is minimized
    * @return Caption adjusted for minimized state
    **/
    function itemCaption(caption, minimized) {
        if (minimized) {
            return "(" + caption + ")";
        }
        return caption;
    }

    TextMetrics {
        id: textMetrics
        property string longestCaption: tabBox.model?.longestCaption() || ""
        text: itemCaption(longestCaption, true)
    }

    onVisibleChanged: {
        if (visible) {
            // Window captions may have changed completely
            textMetrics.longestCaption = tabBox.model?.longestCaption() || "";
            tabBox.updateScreenInfo();
        }
    }
    onModelChanged: {
        textMetrics.longestCaption = tabBox.model?.longestCaption() || "";
        tabBox.updateScreenInfo();
    }
    Component.onCompleted: {
        tabBox.updateScreenInfo();
    }

    PlasmaCore.Dialog {
        id: dialog
        location: PlasmaCore.Types.Floating
        visible: tabBox.visible
        flags: Qt.X11BypassWindowManagerHint
        x: tabBox.screenGeometry.x + tabBox.screenGeometry.width * 0.5 - dialogMainItem.width * 0.5
        y: tabBox.screenGeometry.y + tabBox.screenGeometry.height * 0.5 - dialogMainItem.height * 0.5

        mainItem: Item {
            id: dialogMainItem

            property int extraWidth: (tabBox.allDesktops ? Kirigami.Units.gridUnit * 5 : 0) + (tabBox.isAllScreens ? Kirigami.Units.gridUnit * 5 : 0)
            property int optimalWidth: textMetrics.width + Kirigami.Units.iconSizes.medium + 2 * Kirigami.Units.smallSpacing + hoverItem.margins.right + hoverItem.margins.left + extraWidth
            property int optimalHeight: compactListView.rowHeight * compactListView.count
            width: Math.min(Math.max(tabBox.screenGeometry.width * 0.25, optimalWidth), tabBox.screenGeometry.width * 0.8)
            height: Math.min(optimalHeight, tabBox.screenGeometry.height * 0.8)
            focus: true

            // just to get the margin sizes
            KSvg.FrameSvgItem {
                id: hoverItem
                imagePath: "widgets/viewitem"
                prefix: "hover"
                visible: false
            }

            ListView {
                id: compactListView

                property int rowHeight: Math.max(Kirigami.Units.iconSizes.medium, textMetrics.height) + hoverItem.margins.top * 2 + hoverItem.margins.bottom * 2

                anchors.fill: parent
                clip: true

                model: tabBox.model
                delegate: RowLayout {

                    width: compactListView.width
                    height: compactListView.rowHeight
                    opacity: minimized ? 0.6 : 1.0

                    spacing: 2 * Kirigami.Units.mediumSpacing

                    Kirigami.Icon {
                        id: iconItem
                        source: model.icon
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                        Layout.leftMargin: hoverItem.margins.left * 2
                        Layout.topMargin: hoverItem.margins.top
                        Layout.bottomMargin: hoverItem.margins.bottom
                    }
                    PlasmaComponents3.Label {
                        id: captionItem
                        horizontalAlignment: Text.AlignLeft
                        verticalAlignment: Text.AlignBottom
                        text: itemCaption(caption, minimized)
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        Layout.topMargin: hoverItem.margins.top
                        Layout.bottomMargin: hoverItem.margins.bottom
                        Layout.rightMargin: (screenNameItem.visible || desktopNameItem.visible) ? 0 : hoverItem.margins.right * 2
                    }
                    PlasmaComponents3.Label {
                        id: screenNameItem
                        readonly property string screenName: tabBox.screenNameForWindow(windowId, caption, index)
                        text: screenName
                        elide: Text.ElideMiddle
                        visible: tabBox.isAllScreens && screenName.length > 0
                        opacity: 0.75
                        Layout.topMargin: hoverItem.margins.top
                        Layout.bottomMargin: hoverItem.margins.bottom
                        Layout.rightMargin: desktopNameItem.visible ? 0 : hoverItem.margins.right * 2
                        Component.onCompleted: {
                            if (screenName) {
                                tabBox.registerDelegateScreen(screenName);
                            }
                        }
                    }
                    PlasmaComponents3.Label {
                        id: desktopNameItem
                        text: desktopName
                        elide: Text.ElideMiddle
                        visible: tabBox.allDesktops
                        opacity: 0.75
                        Layout.rightMargin: hoverItem.margins.right * 2
                        Layout.topMargin: hoverItem.margins.top
                        Layout.bottomMargin: hoverItem.margins.bottom
                    }
                    TapHandler {
                        onSingleTapped: {
                            if (index === compactListView.currentIndex) {
                                compactListView.model.activate(index);
                                return;
                            }
                            compactListView.currentIndex = index;
                        }
                        onDoubleTapped: compactListView.model.activate(index)
                    }
                }
                highlight: KSvg.FrameSvgItem {
                    imagePath: "widgets/viewitem"
                    prefix: "hover"
                    width: compactListView.width
                }
                highlightMoveDuration: 0
                highlightResizeDuration: 0
                boundsBehavior: Flickable.StopAtBounds
                Connections {
                    target: tabBox
                    function onCurrentIndexChanged() {compactListView.currentIndex = tabBox.currentIndex;}
                }
            }
            /*
            * Key navigation on outer item for two reasons:
            * @li we have to emit the change signal
            * @li on multiple invocation it does not work on the list view. Focus seems to be lost.
            **/
            Keys.onPressed: {
                if (event.key == Qt.Key_Up) {
                    compactListView.decrementCurrentIndex();
                } else if (event.key == Qt.Key_Down) {
                    compactListView.incrementCurrentIndex();
                }
            }
        }
    }
}
