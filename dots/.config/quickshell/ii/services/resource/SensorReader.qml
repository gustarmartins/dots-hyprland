pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io

Process {
    id: reader
    required property string sensor
    property bool awaitingReply: false
    signal sample(string line)
    command: ["bash", Quickshell.shellPath("scripts/resource-sensors.sh"), sensor]
    stdinEnabled: true
    function requestSample() {
        if (!running) {
            running = true;
        } else if (!awaitingReply) {
            awaitingReply = true;
            write("\n");
        }
    }
    onStarted: requestSample()
    onExited: awaitingReply = false
    stdout: SplitParser {
        onRead: line => {
            reader.awaitingReply = false;
            reader.sample(line);
        }
    }
}
