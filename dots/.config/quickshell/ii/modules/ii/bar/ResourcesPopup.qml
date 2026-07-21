import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    // Helper function to format KB to GB
    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    // Helper function to format Bytes to GB
    function formatBytes(bytes) {
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB";
    }

    Row {
        anchors.centerIn: parent
        spacing: 12

        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "developer_board"
                label: "GPU"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "bolt"
                    label: Translation.tr("Load:")
                    value: `${Math.round(ResourceUsage.gpuUsage * 100)}%`
                }
                StyledPopupValueRow {
                    icon: "database"
                    label: Translation.tr("Mem ctrl:")
                    value: `${Math.round(ResourceUsage.gpuMemBusy * 100)}%`
                }
                StyledPopupValueRow {
                    icon: "speed"
                    label: Translation.tr("Clock:")
                    value: `${Math.round(ResourceUsage.gpuClock)} / ${Math.round(ResourceUsage.gpuMemClock)} MHz`
                }
                StyledPopupValueRow {
                    icon: "power"
                    label: Translation.tr("Power:")
                    value: `${ResourceUsage.gpuPower.toFixed(1)} / ${Math.round(ResourceUsage.gpuPowerCap)} W`
                }
                StyledPopupValueRow {
                    icon: "thermostat"
                    label: Translation.tr("Temp:")
                    value: `${Math.round(ResourceUsage.gpuTempEdge)}° edge / ${Math.round(ResourceUsage.gpuTempHotspot)}° hot`
                }
                StyledPopupValueRow {
                    visible: ResourceUsage.gpuFan > 0
                    icon: "mode_fan"
                    label: Translation.tr("Fan:")
                    value: `${Math.round(ResourceUsage.gpuFan)} RPM`
                }
            }
        }

        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "video_settings"
                label: "VRAM"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "clock_loader_60"
                    label: Translation.tr("Used:")
                    value: root.formatBytes(ResourceUsage.vramUsed)
                }
                StyledPopupValueRow {
                    icon: "cloud_upload"
                    label: Translation.tr("GTT:")
                    value: root.formatBytes(ResourceUsage.gttUsed)
                }
                StyledPopupValueRow {
                    icon: "empty_dashboard"
                    label: Translation.tr("Total:")
                    value: root.formatBytes(ResourceUsage.vramTotal)
                }
            }
        }

        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "memory"
                label: "RAM"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "clock_loader_60"
                    label: Translation.tr("Used:")
                    value: root.formatKB(ResourceUsage.memoryUsed)
                }
                StyledPopupValueRow {
                    icon: "check_circle"
                    label: Translation.tr("Free:")
                    value: root.formatKB(ResourceUsage.memoryFree)
                }
                StyledPopupValueRow {
                    icon: "empty_dashboard"
                    label: Translation.tr("Total:")
                    value: root.formatKB(ResourceUsage.memoryTotal)
                }
            }
        }

        Column {
            visible: ResourceUsage.swapTotal > 0
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "swap_horiz"
                label: "Swap"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "clock_loader_60"
                    label: Translation.tr("Used:")
                    value: root.formatKB(ResourceUsage.swapUsed)
                }
                StyledPopupValueRow {
                    icon: "check_circle"
                    label: Translation.tr("Free:")
                    value: root.formatKB(ResourceUsage.swapFree)
                }
                StyledPopupValueRow {
                    icon: "empty_dashboard"
                    label: Translation.tr("Total:")
                    value: root.formatKB(ResourceUsage.swapTotal)
                }
            }
        }

        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "planner_review"
                label: "CPU"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "bolt"
                    label: Translation.tr("Load:")
                    value: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
                }
                StyledPopupValueRow {
                    icon: "speed"
                    label: Translation.tr("Peak clock:")
                    value: ResourceUsage.cpuMaxClock >= 1000
                        ? `${(ResourceUsage.cpuMaxClock / 1000).toFixed(2)} GHz`
                        : `${Math.round(ResourceUsage.cpuMaxClock)} MHz`
                }
            }
        }

        Column {
            anchors.top: parent.top
            spacing: 8

            StyledPopupHeaderRow {
                icon: "monitor_heart"
                label: "Pressure"
            }
            Column {
                spacing: 4
                StyledPopupValueRow {
                    icon: "memory"
                    label: Translation.tr("RAM (10s):")
                    value: `${(ResourceUsage.memoryPressure * 100).toFixed(1)}%`
                }
                StyledPopupValueRow {
                    icon: "history"
                    label: Translation.tr("RAM (5m):")
                    value: `${(ResourceUsage.memoryPressure300 * 100).toFixed(1)}%`
                }
                StyledPopupValueRow {
                    icon: "planner_review"
                    label: Translation.tr("CPU:")
                    value: `${(ResourceUsage.cpuPressure * 100).toFixed(1)}%`
                }
                StyledPopupValueRow {
                    icon: "storage"
                    label: Translation.tr("I/O:")
                    value: `${(ResourceUsage.ioPressure * 100).toFixed(1)}%`
                }
            }
        }
    }
}
