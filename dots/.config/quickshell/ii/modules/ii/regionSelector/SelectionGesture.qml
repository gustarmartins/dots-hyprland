import QtQuick

// Pointer ownership is independent of the window or layer beneath the selector.
MouseArea {
    id: root
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    preventStealing: true
    cursorShape: Qt.CrossCursor
    property bool accepting: true
    property bool dragging: false
    property int ownerButton: Qt.NoButton
    property real startX: 0
    property real startY: 0
    property real endX: 0
    property real endY: 0
    property bool moved: false
    property list<point> points: []
    readonly property real regionX: Math.min(startX, endX)
    readonly property real regionY: Math.min(startY, endY)
    readonly property real regionWidth: Math.abs(endX - startX)
    readonly property real regionHeight: Math.abs(endY - startY)
    signal pointerMoved(real px, real py)
    signal started()
    signal finished(real px, real py, int button, bool wasMoved)
    signal interrupted(string reason)

    function reset() {
        dragging = false;
        ownerButton = Qt.NoButton;
        startX = endX = startY = endY = 0;
        moved = false;
        points = [];
    }
    function updatePosition(px, py) {
        endX = px; endY = py;
        moved = moved || px !== startX || py !== startY;
        const last = points[points.length - 1];
        if (!last || last.x !== px || last.y !== py) points.push(Qt.point(px, py));
    }
    function begin(px, py, button, modifiers) {
        if (!accepting || dragging || (button !== Qt.LeftButton && button !== Qt.RightButton)) return;
        if (modifiers & (Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier)) {
            interrupted("Release the shortcut keys, then drag to select.");
            return;
        }
        reset();
        startX = endX = px; startY = endY = py;
        points = [Qt.point(px, py)];
        ownerButton = button;
        dragging = true;
        started();
        pointerMoved(px, py);
    }
    function finish(px, py, button) {
        if (!accepting || !dragging || button !== ownerButton) return;
        updatePosition(px, py); // Releases can arrive without a final motion event.
        dragging = false;
        ownerButton = Qt.NoButton;
        finished(px, py, button, moved);
    }
    function cancelGesture() {
        const wasDragging = dragging;
        reset();
        if (wasDragging) interrupted("Selection interrupted. Drag again.");
    }
    onAcceptingChanged: if (!accepting) cancelGesture()
    onPressed: mouse => begin(mouse.x, mouse.y, mouse.button, mouse.modifiers)
    onReleased: mouse => finish(mouse.x, mouse.y, mouse.button)
    onCanceled: cancelGesture()
    onPositionChanged: mouse => {
        pointerMoved(mouse.x, mouse.y);
        if (dragging) updatePosition(mouse.x, mouse.y);
    }
}
