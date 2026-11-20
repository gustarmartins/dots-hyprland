pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property real renderPadding: 4
    property var inFlight: new Set()
    property var renderedImagePaths: ({})
    property string microtexBinaryDir: "/opt/MicroTeX"
    property string microtexBinaryName: "LaTeX"
    property string latexOutputPath: Directories.latexOutput
    signal renderFinished(string hash, string imagePath)

    function requestRender(expression) {
        const hash = Qt.md5(expression);
        if (renderedImagePaths[hash] || inFlight.has(hash)) return [hash, false];
        inFlight.add(hash);
        const job = renderer.createObject(root, {hash, expression});
        if (!job) inFlight.delete(hash);
        return [hash, !!job];
    }

    Component {
        id: renderer
        Process {
            id: job
            required property string hash
            required property string expression
            readonly property string outputPath: root.latexOutputPath + "/" + hash + ".svg"
            workingDirectory: root.microtexBinaryDir
            command: [root.microtexBinaryDir + "/" + root.microtexBinaryName, "-headless",
                "-input=" + expression, "-output=" + outputPath,
                "-textsize=" + Appearance.font.pixelSize.normal, "-padding=" + root.renderPadding,
                "-foreground=" + Appearance.colors.colOnLayer1, "-maxwidth=0.85"]
            running: true
            onExited: code => {
                if (code === 0) {
                    root.renderedImagePaths[hash] = outputPath;
                    root.renderFinished(hash, outputPath);
                }
            }
            // Includes failure to start when the optional compiler is absent.
            onRunningChanged: if (!running) {
                root.inFlight.delete(hash);
                job.destroy();
            }
        }
    }
}
