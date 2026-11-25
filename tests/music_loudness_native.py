#!/usr/bin/env python3
"""Real two-app gain and stereo capture on private PipeWire; no hardware or session manager."""
from pathlib import Path
import resource,threading
import os,subprocess,tempfile,json,time,importlib.machinery,importlib.util,shutil,math
from unittest.mock import patch
REPO=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='app-gain-native-') as td:
 root=Path(td);runtime=root/'runtime';runtime.mkdir(mode=0o700)
 env=dict(os.environ,XDG_RUNTIME_DIR=str(runtime),PIPEWIRE_RUNTIME_DIR=str(runtime),PIPEWIRE_REMOTE='pipewire-0',XDG_CONFIG_HOME=str(root/'config'),XDG_STATE_HOME=str(root/'state'))
 env.pop('PIPEWIRE_CONFIG_NAME',None);env.pop('PIPEWIRE_CONFIG_DIR',None)
 conf=root/'pipewire.conf'
 conf.write_text('''context.properties = { core.daemon = true core.name = pipewire-0 default.clock.rate = 48000 }
context.spa-libs = { audio.convert.* = audioconvert/libspa-audioconvert support.* = support/libspa-support }
context.modules = [
 { name = libpipewire-module-protocol-native }
 { name = libpipewire-module-metadata }
 { name = libpipewire-module-spa-node-factory }
 { name = libpipewire-module-client-node }
 { name = libpipewire-module-access }
 { name = libpipewire-module-adapter }
 { name = libpipewire-module-link-factory }
]
context.objects = [
 { factory = metadata args = { metadata.name = default } }
 { factory = spa-node-factory args = { factory.name = support.node.driver node.name = Dummy-Driver priority.driver = 20000 } }
]
''')
 processes=[]
 def launch(args,name):
  f=(root/(name+'.log')).open('w');p=subprocess.Popen(args,env=env,stdout=f,stderr=subprocess.STDOUT);processes.append((p,f));return p
 def cmd(*args):return subprocess.check_output(args,env=env,text=True,timeout=5)
 def dump():return json.loads(cmd('pw-dump'))
 try:
  launch(['pipewire','-c',str(conf)],'pipewire')
  end=time.monotonic()+5
  while not (runtime/'pipewire-0').exists():
   assert time.monotonic()<end;time.sleep(.05)
  wav=root/'tone.wav'
  subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','sine=frequency=750:sample_rate=48000:duration=120','-af','volume=0.2','-ac','2','-c:a','pcm_f32le',str(wav)],check=True)
  for name in ['firefox-fixture','other-player']:
   binary=root/name;shutil.copy2('/usr/bin/pw-cat',binary)
   launch([str(binary),'--playback','--target','0','--properties',json.dumps({'node.name':name,'application.name':('Eglantine' if name=='other-player' else name),'node.autoconnect':False}),str(wav)],name)
  end=time.monotonic()+5
  while True:
   nodes=[x for x in dump() if x['type'].endswith(':Node') and x.get('info',{}).get('props',{}).get('node.name') in ['firefox-fixture','other-player']]
   if len(nodes)==2:break
   assert time.monotonic()<end;time.sleep(.05)
  for node in nodes:cmd('pw-cli','set-param',str(node['id']),'PortConfig','{ direction = Output mode = dsp format = { mediaType = audio mediaSubtype = raw format = F32 channels = 2 position = [ FL FR ] } }')
  with patch.dict(os.environ,env):
   loader=importlib.machinery.SourceFileLoader('native_gain',str(REPO/'dots/.local/bin/music-loudness'));spec=importlib.util.spec_from_loader(loader.name,loader);m=importlib.util.module_from_spec(spec);loader.exec_module(m)
   m.write(m.CONFIG,{'enabled':True,'selected_app':'exe:firefox-fixture'})
   # The isolation test supplies an effects scope; gains/discovery, capture, reset and audio are real.
   def snapshot(app_id='exe:firefox-fixture',**kw):
    data=m.pw_dump();app=next(a for a in m.playback_apps(data) if a['id']==app_id);node=app['streams'][0]
    return {'preset':'private fixture','ee':{'pid':0,'start':'fixture'},'track':{'key':app_id,'status':'Playing','title':app['name']},'gain':0,'limiter':{},'cookie':next(x['info']['cookie'] for x in data if x['type'].endswith(':Core')),'limiter_serial':node['serial'],'limiter_id':node['id'],'destinations':[],'route_signature':[],'app':app_id,'app_name':app['name'],'streams':app['streams'],'foreign':[],'ceiling':0}
   def measure(app_id):
    with patch.object(m,'inspect',side_effect=lambda **kw:snapshot(app_id)):return m.measure(snapshot(app_id),seconds=2)
   with patch.object(m,'inspect',side_effect=snapshot),patch.object(m,'ensure_worker'):
    base=measure('exe:firefox-fixture');other_before=measure('exe:other-player')
    # Start the Eglantine-labelled stream muted with both channels at zero.
    # Keep it linked during discovery, as it would be during real playback.
    from concurrent.futures import ThreadPoolExecutor
    target='exe:other-player'
    cmd('pw-cli','set-param',str(snapshot(target)['streams'][0]['id']),'Props','{ mute = true channelVolumes = [ 0.0 0.0 ] }')
    # The user-facing meter rejects non-finite peaks; keep digital silence
    # available as a measurement for this startup regression.
    checked_number=m.number
    with patch.object(m,'number',side_effect=lambda v: -math.inf if v=='-inf' else checked_number(v)):
     assert measure(target)['true_peak_dbtp']==-math.inf
    m.write(m.CONFIG,m.config()|{'eden_default':True})
    with ThreadPoolExecutor(max_workers=1) as pool:
     section=pool.submit(measure,target)
     end=time.monotonic()+3
     while not snapshot(target)['streams'][0]['running']:
      assert time.monotonic()<end,'fixture did not start';time.sleep(.03)
     m.update_eden_defaults()
     section.result(timeout=8)
    restored=measure(target)
    delta=restored['true_peak_dbtp']-other_before['true_peak_dbtp']
    assert abs(delta-10)<.15,(restored,other_before)
    assert not m.startup_level_changes(snapshot(target)['streams'][0])
    m.clear_eden_defaults()
    m.write(m.CONFIG,m.config()|{'eden_default':False})
    print('Eglantine startup: initially silent, measured gain',delta,'dB',flush=True)
    other_params=copy_params=snapshot('exe:other-player')['streams'][0]['params'].copy()
    m.adjust(6);assert m.tick();boost=measure('exe:firefox-fixture');other_after=measure('exe:other-player')
    assert abs((boost['true_peak_dbtp']-base['true_peak_dbtp'])-6)<.15,(base,boost)
    assert abs(other_after['true_peak_dbtp']-other_before['true_peak_dbtp'])<.05
    assert snapshot('exe:other-player')['streams'][0]['params']==other_params
    m.adjust(-3);assert abs(m.read(m.SESSION)['db']-3)<.0001
    m.cleanup();reset=measure('exe:firefox-fixture')
    assert abs(reset['true_peak_dbtp']-base['true_peak_dbtp'])<.05,(base,reset)
    assert m.GAIN_KEY not in snapshot()['streams'][0]['params']
    # Exercise the actual automatic matcher and its full eight-second meter.
    m.set_auto_match(True)
    cpu_before=resource.getrusage(resource.RUSAGE_SELF);children_before=resource.getrusage(resource.RUSAGE_CHILDREN);start=time.monotonic()
    automatic=m.match(automatic=True)
    cpu_after=resource.getrusage(resource.RUSAGE_SELF);children_after=resource.getrusage(resource.RUSAGE_CHILDREN)
    auto_wall=time.monotonic()-start
    auto_cpu=sum(getattr(after,k)-getattr(before,k) for before,after in [(cpu_before,cpu_after),(children_before,children_after)] for k in ['ru_utime','ru_stime'])
    assert automatic['db']==1,automatic
    auto_level=measure('exe:firefox-fixture');auto_other=measure('exe:other-player')
    assert abs(auto_level['true_peak_dbtp']-base['true_peak_dbtp']-1)<.15,(base,auto_level)
    assert abs(auto_other['true_peak_dbtp']-other_before['true_peak_dbtp'])<.05
    # A target below the measured level must attenuate, not keep adding gain.
    m.write(m.CONFIG,m.config()|{'target_lufs':auto_level['lufs']-6})
    automatic=m.match(automatic=True);assert automatic['db']==0,automatic
    m.set_auto_match(False);m.cleanup()
    # A running background stream can output only zeroes. Capture it alongside
    # the measured section; real audio in either channel must still block a match.
    other_node=snapshot('exe:other-player')['streams'][0]
    def mixed_snapshot(**kw):
     s=snapshot();s['foreign']=['other-player'];s['foreign_nodes']=[{'id':other_node['id'],'serial':other_node['serial'],'kind':'Stream/Output/Audio'}];return s
    cmd('pw-cli','set-param',str(other_node['id']),'Props','{ mute = true }')
    with patch.object(m,'inspect',side_effect=mixed_snapshot):
     silent=m.measure(mixed_snapshot(),seconds=2,allow_silent=True)
     assert silent['silent_background']==mixed_snapshot()['foreign_nodes']
     cmd('pw-cli','set-param',str(other_node['id']),'Props','{ mute = false }')
     try:m.measure(mixed_snapshot(),seconds=2,allow_silent=True)
     except RuntimeError as e:assert 'Pause other audio' in str(e),e
     else:raise AssertionError('Audible background audio was accepted')
     cmd('pw-cli','set-param',str(other_node['id']),'Props','{ mute = true }')
     timers=[threading.Timer(.6,lambda:cmd('pw-cli','set-param',str(other_node['id']),'Props','{ mute = false }')),
             threading.Timer(1.1,lambda:cmd('pw-cli','set-param',str(other_node['id']),'Props','{ mute = true }'))]
     for timer in timers:timer.start()
     try:
      try:m.measure(mixed_snapshot(),seconds=2,allow_silent=True)
      except RuntimeError as e:assert 'Pause other audio' in str(e),e
      else:raise AssertionError('A brief background sound inside the section was accepted')
     finally:
      for timer in timers:timer.join()
   assert not any(x.get('info',{}).get('props',{}).get('media.class') in ('Audio/Sink','Audio/Source') for x in dump())
   result={'passed':True,'selected_app_delta_db':round(boost['true_peak_dbtp']-base['true_peak_dbtp'],3),'other_app_delta_db':round(other_after['true_peak_dbtp']-other_before['true_peak_dbtp'],3),'reset_delta_db':round(reset['true_peak_dbtp']-base['true_peak_dbtp'],3),'other_app_params_unchanged':True,'real_pipewire_stream_gain_and_capture':True,'hardware_or_microphone_nodes':False,'scope':'Native stream gain and isolation, not actual Firefox or EasyEffects limiting/listening acceptance'}
   result.update(eglantine_unmuted_delta_db=round(delta,3),auto_match_gain_db=1,auto_attenuation_db=-1,auto_other_app_delta_db=round(auto_other['true_peak_dbtp']-other_before['true_peak_dbtp'],3),auto_measurement_wall_seconds=round(auto_wall,3),auto_measurement_cpu_seconds=round(auto_cpu,3),auto_meter_percent_of_one_core_at_30s=round(auto_cpu/30*100,3),silent_background_allowed=True,audible_background_rejected=True,brief_background_sound_rejected=True)
   print(json.dumps(result,indent=2))
   if os.environ.get('MUSIC_LOUDNESS_NATIVE_RESULT'):Path(os.environ['MUSIC_LOUDNESS_NATIVE_RESULT']).write_text(json.dumps(result,indent=2)+'\n')
 except Exception:
  for p in root.glob('*.log'):print(p.name,p.read_text()[-4000:])
  raise
 finally:
  for p,f in reversed(processes):
   if p.poll() is None:p.terminate()
   try:p.wait(timeout=3)
   except subprocess.TimeoutExpired:p.kill();p.wait()
   f.close()
