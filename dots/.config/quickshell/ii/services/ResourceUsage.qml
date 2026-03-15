pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, and CPU usage.
 */
Singleton {
    id: root
	property real memoryTotal: 1
	property real memoryFree: 0
	property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
	property real swapFree: 0
	property real swapUsed: swapTotal - swapFree
	property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
	property real vramTotal: 1
	property real vramUsed: 0
	property real vramUsedPercentage: vramUsed / vramTotal
	property real gttTotal: 1
	property real gttUsed: 0
	property real gttUsedPercentage: gttUsed / gttTotal
	property real cpuUsage: 0
	property var previousCpuStats

	property string maxAvailableMemoryString: kbToGbString(memoryTotal)
	property string maxAvailableSwapString: kbToGbString(swapTotal)
	property string maxAvailableVramString: bytesToGbString(vramTotal)
	property string maxAvailableGttString: bytesToGbString(gttTotal)
	property string maxAvailableCpuString: "--"


	readonly property int historyLength: Config?.options.resources.historyLength ?? 60
	property list<real> cpuUsageHistory: []
	property list<real> memoryUsageHistory: []
	property list<real> swapUsageHistory: []

	function kbToGbString(kb) {
	    return (kb / (1024 * 1024)).toFixed(1) + " GB";
	}

	function bytesToGbString(bytes) {
	    return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB";
	}
    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) {
            memoryUsageHistory.shift()
        }
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) {
            swapUsageHistory.shift()
        }
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) {
            cpuUsageHistory.shift()
        }
    }
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
    }

	Timer {
		interval: 1
        running: true 
        repeat: true
		onTriggered: {
            // Reload files
            fileMeminfo.reload()
            fileStat.reload()
            gpuStatsProc.running = true

            // Parse memory and swap usage
            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
            swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

            const textStat = fileStat.text()
            const cpuLine = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle = stats[3]

                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff = idle - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }

                previousCpuStats = { total, idle }
            }

            root.updateHistories()
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
	}

	FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }

    Process {
        id: gpuStatsProc
        command: ["bash", "-c", "cat /sys/class/drm/card1/device/mem_info_{vram_total,vram_used,gtt_total,gtt_used}"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => l.length > 0)
                if (lines.length >= 4) {
                    root.vramTotal = Number(lines[0])
                    root.vramUsed = Number(lines[1])
                    root.gttTotal = Number(lines[2])
                    root.gttUsed = Number(lines[3])
                }
            }
        }
    }

    Process {
        id: findCpuMaxFreqProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }
}
