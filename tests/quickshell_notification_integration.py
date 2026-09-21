#!/usr/bin/env python3
"""Run under dbus-run-session; exercise the actual notification service."""
import json, os, pathlib, subprocess, tempfile, time
import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
DBusGMainLoop(set_as_default=True)
BASE=pathlib.Path(__file__).resolve().parent
run=pathlib.Path(tempfile.mkdtemp(prefix="notifications-",dir=os.environ.get("QS_AUDIT_OUTPUT")))
runtime=pathlib.Path(tempfile.mkdtemp(prefix="qs-notify-"))
history=run/"history.json"
saved=[dict(notificationId=40,actions=[],appIcon="dialog-information",appName="Saved",body="preserved",image="image://qsimage/73/1",summary="expired image",time=1,urgency="1"),dict(notificationId=41,actions=[],appIcon="dialog-information",appName="Saved",body="keep this",image="file:///tmp/durable-history.png",summary="durable image",time=2,urgency="1")]
history.write_text(json.dumps(saved))
env=os.environ.copy();env.update(QT_QPA_PLATFORM="offscreen",XDG_RUNTIME_DIR=str(runtime),TEST_HISTORY=str(history))
for key in ["DISPLAY","WAYLAND_DISPLAY"]:env.pop(key,None)
fixture=BASE/"notification-fixture/shell.qml"
checks=[]; process=None; log=None; logs=[]
bus=dbus.SessionBus();closed=[];actions=[]
bus.add_signal_receiver(lambda *a:closed.append(tuple(map(int,a))),signal_name="NotificationClosed",dbus_interface="org.freedesktop.Notifications")
bus.add_signal_receiver(lambda *a:actions.append((int(a[0]),str(a[1]))),signal_name="ActionInvoked",dbus_interface="org.freedesktop.Notifications")
def pump():
 ctx=GLib.MainContext.default()
 while ctx.pending():ctx.iteration(False)
def call(*args):
 p=subprocess.run(["qs","-p",str(fixture),"ipc","call","audit",*map(str,args)],env=env,text=True,capture_output=True,timeout=3)
 if p.returncode or "Too many arguments" in p.stdout or "No such function" in p.stdout:raise RuntimeError(p.stdout+p.stderr)
 return p.stdout.strip()
def state():return json.loads(call("status"))
def until(fn,timeout=4):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  pump()
  try:
   value=fn()
   if value:return value
  except (RuntimeError,json.JSONDecodeError):pass
  time.sleep(.025)
 raise AssertionError("timed out")
def check(name,condition):
 assert condition,name
 checks.append(name)
def start():
 global process,log,iface
 path=run/f"shell-{len(logs)}.log";logs.append(path);log=path.open("w")
 process=subprocess.Popen(["qs","-p",str(fixture)],env=env,stdout=log,stderr=subprocess.STDOUT)
 until(lambda:state()["ready"])
 iface=dbus.Interface(bus.get_object("org.freedesktop.Notifications","/org/freedesktop/Notifications"),"org.freedesktop.Notifications")
def stop():
 global process
 if process and process.poll() is None:
  call("stop");process.wait(timeout=4)
 if log:log.close()
 process=None

def notify(summary,timeout=500,hints=None,action_list=None,replace=0):
 return int(iface.Notify("Audit",replace,"dialog-information",summary,"test body",dbus.Array(action_list or [],signature="s"),dbus.Dictionary(hints or {},signature="sv"),timeout))
def record(native):return next(n for n in state()["list"] if n["nativeId"]==native)
try:
 start();s=state()
 check("history records and body preserved",len(s["list"])==2 and s["list"][0]["body"]=="preserved")
 check("expired image sanitized and durable image retained",s["list"][0]["image"]=="" and s["list"][1]["image"]==saved[1]["image"])
 until(lambda:not state()["pending"])
 check("migration persisted without discarding history",len(json.loads(history.read_text()))==2 and json.loads(history.read_text())[0]["image"]=="")
 call("clear");until(lambda:not state()["list"])
 n=notify("early dismissal",450);r=record(n);call("watch");call("dismiss",r["id"])
 until(lambda:state()["watchedLive"]==0 and state()["timersLive"]==0)
 time.sleep(.55);pump()
 check("early dismissal destroys wrapper and timer",not state()["list"] and state()["discarded"]==3)
 check("dismiss reports exactly one close",sum(x[0]==n for x in closed)==1)
 n=notify("hover",220);r=record(n);call("watch");call("hover",r["id"]);time.sleep(.3)
 check("hover stops and destroys timer while retaining popup",record(n)["popup"] and not record(n)["timer"] and state()["timersLive"]==0)
 call("leave",r["id"]);check("hover leave times out popup",not record(n)["popup"])
 call("dismiss",r["id"]);until(lambda:state()["watchedLive"]==0)
 n=notify("sender withdrawal",500);call("watch");iface.CloseNotification(n)
 until(lambda:state()["watchedLive"]==0 and state()["timersLive"]==0)
 check("sender withdrawal cleans wrapper and timer",not state()["list"])
 n=notify("transient timeout",100,{"transient":dbus.Boolean(True)});call("watch")
 until(lambda:not state()["list"] and state()["watchedLive"]==0 and state()["timersLive"]==0)
 check("transient timeout fully cleans objects",True)
 n=notify("normal timeout",100);call("watch")
 until(lambda:not record(n)["popup"] and not record(n)["timer"])
 check("normal timeout retains history without timer",state()["watchedLive"]==1 and state()["timersLive"]==0)
 call("clear")
 native=notify("action",0,action_list=["accept","Accept"]);r=record(native);call("action",r["id"],"accept")
 until(lambda:bool(actions));check("notification action reaches sender",(native,"accept") in actions)
 check("action dismisses record",not state()["list"])
 n=notify("missing action",0);call("action",record(n)["id"],"obsolete");check("obsolete action is safe",not state()["list"])
 # A burst shorter than one flush interval should not serialize every event.
 writes=[];last=history.stat().st_mtime_ns
 for i in range(40):
  notify("burst "+str(i),0)
  now=history.stat().st_mtime_ns
  if now!=last:writes.append(now);last=now
 until(lambda:len(json.loads(history.read_text()))==40)
 check("burst preserved all records",len(json.loads(history.read_text()))==40)
 check("burst persistence coalesced",len(writes)<20)
 call("watch");ids=[n["id"] for n in state()["list"]];call("dismissMany","json:"+json.dumps(ids[:25]));until(lambda:len(json.loads(history.read_text()))==15 and state()["watchedLive"]==15)
 check("bulk dismissal persists once with retained entries",len(json.loads(history.read_text()))==15 and state()["watchedLive"]==15)
 call("clear");until(lambda:state()["watchedLive"]==0 and state()["timersLive"]==0)
 check("clear-all releases every watched object",True)
 notify("reload persistence",0);call("reload")
 until(lambda:state()["ready"] and any(n["summary"]=="reload persistence" and n["nativeId"]==-1 for n in state()["list"]))
 check("immediate hot reload preserves pending notification",True)
 call("clear")
 # Stop before the coalescing timer expires: shutdown must flush pending data.
 notify("shutdown persistence",0);stop()
 check("shutdown flushes pending snapshot",[n["summary"] for n in json.loads(history.read_text())]==["shutdown persistence"])
 start();check("restart restores history without stale native actions",state()["list"][0]["summary"]=="shutdown persistence" and state()["list"][0]["actions"]==[])
 stop()
 history.write_text("corrupted history retained")
 start();native=notify("works with unreadable history",0)
 check("unreadable history does not block new notifications",record(native)["summary"]=="works with unreadable history")
 stop();check("unreadable history is never overwritten",history.read_text()=="corrupted history retained")
 errors=[line for path in logs for line in path.read_text().splitlines() if any(x in line for x in ["ERROR","TypeError","ReferenceError","Binding loop","Cannot assign"])]
 check("no QML errors across lifecycle and restart",not errors)
 result={"status":"passed","checks":checks,"burst_observed_intermediate_writes":len(writes),"logs":[str(p) for p in logs]}
except Exception:
 try: print("failure count",len(state()["list"]),"disk count",len(json.loads(history.read_text())))
 except Exception: pass
 for path in logs:
  print(path);print(path.read_text())
 raise
finally:
 if process and process.poll() is None:
  process.terminate();process.wait(timeout=4)
 if log:log.close()
(run/"result.json").write_text(json.dumps(result,indent=2)+"\n")
print(json.dumps(result,indent=2));print(run)
