import copy,contextlib,importlib.machinery,importlib.util,json,pathlib,tempfile,unittest
from unittest.mock import patch
loader=importlib.machinery.SourceFileLoader('music_loudness',str(pathlib.Path(__file__).resolve().parents[1]/'dots/.local/bin/music-loudness'))
spec=importlib.util.spec_from_loader(loader.name,loader);m=importlib.util.module_from_spec(spec);loader.exec_module(m)

class AppGainTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.tmp.name)
  self.stack=contextlib.ExitStack()
  for name,value in [('RUNTIME',self.root),('SESSION',self.root/'session.json'),('STORE',self.root/'state'),('CONFIG',self.root/'config.json')]:self.stack.enter_context(patch.object(m,name,value))
  m.write(m.CONFIG,{'enabled':True,'selected_app':'exe:firefox'})
  self.stream={'id':8,'serial':'108','channels':2,'process':{'pid':20,'start':'2','exe':'firefox'},'params':{},'running':True,'supported':True}
  self.other={'id':9,'serial':'109','channels':2,'process':{'pid':30,'start':'3','exe':'eden'},'params':{'eden_boost_gain:Mult':4},'running':True,'supported':True}
  self.snapshot={'preset':'music','ee':{'pid':1,'start':'100','exe':'easyeffects'},'track':{'key':'song1','status':'Playing','title':'Song'},'gain':2.82,'ceiling':-1.85,'limiter':{'inputGain':'2.82'},'cookie':42,'limiter_serial':'30','limiter_id':3,'destinations':['50'],'route_signature':[['108','30']],'streams':[self.stream],'app':'exe:firefox','app_name':'Firefox','foreign':[]}
  self.writes=[]
  self.stack.enter_context(patch.object(m,'inspect',side_effect=lambda **kw:copy.deepcopy(self.snapshot)))
  self.stack.enter_context(patch.object(m,'ensure_worker'))
  self.stack.enter_context(patch.object(m,'current_stream',side_effect=self.current))
  self.stack.enter_context(patch.object(m,'set_stream',side_effect=self.set_stream))
  self.stack.enter_context(patch.object(m,'exchange',side_effect=AssertionError('Must never change EasyEffects')))
 def tearDown(self):self.stack.close();self.tmp.cleanup()
 def current(self,ident,cookie):
  if cookie!=self.snapshot['cookie']:return None
  return next((x for x in [*self.snapshot['streams'],self.other] if m.stream_identity(x)==m.stream_identity(ident)),None)
 def set_stream(self,ident,cookie,params):
  s=self.current(ident,cookie)
  if s is None:raise RuntimeError('stream gone')
  self.assertNotEqual(s['serial'],self.other['serial']);self.writes.append((s['serial'],params))
  if params[0]==m.GRAPH_KEY:
   if params[1]:s['params'][m.GAIN_KEY]=json.loads(params[1])['nodes'][0]['control']['Mult']
   else:s['params'].pop(m.GAIN_KEY,None)
  else:s['params'][m.GAIN_KEY]=params[1]
 def test_steps_accumulate_and_reset_without_touching_other_app_or_limiter(self):
  m.adjust(1);m.adjust(1);m.adjust(-.5)
  self.assertAlmostEqual(self.stream['params'][m.GAIN_KEY],10**(1.5/20));self.assertEqual(m.read(m.SESSION)['db'],1.5)
  self.assertTrue(m.tick());m.cleanup();self.assertNotIn(m.GAIN_KEY,self.stream['params'])
  self.assertEqual(self.other['params'],{'eden_boost_gain:Mult':4});self.assertEqual(self.snapshot['gain'],2.82)
 def test_eden_default_uses_existing_manual_gain_slot_once(self):
  self.stream['process']['exe']='eglantine'
  apps=[{'id':'exe:eglantine','name':'Eden','streams':[self.stream]}]
  core=[{'type':'PipeWire:Interface:Core','info':{'cookie':42}}]
  m.write(m.CONFIG,{'enabled':True,'eden_default':True})
  with patch.object(m,'pw_dump',return_value=core),patch.object(m,'playback_apps',return_value=apps):
   m.update_eden_defaults();m.update_eden_defaults()
   self.assertEqual(len(self.writes),1);self.assertEqual(m.current_db({},self.snapshot),10)
   m.adjust(-2);self.assertEqual(m.current_db(m.read(m.SESSION),self.snapshot),8)
   m.cleanup();m.update_eden_defaults();self.assertNotIn(m.GAIN_KEY,self.stream['params'])
   self.stream['serial']='fresh';m.update_eden_defaults();self.assertEqual(m.current_db({},self.snapshot),10)
   m.clear_eden_defaults();self.assertNotIn(m.GAIN_KEY,self.stream['params'])
 def test_eglantine_display_name_and_muted_startup(self):
  self.stream.update(app_name='Eglantine',levels={'mute':True,'softMute':True,'volume':0,'channelVolumes':[0,0],'softVolumes':[0,0]})
  self.assertTrue(m.is_eden(self.stream))
  for exe in ('eden','Eden.AppImage','eglantine','eglantine-local'):
   self.assertTrue(m.is_eden(dict(self.stream,app_name='',process={'exe':exe})))
  apps=[{'id':'exe:wrapper','streams':[self.stream]}]
  core=[{'type':'PipeWire:Interface:Core','info':{'cookie':42}}]
  m.write(m.CONFIG,{'enabled':True,'eden_default':True})
  def update(ident,cookie,changes):self.current(ident,cookie)['levels'].update(changes)
  with patch.object(m,'pw_dump',return_value=core),patch.object(m,'playback_apps',return_value=apps),patch.object(m,'set_stream_props',side_effect=update) as setter:
   m.update_eden_defaults()
   self.assertEqual(self.stream['levels'],{'mute':False,'softMute':False,'volume':1,'channelVolumes':[1,1],'softVolumes':[1,1]})
   self.stream['levels']['mute']=True
   m.update_eden_defaults();self.assertTrue(self.stream['levels']['mute']);setter.assert_called_once()
  self.assertEqual(m.startup_level_changes({'levels':{'volume':.25,'channelVolumes':[0,.5]}}),{})
  # Hidden WirePlumber scalar attenuation (volume=0.25 while mixer channelVolumes are 100%) is fixed.
  self.assertEqual(m.startup_level_changes({'levels':{'volume':.25,'channelVolumes':[1.0,1.0]}}),{'volume':1.0})
 def test_manual_gain_works_with_other_apps_playing(self):
  self.snapshot['foreign']=['Eden','osu!'];m.adjust(2);self.assertTrue(m.tick());self.assertEqual(m.read(m.SESSION)['db'],2)
 def test_matching_refuses_mixed_audio_before_recording(self):
  self.snapshot['foreign']=['Eden']
  with patch.object(m,'measure') as meter:
   with self.assertRaisesRegex(RuntimeError,'Pause other audio'):m.match()
   meter.assert_not_called();self.assertFalse(self.writes)
 def test_external_stage_edit_is_not_overwritten(self):
  m.adjust(2);self.stream['params'][m.GAIN_KEY]=9;m.cleanup();self.assertEqual(self.stream['params'][m.GAIN_KEY],9)
 def test_recycled_id_or_pid_is_not_cleaned_up(self):
  for field in ['serial','process']:
   with self.subTest(field=field):
    self.stream['params']={};m.write(m.SESSION,{});m.adjust(1)
    if field=='serial':self.stream['serial']='999'
    else:self.stream['process']['start']='999'
    writes=len(self.writes);m.cleanup();self.assertEqual(len(self.writes),writes)
 def test_pipewire_restart_cannot_target_new_server(self):
  m.adjust(1);self.snapshot['cookie']=99;writes=len(self.writes);m.cleanup();self.assertEqual(len(self.writes),writes)
 def test_new_song_resets_but_pause_does_not(self):
  m.adjust(1);self.snapshot['track']['status']='Paused';self.assertTrue(m.tick())
  self.snapshot['track']['key']='next';self.assertFalse(m.tick());self.assertNotIn(m.GAIN_KEY,self.stream['params'])
 def test_app_without_metadata_uses_stream_lifetime(self):
  self.snapshot['track']['stream_session']=True;m.adjust(2);self.assertTrue(m.tick())
  self.snapshot['streams']=[];self.assertFalse(m.tick())
 def test_new_stream_does_not_inherit_old_boost(self):
  m.adjust(2);old=self.stream;new=copy.deepcopy(old);new['serial']='200';new['params']={};self.snapshot['streams']=[new]
  self.assertFalse(m.tick());self.assertNotIn(m.GAIN_KEY,new['params'])
 def test_preset_change_never_stacks_and_leaves_its_gain_alone(self):
  m.adjust(2);writes=len(self.writes);self.snapshot.update(preset='new',limiter_serial='44',gain=-3)
  self.assertTrue(m.tick());self.assertTrue(m.tick());self.assertEqual(len(self.writes),writes);self.assertEqual(self.snapshot['gain'],-3)
  m.cleanup();self.assertNotIn(m.GAIN_KEY,self.stream['params'])
 def test_preset_follow_can_be_disabled(self):
  m.adjust(2);m.write(m.CONFIG,{'enabled':True,'selected_app':'exe:firefox','follow_presets':False});self.snapshot['preset']='other'
  self.assertFalse(m.tick());self.assertNotIn(m.GAIN_KEY,self.stream['params'])
 def test_off_restores_owned_stage(self):
  m.adjust(3);m.write(m.CONFIG,{'enabled':False});self.assertFalse(m.tick());self.assertNotIn(m.GAIN_KEY,self.stream['params'])
 def test_selection_change_cleans_previous_app_first(self):
  m.adjust(3)
  with patch.object(m,'pw_dump',return_value=[]),patch.object(m,'playback_apps',return_value=[{'id':'exe:other'}]):m.select_app('exe:other')
  self.assertNotIn(m.GAIN_KEY,self.stream['params']);self.assertEqual(m.config()['selected_app'],'exe:other')
 def test_output_or_route_change_resets(self):
  m.adjust(2);self.snapshot['route_signature']=[['changed']];self.assertFalse(m.tick());self.assertNotIn(m.GAIN_KEY,self.stream['params'])
 def test_missing_pipeline_still_removes_app_stage(self):
  m.adjust(1)
  with patch.object(m,'inspect',side_effect=RuntimeError('missing limiter')):self.assertFalse(m.tick())
  self.assertNotIn(m.GAIN_KEY,self.stream['params'])
 def test_failed_reset_keeps_recovery_receipt(self):
  m.adjust(1)
  with patch.object(m,'set_stream',side_effect=RuntimeError('unavailable')):
   with self.assertRaisesRegex(RuntimeError,'receipt retained'):m.cleanup()
  self.assertTrue(m.read(m.SESSION)['owned']);m.cleanup();self.assertNotIn(m.GAIN_KEY,self.stream['params'])
 def test_partial_multistream_failure_cleans_successful_stages(self):
  second=copy.deepcopy(self.stream);second['serial']='110';second['id']=10;self.snapshot['streams'].append(second)
  def fail(ident,cookie,params):
   if ident['serial']=='110':raise RuntimeError('second refused')
   self.set_stream(ident,cookie,params)
  with patch.object(m,'set_stream',side_effect=fail):
   with self.assertRaisesRegex(RuntimeError,'second refused'):m.adjust(1)
  self.assertNotIn(m.GAIN_KEY,self.stream['params']);self.assertFalse(m.read(m.SESSION)['owned'])
 def test_foreign_gain_slot_is_not_overwritten(self):
  self.stream['params'][m.GAIN_KEY]=2
  with self.assertRaisesRegex(RuntimeError,'matching receipt'):m.adjust(1)
  self.assertFalse(self.writes)
 def test_zero_removes_stage(self):
  m.adjust(1);m.adjust(-1);self.assertNotIn(m.GAIN_KEY,self.stream['params']);self.assertFalse(m.read(m.SESSION)['owned'])
 def test_match_adds_measured_headroom_once(self):
  with patch.object(m,'measure',return_value={'lufs':-22,'true_peak_dbtp':-10}):m.adjust(1);m.match()
  self.assertEqual(m.read(m.SESSION)['db'],7)
 def test_song_skip_during_measurement_discards_result(self):
  def measure(*args,**kw):self.snapshot['track']['key']='next';return {'lufs':-22,'true_peak_dbtp':-10}
  with patch.object(m,'measure',side_effect=measure):
   with self.assertRaisesRegex(RuntimeError,'changed'):m.match()
  self.assertFalse(self.writes)
 def test_other_audio_starting_during_measurement_discards_result(self):
  def measure(*args,**kw):self.snapshot['foreign']=['Eden'];return {'lufs':-22,'true_peak_dbtp':-10}
  with patch.object(m,'measure',side_effect=measure):
   with self.assertRaisesRegex(RuntimeError,'changed'):m.match()
  self.assertFalse(self.writes)
 def test_worker_start_failure_rolls_back_applied_gain(self):
  with patch.object(m,'ensure_worker',side_effect=RuntimeError('worker failed')):
   with self.assertRaisesRegex(RuntimeError,'worker failed'):m.adjust(1)
  self.assertNotIn(m.GAIN_KEY,self.stream['params']);self.assertFalse(m.read(m.SESSION)['owned'])
 def test_idle_worker_exit_does_not_clean_a_new_cli_transaction(self):
  def idle_tick():
   m.write(m.SESSION,{'owned':True,'operation':'new-transaction'});return False
  with patch.object(m,'tick',side_effect=idle_tick),patch.object(m,'cleanup') as cleanup,patch.object(m.time,'sleep'),patch.object(m.signal,'signal'):
   m.serve();cleanup.assert_not_called()
  self.assertTrue(m.read(m.SESSION)['owned'])
 def test_headroom_and_nonfinite(self):
  self.assertEqual(m.recommendation(-25,-12,-16,-1.85),(9,False));self.assertEqual(m.recommendation(-25,-4,-16,-1.85),(1.65,True))
  for n in [float('nan'),float('inf')]:
   with self.assertRaises(ValueError):m.adjust(n)
  with self.assertRaisesRegex(ValueError,'20 dB'):m.adjust(21)
 def test_automatic_matching_moves_up_and_down_in_bounded_steps(self):
  m.set_auto_match(True)
  with patch.object(m,'measure',return_value={'lufs':-24,'true_peak_dbtp':-12}):
   m.match(automatic=True);self.assertEqual(m.read(m.SESSION)['db'],1)
   m.match(automatic=True);self.assertEqual(m.read(m.SESSION)['db'],2)
  with patch.object(m,'measure',return_value={'lufs':-10,'true_peak_dbtp':-3}):
   m.match(automatic=True);self.assertEqual(m.read(m.SESSION)['db'],1)
  self.assertEqual(self.other['params'],{'eden_boost_gain:Mult':4});self.assertEqual(self.snapshot['gain'],2.82)
 def test_automatic_gain_stops_at_caps_and_preserves_headroom(self):
  self.assertEqual(m.auto_recommendation(-28,-12,-16,-1.85,6)[0],6)
  self.assertEqual(m.auto_recommendation(-4,-1,-16,-1.85,-12)[0],-12)
  self.assertEqual(m.auto_recommendation(-24,-2.7,-16,-1.85,0)[0],.35)
  self.assertEqual(m.auto_recommendation(-16.5,-8,-16,-1.85,2)[0],2)
  # Turning auto on after a large manual trim still changes at most one dB.
  self.assertEqual(m.auto_recommendation(-10,-3,-16,-1.85,20)[0],19)
 def test_silence_and_fades_do_not_accumulate_automatic_gain(self):
  m.set_auto_match(True)
  for lufs,peak in [(-65,-70),(-45,-25),(-20,-60)]:
   with self.subTest(lufs=lufs,peak=peak),patch.object(m,'measure',return_value={'lufs':lufs,'true_peak_dbtp':peak}):m.auto_attempt()
  self.assertFalse(self.writes);self.assertFalse(m.read(m.SESSION)['measuring'])
 def test_automatic_off_during_capture_discards_measurement(self):
  m.set_auto_match(True)
  def measure(*args,**kw):
   m.set_auto_match(False);return {'lufs':-24,'true_peak_dbtp':-12}
  with patch.object(m,'measure',side_effect=measure):
   with self.assertRaisesRegex(RuntimeError,'cancelled'):m.match(automatic=True)
  self.assertFalse(self.writes);self.assertFalse(m.config()['auto_match']);self.assertFalse(m.read(m.SESSION)['measuring'])
 def test_automatic_waits_for_playback_and_exclusive_audio(self):
  m.set_auto_match(True)
  with patch.object(m,'measure') as meter:
   self.snapshot['track']['status']='Paused';m.auto_attempt()
   self.snapshot['track']['status']='Playing';self.snapshot['foreign']=['osu!'];m.auto_attempt()
   meter.assert_not_called()
  self.assertFalse(self.writes)
 def test_manual_adjustment_turns_automatic_matching_off(self):
  m.set_auto_match(True);m.adjust(2)
  self.assertFalse(m.config()['auto_match']);self.assertEqual(m.read(m.SESSION)['db'],2)
  with patch.object(m,'measure') as meter:m.auto_attempt();meter.assert_not_called()
 def test_failed_automatic_worker_start_does_not_leave_auto_enabled(self):
  with patch.object(m,'ensure_worker',side_effect=RuntimeError('worker failed')):
   with self.assertRaisesRegex(RuntimeError,'worker failed'):m.set_auto_match(True)
  self.assertFalse(m.config()['auto_match'])
 def test_automatic_worker_waits_for_configured_interval(self):
  m.set_auto_match(True);clock=[100.0];attempts=[]
  def attempt():
   attempts.append(clock[0])
   if len(attempts)==2:m.set_auto_match(False)
  def sleep(seconds):clock[0]+=seconds
  with patch.object(m,'tick',return_value=False),patch.object(m,'auto_attempt',side_effect=attempt),patch.object(m.time,'monotonic',side_effect=lambda:clock[0]),patch.object(m.time,'sleep',side_effect=sleep),patch.object(m.signal,'signal'):
   m.serve()
  self.assertEqual(len(attempts),2);self.assertGreaterEqual(attempts[1]-attempts[0],30)
 def test_background_silence_probe_never_connects_to_a_microphone(self):
  self.snapshot.update(foreign=['Microphone'],foreign_nodes=[{'id':9,'serial':'109','kind':'Audio/Source'}])
  with self.assertRaisesRegex(RuntimeError,'Pause other audio'):m.meter_background(self.snapshot,True)
 def test_background_stream_changes_invalidate_the_sample(self):
  self.snapshot.update(foreign=['osu!'],foreign_nodes=[{'id':9,'serial':'109','kind':'Stream/Output/Audio'}])
  self.assertTrue(m.meter_scope_matches(self.snapshot,copy.deepcopy(self.snapshot),True))
  changed=copy.deepcopy(self.snapshot);changed['foreign_nodes'][0]['serial']='999'
  self.assertFalse(m.meter_scope_matches(self.snapshot,changed,True))
  self.assertFalse(m.meter_scope_matches(self.snapshot,self.snapshot,False))
 def test_automatic_matching_requires_silence_proof_for_each_background_stream(self):
  m.set_auto_match(True)
  self.snapshot.update(foreign=['osu!'],foreign_nodes=[{'id':9,'serial':'109','kind':'Stream/Output/Audio'}])
  with patch.object(m,'measure',return_value={'lufs':-24,'true_peak_dbtp':-12}):
   with self.assertRaisesRegex(RuntimeError,'changed'):m.match(automatic=True)
  self.assertFalse(self.writes)
  measured={'lufs':-24,'true_peak_dbtp':-12,'silent_background':self.snapshot['foreign_nodes']}
  with patch.object(m,'measure',return_value=measured):m.match(automatic=True)
  self.assertEqual(m.read(m.SESSION)['db'],1)

class DiscoveryTests(unittest.TestCase):
 def node(self,i,name,kind='Stream/Output/Audio',pid=20,state='running'):
  return {'type':'PipeWire:Interface:Node','id':i,'info':{'state':state,'props':{'node.name':name,'application.name':name,'object.serial':str(i+100),'media.class':kind,'client.id':pid},'params':{'Format':[{'channels':2}],'PropInfo':[{'name':'audioconvert.filter-graph.N'}],'Props':[{'params':[]}]}}}
 def test_firefox_and_unknown_app_without_mpris_are_discovered_from_native_client(self):
  data=[self.node(8,'Firefox'),self.node(9,'Novel Player',pid=30),self.node(10,'microphone','Audio/Source'),self.node(11,'effect_output.spatial-surround')]
  data += [{'type':'PipeWire:Interface:Client','id':p,'info':{'props':{'pipewire.sec.pid':p}}} for p in [20,30]]
  with patch.object(m,'birth',side_effect=lambda pid:{'pid':int(pid),'start':'1','exe':'firefox' if int(pid)==20 else 'novel'}):apps=m.playback_apps(data)
  self.assertEqual([a['id'] for a in apps],['exe:firefox','exe:novel']);self.assertTrue(all(a['streams'][0]['supported'] for a in apps))
 def test_mpris_is_optional(self):
  app={'id':'exe:firefox','name':'Firefox','streams':[{'serial':'1','process':{'pid':20,'start':'1','exe':'firefox'},'running':True}]}
  with patch.dict('sys.modules',{'gi':None}):track=m.music_track(app)
  self.assertEqual(track['status'],'Playing');self.assertTrue(track['stream_session'])
 def graph(self):
  data=[{'type':'PipeWire:Interface:Core','info':{'cookie':42}}]
  for i,name,kind in [(1,'easyeffects_sink','Audio/Sink'),(2,'ee_soe_equalizer',None),(3,'ee_soe_midside_equalizer',None),(4,'ee_soe_limiter',None),(5,'ee_soe_spectrum',None),(6,'ee_soe_output_level',None),(7,'physical','Audio/Sink'),(8,'Firefox','Stream/Output/Audio'),(9,'Eden','Stream/Output/Audio')]:data.append(self.node(i,name,kind))
  for a,b in [(1,2),(2,3),(3,4),(4,5),(5,6),(6,7),(8,1),(9,1)]:data.append(self.link(a,b))
  return data
 def link(self,a,b):return {'type':'PipeWire:Interface:Link','info':{'output-node-id':a,'input-node-id':b,'state':'active'}}
 def test_foreign_stream_only_disables_meter(self):
  result=m.graph_state(self.graph(),[{'id':8}]);self.assertEqual(result['foreign'],['Eden']);self.assertEqual(result['limiter_id'],4)
 def test_route_signature_survives_json_receipt(self):
  result=m.graph_state(self.graph(),[{'id':8}]);self.assertEqual(json.loads(json.dumps(result))['route_signature'],result['route_signature'])
 def test_unrelated_stream_change_is_not_a_selected_route_change(self):
  data=self.graph();before=m.graph_state(data,[{'id':8}]);data=[x for x in data if x.get('id')!=9]
  self.assertEqual(before['route_signature'],m.graph_state(data,[{'id':8}])['route_signature'])
 def test_bypassing_easy_effects_is_rejected(self):
  data=[x for x in self.graph() if not (x['type'].endswith(':Link') and x['info']['output-node-id']==8)]+[self.link(8,7)]
  with self.assertRaisesRegex(RuntimeError,'Route the selected'):m.graph_state(data,[{'id':8}])
 def test_effect_after_limiter_rejected(self):
  data=self.graph()+[self.node(10,'ee_soe_bass_enhancer',None),self.link(4,10),self.link(10,5)]
  with self.assertRaisesRegex(RuntimeError,'after'):m.graph_state(data,[{'id':8}])
 def test_spatial_route_and_mixed_source_are_traced(self):
  data=[x for x in self.graph() if not (x['type'].endswith(':Link') and x['info']['output-node-id']==8)]
  data += [self.node(10,'effect_input.spatial-surround','Audio/Sink',30),self.node(11,'effect_output.spatial-surround','Stream/Output/Audio',30),self.link(8,10),self.link(11,1)]
  self.assertEqual(m.graph_state(data,[{'id':8}])['foreign'],['Eden'])

if __name__=='__main__':unittest.main()
