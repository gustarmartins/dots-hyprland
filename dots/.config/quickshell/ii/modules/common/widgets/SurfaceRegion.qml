import QtQuick
import Quickshell

// Share the painted surface's geometry between the input and native blur masks.
Region {
    property Item surface: null
    item: surface
    radius: Math.round(surface?.radius ?? 0)
    topLeftRadius: Math.round(surface?.topLeftRadius ?? radius)
    topRightRadius: Math.round(surface?.topRightRadius ?? radius)
    bottomLeftRadius: Math.round(surface?.bottomLeftRadius ?? radius)
    bottomRightRadius: Math.round(surface?.bottomRightRadius ?? radius)
}
