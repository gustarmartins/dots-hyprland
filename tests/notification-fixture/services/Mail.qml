pragma Singleton
import Quickshell
Singleton { property var config: ({enabled:false, accounts:[]}); readonly property bool enabled: config.enabled; property var state: ({connected:true}); function openMessage(data) {} }
