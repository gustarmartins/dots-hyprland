#!/usr/bin/env python3
"""Exercise the real QML resource sampler against disposable sysfs nodes on a private bus."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

assert os.environ.get('DBUS_SESSION_BUS_ADDRESS') and f'/run/user/{os.getuid()}/bus' not in os.environ['DBUS_SESSION_BUS_ADDRESS']
repo=Path(__file__).resolve().parents[1]
out=Path(tempfile.mkdtemp(prefix='qs-sampler-'))
shell=out/'config/quickshell/ii'
source=repo/'dots/.config/quickshell/ii'
for name in ('services','scripts','modules/common'):
    (shell/name).mkdir(parents=True)
shutil.copy2(source/'services/ResourceUsage.qml',shell/'services')
shutil.copy2(source/'scripts/resource-sensors.sh',shell/'scripts')
(shell/'modules/common/Config.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    readonly property QtObject options: QtObject {
        readonly property QtObject resources: QtObject {
            property int updateInterval: 250
            property int historyLength: 4
        }
    }
}''')
for name in ('run','home','data','cache','state','drm/card0/device/hwmon/hwmon1','drm/card2/device','cpu/cpu0/cpufreq','cpu/cpu3/cpufreq'):
    (out/name).mkdir(parents=True,mode=0o700,exist_ok=True)
helper=shell/'scripts/resource-sensors.sh'
helper.write_text(helper.read_text().replace('/sys/class/drm',str(out/'drm')).replace('/sys/devices/system/cpu',str(out/'cpu')))
gpu=out/'drm/card0/device'
(out/'drm/card2/device/vendor').write_text('0x8086\n')
(gpu/'vendor').write_text('0x1002\n')
(gpu/'boot_vga').write_text('1\n')
for name,v in {'mem_info_vram_total':8000,'mem_info_vram_used':2000,'gpu_busy_percent':63,'mem_busy_percent':18,'hwmon/hwmon1/temp1_input':41000}.items():
    (gpu/name).write_text(f'{v}\n')
(out/'cpu/cpu0/cpufreq/scaling_cur_freq').write_text('2300000\n')
clock=out/'cpu/cpu3/cpufreq/scaling_cur_freq'
clock.write_text('3700000\n')
env=dict(os.environ, HOME=str(out/'home'),XDG_CONFIG_HOME=str(out/'config'),XDG_DATA_HOME=str(out/'data'),XDG_CACHE_HOME=str(out/'cache'),
         XDG_STATE_HOME=str(out/'state'),XDG_RUNTIME_DIR=str(out/'run'),QT_QPA_PLATFORM='offscreen',WAYLAND_DISPLAY='',HYPRLAND_INSTANCE_SIGNATURE='')
entry=shell/'sample-test.qml'
entry.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
ShellRoot {
    IpcHandler {
        target:"fixture"
        function state():string {
            return JSON.stringify({clock:ResourceUsage.cpuMaxClock, gpu:ResourceUsage.gpuUsage,
                memory:ResourceUsage.vramUsedPercentage, temp:ResourceUsage.gpuTempEdge, missing:ResourceUsage.gpuFan,
                history:ResourceUsage.gpuUsageHistory, cpuHistory:ResourceUsage.cpuUsageHistory.length});
        }
        function shrink():void {Config.options.resources.historyLength=2}
    }
}''')
def call(fn):
    return subprocess.check_output(['/usr/bin/qs','-p',str(entry),'ipc','call','fixture',fn],env=env,text=True,stderr=subprocess.DEVNULL,timeout=2).strip()
def wait(fn):
    end=time.monotonic()+8
    while time.monotonic()<end:
        try:
            state=json.loads(call('state'))
            if fn(state): return state
        except (subprocess.SubprocessError,ValueError): pass
        time.sleep(.06)
    raise AssertionError(out)
def sensor_pids(parent):
    pids=Path(f'/proc/{parent}/task/{parent}/children').read_text().split()
    return {args[-1].decode():int(p) for p in pids if (procpath:=Path('/proc',p,'cmdline')).exists()
            and (args:=procpath.read_bytes().rstrip(b'\0').split(b'\0')) and str(helper).encode() in args}
with (out/'shell.log').open('w') as log:
    proc=subprocess.Popen(['/usr/bin/qs','-p',str(entry)],env=env,stdout=log,stderr=subprocess.STDOUT)
    try:
        initial=wait(lambda v:v['clock']==3700 and len(v['history'])==4)
        assert initial['gpu']==.63 and initial['memory']==.25 and initial['temp']==41 and initial['missing']==0,initial
        first=sensor_pids(proc.pid)
        assert set(first)=={'gpu','cpu-clock'},first
        call('shrink')
        wait(lambda v:len(v['history'])==v['cpuHistory']==2)
        busy=gpu/'gpu_busy_percent'
        busy.unlink();os.mkfifo(busy)
        time.sleep(.55)
        clock.write_text('4123000\n')
        wait(lambda v:v['clock']==4123 and v['gpu']==.63)
        # The CPU reader and IPC stayed responsive while the GPU reader waited.
        fd=os.open(busy,os.O_WRONLY|os.O_NONBLOCK)
        busy.unlink();busy.write_text('81\n')
        os.write(fd,b'81\n');os.close(fd)
        wait(lambda v:v['history']==[.81,.81])
        assert sensor_pids(proc.pid)==first,'A sensor spawned per tick'
        os.kill(first['gpu'],signal.SIGTERM)
        busy.write_text('43\n')
        final=wait(lambda v:v['gpu']==.43)
        last=sensor_pids(proc.pid)
        assert last['cpu-clock']==first['cpu-clock'] and last['gpu']!=first['gpu']
        print(json.dumps({'status':'passed','initial':initial,'final':final,'readers_before':first,'readers_after_one_failure':last,'output':str(out)}))
    finally:
        proc.terminate()
        try:proc.wait(timeout=4)
        except subprocess.TimeoutExpired:proc.kill();proc.wait()
