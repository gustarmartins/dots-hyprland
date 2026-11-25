import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.services
import "SettingsCatalog.js" as Catalog
import qs.modules.common.widgets

Rectangle {
    id: root
    required property var setting
    property bool writable: true
    // Android 16 / Material 3 Expressive segmented group position: "single", "first", "middle", "last"
    property string groupPosition: "single"
    property bool flatRow: false
    signal edited(string path)
    signal providerEdited(var next)
    signal navigate(string page)
    property var providerValue
    property string unavailableReason: ""
    property string error: ""
    readonly property var value: setting.provider ? providerValue : setting.kind === "destination" ? undefined : read(setting.path)
    readonly property string valueSuffix: setting.unit ? (Catalog.timeUnits[setting.unit] || setting.unit) : (setting.suffix || "")
    readonly property string accessibleTitle: setting.title + (valueSuffix ? ", " + valueSuffix : "")
    readonly property bool available: !unavailableReason && (setting.when || []).every(pair => read(pair[0]) === pair[1])
    readonly property bool compactEditor: ["toggle", "number", "choice", "monitor", "destination"].includes(setting.kind)
    readonly property bool alwaysInline: ["toggle", "destination"].includes(setting.kind)
    readonly property bool isLight: Appearance.m3colors.darkmode === false
    readonly property color surfaceRest: flatRow
        ? "transparent"
        : (isLight ? (Appearance.m3colors.m3surfaceContainerLowest ?? Appearance.m3colors.m3surfaceContainerLow) : Appearance.m3colors.m3surfaceContainerLow)
    readonly property color surfaceHover: flatRow
        ? Qt.alpha(Appearance.m3colors.m3onSurface, 0.04)
        : (isLight ? (Appearance.m3colors.m3surfaceContainer ?? Appearance.m3colors.m3surfaceContainerHigh) : (Appearance.m3colors.m3surfaceContainer ?? Appearance.m3colors.m3surfaceContainerHigh))
    readonly property real outerRadius: 18
    readonly property real innerRadius: 4

    objectName: "setting:" + setting.path
    implicitHeight: layout.implicitHeight + (flatRow ? 22 : 26)
    color: rowHover.hovered && root.available ? surfaceHover : surfaceRest
    topLeftRadius: flatRow ? 10 : (groupPosition === "single" || groupPosition === "first") ? outerRadius : innerRadius
    topRightRadius: flatRow ? 10 : (groupPosition === "single" || groupPosition === "first") ? outerRadius : innerRadius
    bottomLeftRadius: flatRow ? 10 : (groupPosition === "single" || groupPosition === "last") ? outerRadius : innerRadius
    bottomRightRadius: flatRow ? 10 : (groupPosition === "single" || groupPosition === "last") ? outerRadius : innerRadius
    border.width: 0
    Behavior on color { ColorAnimation { duration: 120 } }

    HoverHandler { id: rowHover }

    function read(path) {
        let obj = Config.options;
        for (const key of path.split(".")) { if (obj === undefined || obj === null) return undefined; obj = obj[key]; }
        return obj;
    }
    function dependencyMessage() {
        if (unavailableReason) return unavailableReason;
        return (setting.when || []).filter(pair => read(pair[0]) !== pair[1]).map(pair => {
            const spec = Catalog.entries.find(e => e.path === pair[0]);
            const title = spec?.title ?? "the related option";
            if (typeof pair[1] === "boolean") return (pair[1] ? "Turn on “" : "Turn off “") + title + "” first.";
            const choice = spec?.choices?.find(c => c.value === pair[1]);
            return "Choose “" + (choice?.label ?? pair[1]) + "” under “" + title + "”.";
        }).join(" ");
    }
    function commit(next) {
        if (!root.writable || !root.available || !Config.ready) return;
        if (setting.provider) {
            if (next !== root.value) root.providerEdited(next);
            root.error = "";
            return;
        }
        let keys = setting.path.split("."); let obj = Config.options;
        for (let i = 0; i < keys.length - 1; i++) obj = obj[keys[i]];
        if (JSON.stringify(obj[keys[keys.length - 1]]) !== JSON.stringify(next)) {
            obj[keys[keys.length - 1]] = next;
            root.edited(setting.path);
        }
        root.error = "";
    }
    ColumnLayout {
        id: layout
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: root.flatRow ? 12 : 18; rightMargin: root.flatRow ? 12 : 18; topMargin: root.flatRow ? 11 : 13 }
        spacing: 8
        GridLayout {
            Layout.fillWidth: true
            columns: (root.alwaysInline ? root.width > 300 : root.width > 520) && root.compactEditor ? 2 : 1
            columnSpacing: 20
            rowSpacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr(root.setting.title)
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: root.available ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: Translation.tr(root.setting.description || "")
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    color: Appearance.m3colors.m3onSurfaceVariant
                }
            }
            Loader {
                id: editor
                Layout.alignment: root.setting.kind === "toggle" ? (Qt.AlignRight | Qt.AlignVCenter) : Qt.AlignVCenter
                Layout.fillWidth: !root.compactEditor || (!root.alwaysInline && layout.width <= 520)
                Layout.preferredWidth: root.setting.kind === "toggle" ? 52
                    : root.setting.kind === "destination" ? 96
                    : root.compactEditor ? Math.min(root.valueSuffix ? 290 : 244, layout.width) : layout.width
                enabled: root.available && root.writable && Config.ready
                opacity: enabled ? 1 : 0.48
                sourceComponent: root.setting.kind === "destination" ? destinationEditor
                    : root.setting.kind === "toggle" ? toggleEditor
                    : root.setting.kind === "number" ? numberEditor
                    : root.setting.kind === "choice" || root.setting.kind === "monitor" ? choiceEditor
                    : root.setting.kind === "info" ? infoEditor
                    : root.setting.kind === "tiles" ? tileEditor
                    : ["lines", "json", "longtext"].includes(root.setting.kind) ? areaEditor : textEditor
            }
        }
        StyledText {
            visible: !root.available
            Layout.fillWidth: true
            text: root.dependencyMessage()
            wrapMode: Text.WordWrap
            font.pixelSize: 12
            color: Appearance.m3colors.m3onSurfaceVariant
        }
        StyledText {
            visible: root.error.length > 0
            Layout.fillWidth: true
            text: root.error
            wrapMode: Text.WordWrap
            color: Appearance.m3colors.m3error
            font.pixelSize: 12
        }
    }
    Component {
        id: destinationEditor
        SettingsButton {
            text: Translation.tr("Open")
            Accessible.name: Translation.tr("Open") + " " + root.setting.title
            onClicked: root.navigate(root.setting.page)
        }
    }
    Component {
        id: toggleEditor
        SettingsSwitch {
            objectName: "toggle:" + root.setting.path
            checked: !!root.value
            Accessible.name: root.setting.title
            onToggled: root.commit(checked)
        }
    }
    Component {
        id: numberEditor
        Rectangle {
            id: stepperShell
            implicitHeight: 40
            radius: 12
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: numField.activeFocus ? 2 : 1
            border.color: numField.activeFocus ? Appearance.m3colors.m3primary : Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.7)
            readonly property real factor: root.setting.scale || 1
            function increment(delta) {
                root.commit(Math.max(root.setting.min, Math.min(root.setting.max,
                    Number(root.value) * factor + delta)) / factor);
            }
            RowLayout {
                anchors.fill: parent
                anchors.margins: 2
                spacing: 2
                Button {
                    id: decBtn
                    implicitWidth: 34
                    Layout.fillHeight: true
                    Accessible.name: "Decrease " + root.accessibleTitle
                    onClicked: stepperShell.increment(-root.setting.step)
                    background: Rectangle {
                        radius: 10
                        color: decBtn.down ? Appearance.m3colors.m3secondaryContainer
                            : decBtn.hovered ? Appearance.m3colors.m3surfaceContainerHighest : "transparent"
                    }
                    contentItem: StyledText {
                        text: "−"
                        font.pixelSize: 17
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: decBtn.down ? (Appearance.m3colors.m3onSecondaryContainer ?? Appearance.m3colors.m3onSurface) : Appearance.m3colors.m3onSurface
                    }
                }
                TextField {
                    id: numField
                    objectName: "number:" + root.setting.path
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    color: Appearance.m3colors.m3onSurface
                    selectionColor: Appearance.m3colors.m3primary
                    selectedTextColor: Appearance.m3colors.m3onPrimary
                    background: Item {}
                    text: String(Math.round(Number(root.value) * stepperShell.factor * 1000) / 1000)
                    selectByMouse: true
                    Accessible.name: root.accessibleTitle
                    validator: DoubleValidator { bottom: root.setting.min; top: root.setting.max; decimals: 3; locale: "C" }
                    function commitText() {
                        if (!Config.ready || !root.writable || !root.available) return;
                        const n = Number(text);
                        if (!text.trim() || !Number.isFinite(n) || n < root.setting.min || n > root.setting.max)
                            root.error = "Enter a value from " + root.setting.min + " to " + root.setting.max + (root.valueSuffix ? " " + root.valueSuffix : "") + ".";
                        else root.commit(n / stepperShell.factor);
                    }
                    onEditingFinished: commitText()
                    onActiveFocusChanged: if (!activeFocus) commitText()
                }
                StyledText {
                    objectName: "unit:" + root.setting.path
                    visible: root.valueSuffix.length > 0
                    text: root.valueSuffix
                    font.pixelSize: 12
                    color: Appearance.m3colors.m3onSurfaceVariant
                    Layout.rightMargin: 4
                }
                Button {
                    id: incBtn
                    implicitWidth: 34
                    Layout.fillHeight: true
                    Accessible.name: "Increase " + root.accessibleTitle
                    onClicked: stepperShell.increment(root.setting.step)
                    background: Rectangle {
                        radius: 10
                        color: incBtn.down ? Appearance.m3colors.m3secondaryContainer
                            : incBtn.hovered ? Appearance.m3colors.m3surfaceContainerHighest : "transparent"
                    }
                    contentItem: StyledText {
                        text: "+"
                        font.pixelSize: 17
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: incBtn.down ? (Appearance.m3colors.m3onSecondaryContainer ?? Appearance.m3colors.m3onSurface) : Appearance.m3colors.m3onSurface
                    }
                }
            }
        }
    }
    Component {
        id: choiceEditor
        SettingsComboBox {
            id: choice
            objectName: "choice:" + root.setting.path
            property var choices: root.setting.kind === "monitor"
                ? [{label: "Choose output", value: ""}].concat(Quickshell.screens.map(s => ({label:s.name, value:s.name})))
                : root.setting.choices
            model: choices
            textRole: "label"
            valueRole: "value"
            currentIndex: choices.findIndex(c => c.value === root.value)
            displayText: currentIndex < 0 ? String(root.value) : currentText
            Accessible.name: root.setting.title
            onActivated: index => root.commit(choices[index].value)
        }
    }
    Component {
        id: textEditor
        RowLayout {
            spacing: 8
            readonly property bool isColor: root.setting.validation === "color"
            readonly property bool validHex: isColor && /^#[0-9a-fA-F]{6}$/.test(field.text.trim())
            Rectangle {
                visible: parent.isColor
                implicitWidth: 28
                implicitHeight: 28
                radius: 14
                color: parent.validHex ? field.text.trim() : Appearance.m3colors.m3primary
                border.width: 1.5
                border.color: Appearance.m3colors.m3outlineVariant
            }
            SettingsField {
                id: field
                objectName: "text:" + root.setting.path
                Layout.fillWidth: true
                text: String(root.value ?? "")
                selectByMouse: true
                Accessible.name: root.setting.title
                placeholderText: root.setting.path === "language.ui" ? "auto" : parent.isColor ? "Wallpaper automatic (or #006878)" : ""
                onEditingFinished: {
                    if (["light.night.from", "light.night.to"].includes(root.setting.path)
                        && !/^([01]\d|2[0-3]):[0-5]\d$/.test(text)) {
                        root.error = "Use a 24-hour time such as 19:00."; return;
                    }
                    if (root.setting.validation === "color" && text.trim() && !/^#[0-9a-fA-F]{6}$/.test(text.trim())) {
                        root.error = "Use a six-digit color such as #a5b4fc, or leave empty."; return;
                    }
                    root.commit(text);
                }
            }
            SettingsButton {
                visible: parent.isColor && String(root.value ?? "").trim().length > 0
                text: "Reset"
                implicitHeight: 40
                onClicked: { field.text = ""; root.commit(""); }
            }
        }
    }
    Component {
        id: areaEditor
        ColumnLayout {
            spacing: 8
            TextArea {
                id: area
                objectName: "text:" + root.setting.path
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(180, Math.max(80, contentHeight + 20))
                padding: 10
                color: Appearance.m3colors.m3onSurface
                placeholderTextColor: Appearance.m3colors.m3onSurfaceVariant
                selectionColor: Appearance.m3colors.m3primary
                selectedTextColor: Appearance.m3colors.m3onPrimary
                background: Rectangle {
                    radius: 12
                    color: Appearance.m3colors.m3surfaceContainerHigh
                    border.width: area.activeFocus ? 2 : 1
                    border.color: area.activeFocus ? Appearance.m3colors.m3primary : Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.7)
                }
                text: root.setting.kind === "lines" ? Array.from(root.value || []).join("\n")
                    : root.setting.kind === "json" ? JSON.stringify(root.value, null, 2) : String(root.value ?? "")
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                Accessible.name: root.setting.title
            }
            RowLayout {
                SettingsButton {
                    objectName: "save:" + root.setting.path
                    text: "Save"
                    onClicked: {
                        let next = area.text;
                        if (root.setting.kind === "lines") next = next.split("\n").map(s => s.trim()).filter(s => s.length > 0);
                        if (root.setting.kind === "json") {
                            try {
                                next = JSON.parse(next);
                                if (!Array.isArray(next) || next.some(model => !model || typeof model !== "object"
                                    || ["name", "model", "endpoint"].some(key => typeof model[key] !== "string" || !model[key].trim())))
                                    throw new Error("Each model needs a name, model and endpoint");
                            }
                            catch (e) { root.error = "Enter a JSON array of models, each with a name, model and endpoint. Nothing was saved."; return; }
                        }
                        root.commit(next);
                    }
                }
                StyledText { text: root.setting.kind === "lines" ? "One entry per line" : "Use Save to keep these edits"; font.pixelSize: 12; color: Appearance.m3colors.m3onSurfaceVariant }
            }
        }
    }
    Component { id: infoEditor; StyledText { text: String(root.value ?? ""); wrapMode: Text.WordWrap; font.pixelSize: 13 } }
    Component { id: tileEditor; QuickTileEditor { tiles: root.value || []; onEdited: value => root.commit(value) } }
}
