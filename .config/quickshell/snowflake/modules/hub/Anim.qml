import QtQuick

NumberAnimation {
    property string kind: "spatial"

    duration: kind === "fast" ? 350
            : kind === "slow" ? 650
            : kind === "effects" ? 200
            : 500
    easing.type: Easing.BezierSpline
    easing.bezierCurve: kind === "fast" ? [0.42, 1.67, 0.21, 0.9, 1, 1]
                      : kind === "slow" ? [0.39, 1.29, 0.35, 0.98, 1, 1]
                      : kind === "effects" ? [0.34, 0.8, 0.34, 1, 1, 1]
                      : [0.38, 1.21, 0.22, 1, 1, 1]
}
