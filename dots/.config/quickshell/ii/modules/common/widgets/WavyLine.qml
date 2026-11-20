import qs.modules.common
import QtQuick

Canvas {
    id: root
    property real amplitudeMultiplier: 0.5
    property real frequency: 6
    property color color: Appearance?.colors.colPrimary ?? "#685496"
    property real lineWidth: 4
    property real fullLength: width

    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        const amplitude = root.lineWidth * root.amplitudeMultiplier;
        const first = root.lineWidth / 2;
        const last = width - first;
        if (last < first || root.fullLength <= 0) return;
        const step = root.frequency * 2 * Math.PI / root.fullLength;
        const angle = Date.now() / 400.0 + first * step;
        const sinStep = Math.sin(step), cosStep = Math.cos(step);
        let sin = Math.sin(angle), cos = Math.cos(angle);
        const centerY = height / 2;

        ctx.strokeStyle = root.color;
        ctx.lineWidth = root.lineWidth;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(first, centerY + amplitude * sin);
        // Advance the angle by one pixel without a trigonometric call for each vertex.
        for (let x = first + 1; x <= last; ++x) {
            const nextSin = sin * cosStep + cos * sinStep;
            cos = cos * cosStep - sin * sinStep;
            sin = nextSin;
            ctx.lineTo(x, centerY + amplitude * sin);
        }
        ctx.stroke();
    }
}
