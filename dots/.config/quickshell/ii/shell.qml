//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "services"
import "panelFamilies"

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root
    // Singleton destruction runs after the engine interrupts JavaScript.
    // Flush while the root is still alive, including during hot reload.
    Component.onDestruction: Notifications.flushSave(true)

    // Stuff for every panel family
    ReloadPopup {}
    SessionBusRecovery {
        deferRestart: GlobalStates.screenLocked
    }
    Binding {
        target: ShellControl
        property: "locked"
        value: GlobalStates.screenLocked
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.start()
        Wallpapers.load()
        WallpaperDiscovery.rotationOwner = true
        Updates.load()
        CryoDSession.start()
        CryoDConsent.start()
    }


    // Panel families
    property list<string> families: ["ii", "waffle"]
    function cyclePanelFamily() {
        if (GlobalStates.screenLocked) {
            console.warn("[ShellRoot] ignoring panelFamily cycle while screen is locked");
            return;
        }
        const currentIndex = families.indexOf(Config.options.panelFamily)
        const nextIndex = (currentIndex + 1) % families.length
        Config.options.panelFamily = families[nextIndex]
    }

    component PanelFamilyLoader: LazyLoader {
        required property string identifier
        property bool extraCondition: true
        active: Config.ready && Config.options.panelFamily === identifier && extraCondition
    }
    
    PanelFamilyLoader {
        identifier: "ii"
        component: IllogicalImpulseFamily {}
    }

    PanelFamilyLoader {
        identifier: "waffle"
        component: WaffleFamily {}
    }


    // Keep the process and its StatusNotifierWatcher alive across UI reloads.
    IpcHandler {
        target: "shellControl"
        function reload(): void { ShellControl.requestReload() }
        function restartForUpdate(): void { ShellControl.requestRestartForUpdate() }
        function status(): string { return ShellControl.statusJson() }
    }

    // Shortcuts
    IpcHandler {
        target: "panelFamily"

        function cycle(): void {
            root.cyclePanelFamily()
        }
    }

    GlobalShortcut {
        name: "panelFamilyCycle"
        description: "Cycles panel family"

        onPressed: root.cyclePanelFamily()
    }
}
