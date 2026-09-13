pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import org.kde.syntaxhighlighting

ColumnLayout {
    id: root
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property var segmentContent: ({})
    property var segmentLang: "txt"
    property var messageData: {}
    property bool isCommandRequest: segmentLang === "command"
    property var displayLang: (isCommandRequest ? "bash" : segmentLang)

    property bool expanded: !isCommandRequest || (segmentContent.split("\n").length <= 2)

    spacing: 3

    function getCommandAnalysis(cmdText) {
        if (!cmdText || typeof cmdText !== "string") {
            return {
                binary: "bash",
                category: "general",
                label: "EXEC",
                icon: "terminal",
                bg: "#181a1f",
                badgeBg: "#282c34",
                fg: "#adb5bd",
                border: "#3a3f4b"
            };
        }

        const trimmed = cmdText.trim();
        // Extract first binary word
        const words = trimmed.replace(/^[A-Za-z0-9_]+=[^\s]+\s+/, "").split(/\s+/);
        let binary = words[0] || "bash";
        if (binary === "sudo" && words.length > 1) {
            binary = `sudo ${words[1]}`;
        }

        // Clean punctuation from binary name
        binary = binary.replace(/[^a-zA-Z0-9_\-\.]/g, "");

        const lower = trimmed.toLowerCase();

        // 1. Destructive / Dangerous
        if (/\b(sudo|rm|dd|mkfs|wipefs|fdisk|parted|reboot|shutdown|poweroff|kill|pkill|killall|mv)\b/.test(lower)) {
            return {
                binary: binary || "root",
                category: "destructive",
                label: "DESTRUCTIVE",
                icon: "warning",
                bg: "#2b1114",
                badgeBg: "#4a1c22",
                fg: "#ff8787",
                border: "#7a2732"
            };
        }

        // 2. Modifying / Write / Config
        if (/\b(mkdir|touch|cp|chmod|chown|sed|git|systemctl|journalctl|pacman|yay|paru|npm|pip|cargo|rustup|tar|unzip|zip|tee)\b/.test(lower) || />/.test(lower)) {
            return {
                binary: binary || "write",
                category: "write",
                label: "MODIFY",
                icon: "edit_note",
                bg: "#261a0a",
                badgeBg: "#473012",
                fg: "#ffd43b",
                border: "#6b491b"
            };
        }

        // 3. Read-only / Inspection / Diagnostics
        if (/\b(find|which|type|cat|head|tail|ls|grep|rg|ip|ps|adb|adbc|df|free|uptime|wc|stat|file|uname|whoami|curl|wget|ping|awk|sort|uniq|ss|netstat)\b/.test(lower)) {
            return {
                binary: binary || "query",
                category: "read",
                label: "READ",
                icon: "search",
                bg: "#0c2117",
                badgeBg: "#173d2b",
                fg: "#69db7c",
                border: "#255c42"
            };
        }

        // 4. General / Unknown
        return {
            binary: binary || "exec",
            category: "general",
            label: "EXEC",
            icon: "terminal",
            bg: "#181a1f",
            badgeBg: "#282c34",
            fg: "#adb5bd",
            border: "#3a3f4b"
        };
    }

    readonly property var cmdInfo: root.isCommandRequest ? root.getCommandAnalysis(root.segmentContent) : ({})

    // =========================================================================
    // COMMAND EXECUTION CARD (When segment is a command)
    // =========================================================================
    Rectangle {
        visible: root.isCommandRequest
        Layout.fillWidth: true
        radius: Appearance.rounding.small
        color: root.cmdInfo.bg ?? Appearance.colors.colLayer2
        border.color: root.cmdInfo.border ?? Appearance.colors.colOutlineVariant
        border.width: 1
        implicitHeight: commandCardLayout.implicitHeight + 10

        ColumnLayout {
            id: commandCardLayout
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 6
            }
            spacing: 6

            // Header Bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                // Action Tag Badge
                Rectangle {
                    radius: Appearance.rounding.small
                    color: root.cmdInfo.badgeBg ?? "#333"
                    implicitHeight: 22
                    implicitWidth: tagRow.implicitWidth + 12

                    RowLayout {
                        id: tagRow
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            text: root.cmdInfo.icon ?? "terminal"
                            iconSize: 14
                            color: root.cmdInfo.fg ?? "#fff"
                        }
                        StyledText {
                            text: root.cmdInfo.label ?? "EXEC"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: root.cmdInfo.fg ?? "#fff"
                        }
                    }
                }

                // Main Binary Tag
                Rectangle {
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colSurfaceContainerHigh
                    implicitHeight: 22
                    implicitWidth: binaryText.implicitWidth + 12

                    StyledText {
                        id: binaryText
                        anchors.centerIn: parent
                        text: root.cmdInfo.binary ?? "bash"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.monoPixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                    }
                }

                // Single-line preview if collapsed
                StyledText {
                    visible: !root.expanded
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: (root.segmentContent || "").replace(/\n/g, " ").trim()
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.monoPixelSize.small
                    color: Appearance.colors.colSubtext
                }

                Item { Layout.fillWidth: true; visible: root.expanded }

                // Copy Command Button
                AiMessageControlButton {
                    id: copyCmdButton
                    buttonIcon: activated ? "inventory" : "content_copy"
                    onClicked: {
                        Quickshell.clipboardText = root.segmentContent
                        copyCmdButton.activated = true
                        cmdCopyTimer.restart()
                    }
                    Timer {
                        id: cmdCopyTimer
                        interval: 1500
                        onTriggered: copyCmdButton.activated = false
                    }
                    StyledToolTip { text: Translation.tr("Copy command") }
                }

                // Expand / Collapse Chevron
                AiMessageControlButton {
                    buttonIcon: root.expanded ? "expand_less" : "expand_more"
                    onClicked: root.expanded = !root.expanded
                    StyledToolTip { text: root.expanded ? Translation.tr("Collapse") : Translation.tr("Expand") }
                }
            }

            // Command Content Box (Expandable)
            Rectangle {
                visible: root.expanded
                Layout.fillWidth: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                implicitHeight: cmdScroll.implicitHeight + 8

                ScrollView {
                    id: cmdScroll
                    anchors {
                        fill: parent
                        margins: 4
                    }
                    implicitHeight: Math.min(cmdArea.implicitHeight + 4, 180)
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    TextArea {
                        id: cmdArea
                        readOnly: true
                        selectByMouse: true
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.monoPixelSize.small
                        wrapMode: TextEdit.Wrap
                        color: Appearance.colors.colOnSurface
                        text: root.segmentContent

                        SyntaxHighlighter {
                            textEdit: cmdArea
                            repository: Repository
                            definition: Repository.definitionForName("bash")
                            theme: Appearance.syntaxHighlightingTheme
                        }
                    }
                }
            }

            // Interactive Approval Buttons (If waiting for user permission)
            RowLayout {
                visible: root.messageData?.functionPending ?? false
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8

                Item { Layout.fillWidth: true }

                ButtonGroup {
                    GroupButton {
                        contentItem: StyledText {
                            text: Translation.tr("Reject")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                        }
                        onClicked: Ai.rejectCommand(root.messageData)
                    }
                    GroupButton {
                        toggled: true
                        contentItem: StyledText {
                            text: Translation.tr("Approve & Run")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimary
                        }
                        onClicked: Ai.approveCommand(root.messageData)
                    }
                }
            }
        }
    }

    // =========================================================================
    // STANDARD CODE BLOCK (For non-command code snippets: python, json, etc.)
    // =========================================================================
    Rectangle {
        visible: !root.isCommandRequest
        Layout.fillWidth: true
        topLeftRadius: Appearance.rounding.small
        topRightRadius: Appearance.rounding.small
        bottomLeftRadius: Appearance.rounding.unsharpen
        bottomRightRadius: Appearance.rounding.unsharpen
        color: Appearance.colors.colSurfaceContainerHighest
        implicitHeight: standardHeaderRow.implicitHeight + 6

        RowLayout {
            id: standardHeaderRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 4
            spacing: 5

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                text: root.displayLang ? Repository.definitionForName(root.displayLang).name : "plain"
            }

            Item { Layout.fillWidth: true }

            ButtonGroup {
                AiMessageControlButton {
                    id: copyCodeBtn
                    buttonIcon: activated ? "inventory" : "content_copy"
                    onClicked: {
                        Quickshell.clipboardText = root.segmentContent
                        copyCodeBtn.activated = true
                        codeTimer.restart()
                    }
                    Timer {
                        id: codeTimer
                        interval: 1500
                        onTriggered: copyCodeBtn.activated = false
                    }
                    StyledToolTip { text: Translation.tr("Copy code") }
                }
                AiMessageControlButton {
                    id: saveCodeBtn
                    buttonIcon: activated ? "check" : "save"
                    onClicked: {
                        const downloadPath = FileUtils.trimFileProtocol(Directories.downloads)
                        Quickshell.execDetached(["bash", "-c", 
                            `echo '${StringUtils.shellSingleQuoteEscape(root.segmentContent)}' > '${downloadPath}/code.${root.segmentLang || "txt"}'`
                        ])
                        Quickshell.execDetached(["notify-send", 
                            Translation.tr("Code saved to file"), 
                            Translation.tr("Saved to %1").arg(`${downloadPath}/code.${root.segmentLang || "txt"}`),
                            "-a", "Shell"
                        ])
                        saveCodeBtn.activated = true
                        saveTimer.restart()
                    }
                    Timer {
                        id: saveTimer
                        interval: 1500
                        onTriggered: saveCodeBtn.activated = false
                    }
                    StyledToolTip { text: Translation.tr("Save to Downloads") }
                }
            }
        }
    }

    RowLayout {
        visible: !root.isCommandRequest
        spacing: 2

        // Line Numbers
        Rectangle {
            implicitWidth: 36
            implicitHeight: lineNumbersCol.implicitHeight
            Layout.fillHeight: true
            color: Appearance.colors.colLayer2
            topLeftRadius: Appearance.rounding.unsharpen
            bottomLeftRadius: Appearance.rounding.small
            topRightRadius: Appearance.rounding.unsharpen
            bottomRightRadius: Appearance.rounding.unsharpen

            ColumnLayout {
                id: lineNumbersCol
                anchors {
                    left: parent.left
                    right: parent.right
                    rightMargin: 6
                    top: parent.top
                    topMargin: 6
                }
                spacing: 0
                Repeater {
                    model: standardCodeArea.text.split("\n").length
                    Text {
                        required property int index
                        Layout.fillWidth: true
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.monoPixelSize.small
                        color: Appearance.colors.colSubtext
                        horizontalAlignment: Text.AlignRight
                        text: index + 1
                    }
                }
            }
        }

        // Code Editor
        Rectangle {
            Layout.fillWidth: true
            color: Appearance.colors.colLayer2
            topLeftRadius: Appearance.rounding.unsharpen
            bottomLeftRadius: Appearance.rounding.unsharpen
            topRightRadius: Appearance.rounding.unsharpen
            bottomRightRadius: Appearance.rounding.small
            implicitHeight: standardScroll.implicitHeight + 8

            ScrollView {
                id: standardScroll
                anchors {
                    fill: parent
                    margins: 4
                }
                implicitHeight: standardCodeArea.implicitHeight + 2
                clip: true

                TextArea {
                    id: standardCodeArea
                    readOnly: !root.editing
                    selectByMouse: root.enableMouseSelection || root.editing
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.monoPixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: root.segmentContent
                    onTextChanged: { root.segmentContent = text }

                    SyntaxHighlighter {
                        textEdit: standardCodeArea
                        repository: Repository
                        definition: Repository.definitionForName(root.displayLang || "plaintext")
                        theme: Appearance.syntaxHighlightingTheme
                    }
                }
            }
        }
    }
}
