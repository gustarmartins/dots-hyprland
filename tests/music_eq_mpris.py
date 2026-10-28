#!/usr/bin/env python3
"""Run with dbus-run-session: real Playerctl events, fake Spotify and EE socket."""
import json,os,socket,subprocess,tempfile,threading,time
from pathlib import Path
from gi.repository import Gio,GLib
repo=Path(__file__).resolve().parents[1]
xml='''<node><interface name="org.mpris.MediaPlayer2"><property name="Identity" type="s" access="read"/><property name="CanQuit" type="b" access="read"/><property name="CanRaise" type="b" access="read"/><property name="HasTrackList" type="b" access="read"/><property name="SupportedUriSchemes" type="as" access="read"/><property name="SupportedMimeTypes" type="as" access="read"/></interface><interface name="org.mpris.MediaPlayer2.Player"><property name="PlaybackStatus" type="s" access="read"/><property name="Metadata" type="a{sv}" access="read"/><property name="CanControl" type="b" access="read"/><property name="Position" type="x" access="read"/><property name="Rate" type="d" access="read"/><property name="Volume" type="d" access="read"/></interface></node>'''
with tempfile.TemporaryDirectory(prefix='music-eq-mpris-') as tmp:
 root=Path(tmp);runtime=root/'run';runtime.mkdir()
 config=root/'config';data=root/'data';state=root/'state'
 for d in [config/'music-eq',data/'easyeffects/output',state]:d.mkdir(parents=True)
 for name,gain in [('base',-2),('song',-5),('manual',-2)]:
  (data/'easyeffects/output'/f'{name}.json').write_text(json.dumps({'output':{'equalizer#0':{'input-gain':gain},'limiter#0':{'output-gain':0}}}))
 cfg=dict(spotify=True,jukebox=True,artists=True,genres=True,tracks=[dict(artist='Fixture Artist',title='First',preset='song')],artist_rules={},genre_rules={},fallback='base',route='')
 (config/'music-eq/config.json').write_text(json.dumps(cfg))
 current={'preset':'base','eq':'-2','gain':'-0.85'};loads=[];stop=threading.Event()
 sock=socket.socket(socket.AF_UNIX);sock.bind(str(runtime/'EasyEffectsServer'));sock.listen();sock.settimeout(.1)
 def serve():
  while not stop.is_set():
   try:c,_=sock.accept()
   except socket.timeout:continue
   with c:
    raw=b''
    while x:=c.recv(4096):raw+=x
    command=raw.decode().strip();answer=''
    if command=='get_last_loaded_preset:output':answer=current['preset']
    elif command=='get_global_bypass':answer='2'
    elif command=='get_property:output:limiter:0:outputGain':answer=current['gain']
    elif command=='get_property:output:equalizer:0:inputGain':answer=current['eq']
    elif command.startswith('load_preset:output:'):
     current['preset']=command.split(':')[-1];current['eq']='-5' if current['preset']=='song' else '-2';loads.append(current['preset'])
    elif command.startswith('set_property:output:limiter:0:outputGain:'):current['gain']=command.split(':')[-1]
    elif command.startswith('set_property:output:equalizer:0:inputGain:'):current['eq']=command.split(':')[-1]
    c.sendall(answer.encode())
 thread=threading.Thread(target=serve,daemon=True);thread.start()
 bus=Gio.bus_get_sync(Gio.BusType.SESSION,None)
 bus.call_sync('org.freedesktop.DBus','/org/freedesktop/DBus','org.freedesktop.DBus','RequestName',GLib.Variant('(su)',('org.mpris.MediaPlayer2.spotify',0)),None,0,1000,None)
 player={'title':'First','status':'Playing'}
 def metadata():return {'xesam:artist':GLib.Variant('as',['Fixture Artist']),'xesam:title':GLib.Variant('s',player['title']),'xesam:url':GLib.Variant('s','spotify:track:'+player['title'])}
 def get_prop(conn,sender,path,iface,name):
  if name=='Metadata':return GLib.Variant('a{sv}',metadata())
  if name=='PlaybackStatus':return GLib.Variant('s',player['status'])
  if name=='Identity':return GLib.Variant('s','Spotify fixture')
  if name=='Position':return GLib.Variant('x',0)
  if name in ('Volume','Rate'):return GLib.Variant('d',1)
  if name.startswith('Supported'):return GLib.Variant('as',[])
  return GLib.Variant('b',True)
 for iface in Gio.DBusNodeInfo.new_for_xml(xml).interfaces:bus.register_object('/org/mpris/MediaPlayer2',iface,None,get_prop,None)
 env=dict(os.environ,XDG_CONFIG_HOME=str(config),XDG_DATA_HOME=str(data),XDG_STATE_HOME=str(state),XDG_RUNTIME_DIR=str(runtime))
 log=(root/'log').open('w+')
 process=subprocess.Popen([str(repo/'dots/.local/bin/music-eq'),'run'],env=env,stdout=log,stderr=log)
 def wait_for(check):
  deadline=time.monotonic()+8
  while time.monotonic()<deadline:
   while GLib.MainContext.default().iteration(False):pass
   if check():return
   time.sleep(.02)
  log.seek(0);raise AssertionError(log.read()+str(current)+str(loads))
 def emit():bus.emit_signal(None,'/org/mpris/MediaPlayer2','org.freedesktop.DBus.Properties','PropertiesChanged',GLib.Variant('(sa{sv}as)',('org.mpris.MediaPlayer2.Player',{'Metadata':GLib.Variant('a{sv}',metadata()),'PlaybackStatus':GLib.Variant('s',player['status'])},[])))
 try:
  wait_for(lambda:current['preset']=='song')
  assert current['gain']=='-0.85'
  player['title']='Unmapped';emit();wait_for(lambda:current['preset']=='base')
  player['title']='First';emit();wait_for(lambda:loads.count('song')==2)
  def status():
   try:return json.loads((state/'music-eq/state.json').read_text())
   except (FileNotFoundError,json.JSONDecodeError):return {}
  player['status']='Paused';emit();wait_for(lambda:status().get('message')=='Waiting for playback')
  assert current['preset']=='song' and loads.count('base')==1
  # The native GUI can change a preset while playback is paused.
  current['preset']='manual';emit();wait_for(lambda:status().get('manual_override'))
  player['status']='Playing';emit();wait_for(lambda:status().get('message')=='Manual preset held until next song')
  assert current['preset']=='manual'
  player['status']='Paused';emit();wait_for(lambda:'pause' in status().get('message',''))
  process.terminate();wait_for(lambda:process.poll() is not None)
  assert current['preset']=='manual'
  process=subprocess.Popen([str(repo/'dots/.local/bin/music-eq'),'run'],env=env,stdout=log,stderr=log)
  wait_for(lambda:status().get('pid')==process.pid)
  player['status']='Playing';emit();wait_for(lambda:status().get('message')=='Manual preset held until next song')
  assert current['preset']=='manual'
  player['title']='Next';emit();wait_for(lambda:current['preset']=='base')
  wait_for(lambda:status().get('manual_override') is False)
  assert current['gain']=='-0.85'
  print('PASS: real MPRIS song selection, paused manual selection, resume, daemon restart, next-song expiry, output gain')
 finally:
  process.terminate()
  wait_for(lambda:process.poll() is not None)
  stop.set();thread.join();sock.close();log.close()
