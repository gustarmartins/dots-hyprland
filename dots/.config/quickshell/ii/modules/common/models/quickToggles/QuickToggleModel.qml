import QtQuick

QtObject {
    // Textual info
    required property string name
    property string statusText
    property string tooltipText: ""
    property string icon: "close"

    // State
    property bool hasStatusText: true
    property bool available: true
    property bool toggled: false

    // Interactions
    required property var mainAction
    property bool hasMenu: false
    property var altAction: null
    // Opt-in for action tiles whose alternate operation must require an
    // actual right mouse click. Existing split-button/menu toggles keep their
    // original behavior.
    property bool altActionOnRightClick: false

    // Allow stuff like Processes to be declared freely
    default property list<QtObject> data
}
