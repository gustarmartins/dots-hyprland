pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

DelegateChooser {
    id: root
    property bool editMode: false
    required property real baseCellWidth
    required property real baseCellHeight
    required property real spacing
    required property int startingIndex
    signal openAudioOutputDialog()
    signal openAudioInputDialog()
    signal openBluetoothDialog()
    signal openNightLightDialog()
    signal openWifiDialog()

    property int columns: 7
    signal tileResized(int index, int width, int height)
    signal tileMoved(int index, real x, real y)
    role: "type"

    DelegateChoice { roleValue: "gpuMemory"; AndroidGpuMemoryToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "memoryCompact"; AndroidMemoryCompactToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "dropCaches"; AndroidMemoryDropCachesToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "zramWriteback"; AndroidZramWritebackToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "zramRecompress"; AndroidZramRecompressToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "zramAlgo"; AndroidZramAlgoToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "focusMode"; AndroidFocusModeToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "memoryMode"; AndroidMemoryModeToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "buildCache"; AndroidBuildCacheToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "antiFlashbang"; AndroidAntiFlashbangToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
        onOpenMenu: {
            root.openNightLightDialog()
        }
    } }

    DelegateChoice { roleValue: "audio"; AndroidAudioToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
        onOpenMenu: {
            root.openAudioOutputDialog()
        }
    } }

    DelegateChoice { roleValue: "bluetooth"; AndroidBluetoothToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
        onOpenMenu: {
            root.openBluetoothDialog()
        }
    } }

    DelegateChoice { roleValue: "cloudflareWarp"; AndroidCloudflareWarpToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "colorPicker"; AndroidColorPickerToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "darkMode"; AndroidDarkModeToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "easyEffects"; AndroidEasyEffectsToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "gameMode"; AndroidGameModeToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "tearing"; AndroidTearingToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "directScanout"; AndroidDirectScanoutToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "vrr"; AndroidVrrToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "lsfg"; AndroidLsfgToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "tripleBuffer"; AndroidTripleBufferToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "idleInhibitor"; AndroidIdleInhibitorToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "mic"; AndroidMicToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
        onOpenMenu: {
            root.openAudioInputDialog()
        }
    } }

    DelegateChoice { roleValue: "musicRecognition"; AndroidMusicRecognition {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "network"; AndroidNetworkToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
        onOpenMenu: {
            root.openWifiDialog()
        }
    } }

    DelegateChoice { roleValue: "nightLight"; AndroidNightLightToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
        onOpenMenu: {
            root.openNightLightDialog()
        }
    } }

    DelegateChoice { roleValue: "notifications"; AndroidNotificationToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "onScreenKeyboard"; AndroidOnScreenKeyboardToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "powerProfile"; AndroidPowerProfileToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }

    DelegateChoice { roleValue: "screenSnip"; AndroidScreenSnipToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex ?? (root.startingIndex + index)
        buttonData: modelData
        editMode: root.editMode
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        cellRows: modelData.height ?? 1
        gridColumns: root.columns
        x: (modelData.gridColumn ?? 0) * (root.baseCellWidth + root.spacing)
        y: (modelData.gridRow ?? 0) * (root.baseCellHeight + root.spacing)
        onTileResized: (index, width, height) => root.tileResized(index, width, height)
        onTileMoved: (index, x, y) => root.tileMoved(index, x, y)
    } }
}
