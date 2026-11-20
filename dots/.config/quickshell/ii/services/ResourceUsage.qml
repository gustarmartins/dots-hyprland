pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import "resource" as Resource

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

	// Driver reads may wait on hardware; keep them in the asynchronous process.
	// gpu_busy_percent is the graphics pipe, mem_busy_percent the memory controller.
	property real gpuUsage: 0
	property real gpuMemBusy: 0
	property real gpuPower: 0
	property real gpuPowerCap: 1
	property real gpuTempEdge: 0
	property real gpuTempHotspot: 0
	property real gpuTempMem: 0
	property real gpuClock: 0
	property real gpuMemClock: 0
	property real gpuFan: 0

	property real cpuUsage: 0
	property var previousCpuStats
	// Live peak core clock (MHz) — max scaling_cur_freq across all cores at poll
	// time, so it reflects whichever core is boosting highest right now.
	property real cpuMaxClock: 0

	// PSI — Linux Pressure Stall Information (/proc/pressure/*). The "some avgN"
	// field is the share of time at least one task was stalled waiting on the
	// resource. Kernel exposes it as 0-100; stored here /100 to match the
	// *UsedPercentage convention so the Resource widget can bind directly.
	property real cpuPressure: 0
	property real memoryPressure: 0        // some avg10 — the live bar headline
	property real memoryPressure300: 0     // some avg300 — sustained, for the popup
	property real ioPressure: 0

	property string maxAvailableMemoryString: kbToGbString(memoryTotal)
	property string maxAvailableSwapString: kbToGbString(swapTotal)
	property string maxAvailableVramString: bytesToGbString(vramTotal)
	property string maxAvailableGttString: bytesToGbString(gttTotal)
	property string maxAvailableCpuString: "--"


	readonly property int historyLength: Config?.options.resources.historyLength ?? 60
	property list<real> cpuUsageHistory: []
	property list<real> memoryUsageHistory: []
	property list<real> swapUsageHistory: []
	property list<real> gpuUsageHistory: []

	function kbToGbString(kb) {
	    return (kb / (1024 * 1024)).toFixed(1) + " GB";
	}

	function bytesToGbString(bytes) {
	    return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB";
	}
    function appendSample(history, value) {
        if (historyLength <= 0) return [];
        const next = history.slice(Math.max(0, history.length + 1 - historyLength));
        next.push(value);
        return next;
    }

    // Parse each completed read, rather than the previous sample immediately
    // after reload(). FileView loads asynchronously by default.
    Timer {
        interval: Math.max(250, Config.options?.resources?.updateInterval ?? 3000)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            fileMeminfo.reload()
            fileStat.reload()
            filePsiMem.reload()
            filePsiCpu.reload()
            filePsiIo.reload()
            gpuStatsProc.requestSample()
            cpuClockProc.requestSample()
        }
    }

    FileView {
        id: fileMeminfo
        path: "/proc/meminfo"
        onLoaded: {
            const data = text()
            root.memoryTotal = Number(data.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            root.memoryFree = Number(data.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            root.swapTotal = Number(data.match(/SwapTotal: *(\d+)/)?.[1] ?? 0)
            root.swapFree = Number(data.match(/SwapFree: *(\d+)/)?.[1] ?? 0)
            root.memoryUsageHistory = root.appendSample(root.memoryUsageHistory, root.memoryUsedPercentage)
            root.swapUsageHistory = root.appendSample(root.swapUsageHistory, root.swapUsedPercentage)
        }
    }
    FileView {
        id: fileStat
        path: "/proc/stat"
        onLoaded: {
            const cpuLine = text().match(/^cpu\s+(.+)$/m)
            if (!cpuLine) return
            // guest/guest_nice are included in user/nice already; iowait is idle.
            const stats = cpuLine[1].trim().split(/\s+/).slice(0, 8).map(Number)
            const total = stats.reduce((a, b) => a + b, 0)
            const idle = stats[3] + (stats[4] ?? 0)
            if (root.previousCpuStats) {
                const delta = total - root.previousCpuStats.total
                const idleDelta = idle - root.previousCpuStats.idle
                if (delta > 0) {
                    root.cpuUsage = Math.max(0, Math.min(1, 1 - idleDelta / delta))
                    root.cpuUsageHistory = root.appendSample(root.cpuUsageHistory, root.cpuUsage)
                }
            }
            root.previousCpuStats = { total, idle }
        }
    }
    FileView {
        id: filePsiMem
        path: "/proc/pressure/memory"
        onLoaded: {
            const data = text()
            root.memoryPressure = Number(data.match(/some avg10=([\d.]+)/)?.[1] ?? 0) / 100
            root.memoryPressure300 = Number(data.match(/some avg10=.*avg300=([\d.]+)/)?.[1] ?? 0) / 100
        }
    }
    FileView {
        id: filePsiCpu
        path: "/proc/pressure/cpu"
        onLoaded: root.cpuPressure = Number(text().match(/some avg10=([\d.]+)/)?.[1] ?? 0) / 100
    }
    FileView {
        id: filePsiIo
        path: "/proc/pressure/io"
        onLoaded: root.ioPressure = Number(text().match(/some avg10=([\d.]+)/)?.[1] ?? 0) / 100
    }

    // A tick requests one sample. Keep the blocking GPU driver reads independent
    // of CPU clock reads. A slow driver cannot build up a queue of old samples.
    Resource.SensorReader {
        id: gpuStatsProc
        sensor: "gpu"
        onSample: line => {
            const values = line.split(" ").map(Number);
            if (values.length !== 14) return;
            root.vramTotal = values[0] || 1;
            root.vramUsed = values[1];
            root.gttTotal = values[2] || 1;
            root.gttUsed = values[3];
            root.gpuUsage = values[4] / 100;
            root.gpuMemBusy = values[5] / 100;
            root.gpuPower = values[6] / 1000000;
            root.gpuPowerCap = values[7] / 1000000 || 1;
            root.gpuTempEdge = values[8] / 1000;
            root.gpuTempHotspot = values[9] / 1000;
            root.gpuTempMem = values[10] / 1000;
            root.gpuClock = values[11] / 1000000;
            root.gpuMemClock = values[12] / 1000000;
            root.gpuFan = values[13];
            root.gpuUsageHistory = root.appendSample(root.gpuUsageHistory, root.gpuUsage);
        }
    }

    Resource.SensorReader {
        id: cpuClockProc
        sensor: "cpu-clock"
        onSample: line => root.cpuMaxClock = Number(line) / 1000
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
