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
    signal edited(string path)
    property string error: ""
    readonly property var value: read(setting.path)
    readonly property bool available: (setting.when || []).every(pair => read(pair[0]) === pair[1])
    readonly property bool compactEditor: ["toggle", "number", "choice", "monitor"].includes(setting.kind)
    objectName: "setting:" + setting.path
    implicitHeight: layout.implicitHeight + 28
    color: Appearance.m3colors.m3surfaceContainerLow
    radius: 14
    border.width: 1
    border.color: Appearance.m3colors.m3outlineVariant

    function read(path) {
        let obj = Config.options;
        for (const key of path.split(".")) { if (obj === undefined || obj === null) return undefined; obj = obj[key]; }
        return obj;
    }
    function dependencyMessage() {
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
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 10
        GridLayout {
            Layout.fillWidth: true
            columns: root.width > 630 && root.compactEditor ? 2 : 1
            columnSpacing: 20
            rowSpacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr(root.setting.title)
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    font.pixelSize: 15
                    color: Appearance.m3colors.m3onSurface
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
                Layout.fillWidth: !root.compactEditor || layout.width < 630
                Layout.preferredWidth: root.compactEditor ? Math.min(250, layout.width) : layout.width
                enabled: root.available && root.writable && Config.ready
                opacity: enabled ? 1 : 0.45
                sourceComponent: root.setting.kind === "toggle" ? toggleEditor
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
        RowLayout {
            spacing: 4
            readonly property real factor: root.setting.scale || 1
            function increment(delta) {
                root.commit(Math.max(root.setting.min, Math.min(root.setting.max,
                    Number(root.value) * factor + delta)) / factor);
            }
            SettingsButton { text: "−"; implicitWidth: 38; Accessible.name: "Decrease " + root.setting.title; onClicked: parent.increment(-root.setting.step) }
            SettingsField {
                objectName: "number:" + root.setting.path
                Layout.fillWidth: true
                horizontalAlignment: TextInput.AlignHCenter
                text: String(Math.round(Number(root.value) * parent.factor * 1000) / 1000)
                selectByMouse: true
                Accessible.name: root.setting.title
                validator: DoubleValidator { bottom: root.setting.min; top: root.setting.max; decimals: 3; locale: "C" }
                onEditingFinished: {
                    const n = Number(text);
                    if (!text.trim() || !Number.isFinite(n) || n < root.setting.min || n > root.setting.max)
                        root.error = "Enter a value from " + root.setting.min + " to " + root.setting.max + ".";
                    else root.commit(n / parent.factor);
                }
            }
            StyledText { visible: !!root.setting.suffix; text: root.setting.suffix || ""; font.pixelSize: 12 }
            SettingsButton { text: "+"; implicitWidth: 38; Accessible.name: "Increase " + root.setting.title; onClicked: parent.increment(root.setting.step) }
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
        SettingsField {
            objectName: "text:" + root.setting.path
            text: String(root.value ?? "")
            selectByMouse: true
            Accessible.name: root.setting.title
            placeholderText: root.setting.path === "language.ui" ? "auto" : ""
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
