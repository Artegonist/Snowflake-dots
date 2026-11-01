import QtQuick

WheelHandler {
    id: ws

    // ------------------------- STATE -------------------------
    required property Flickable flick
    property real step: 64
    property bool keepPosition: true

    target: null
    orientation: Qt.Vertical
    enabled: ws.flick.contentHeight > ws.flick.height + 1

    property real goal: 0
    property real curY: 0
    property real prevY: 0

    // ------------------------- BOUNDS -------------------------
    function topY() {
        return ws.flick.originY - ws.flick.topMargin
    }

    function bottomY() {
        return Math.max(ws.topY(), ws.flick.originY + ws.flick.contentHeight + ws.flick.bottomMargin - ws.flick.height)
    }

    function clampY(y) {
        return Math.max(ws.topY(), Math.min(ws.bottomY(), y))
    }

    // ------------------------- WHEEL -------------------------
    onWheel: function(event) {
        const f = ws.flick
        const touchpad = event.pixelDelta.y !== 0
        const dy = touchpad ? -event.pixelDelta.y : -event.angleDelta.y / 120 * ws.step
        if (dy === 0)
            return
        f.cancelFlick()
        const base = scrollAnim.running ? ws.goal : f.contentY
        ws.goal = ws.clampY(base + dy)
        if (touchpad) {
            scrollAnim.stop()
            f.contentY = ws.goal
        } else {
            scrollAnim.to = ws.goal
            scrollAnim.restart()
        }
    }

    // ------------------------- ANIMATION -------------------------
    property NumberAnimation scrollAnim: NumberAnimation {
        id: scrollAnim
        target: ws.flick
        property: "contentY"
        duration: 170
        easing.type: Easing.OutCubic
    }

    // ------------------------- POSITION -------------------------
    function restore() {
        ws.flick.contentY = ws.clampY(ws.prevY)
    }

    function settle() {
        if (ws.flick.moving)
            return
        const y = ws.clampY(ws.flick.contentY)
        if (Math.abs(y - ws.flick.contentY) > 0.5) {
            scrollAnim.stop()
            ws.flick.contentY = y
        }
    }

    property Connections watcher: Connections {
        target: ws.flick
        ignoreUnknownSignals: true

        function onContentYChanged() {
            ws.prevY = ws.curY
            ws.curY = ws.flick.contentY
        }

        function onModelChanged() {
            scrollAnim.stop()
            if (ws.keepPosition && ws.prevY !== ws.curY && Math.abs(ws.curY - ws.topY()) < 1)
                Qt.callLater(ws.restore)
        }

        function onContentHeightChanged() { ws.settle() }
        function onHeightChanged() { ws.settle() }
    }

    // ------------------------- SETUP -------------------------
    Component.onCompleted: {
        ws.flick.interactive = Qt.binding(function() { return ws.flick.contentHeight > ws.flick.height + 1 })
        ws.flick.boundsBehavior = Flickable.StopAtBounds
        ws.flick.boundsMovement = Flickable.StopAtBounds
        ws.flick.pixelAligned = true
        ws.flick.flickDeceleration = 4000
        ws.flick.maximumFlickVelocity = 2500
        ws.curY = ws.flick.contentY
        ws.prevY = ws.curY
    }
}
