import importlib.machinery,importlib.util,math,pathlib,unittest
from unittest.mock import patch
loader=importlib.machinery.SourceFileLoader('eden_boost',str(pathlib.Path(__file__).resolve().parents[1]/'dots/.local/bin/eden-audio-boost'))
spec=importlib.util.spec_from_loader(loader.name,loader);b=importlib.util.module_from_spec(spec);loader.exec_module(b)
class BoostTests(unittest.TestCase):
 def test_graph_is_linear_twelve_db_and_preserves_channels(self):
  g=b.graph(12);node=g['nodes'][0]
  self.assertAlmostEqual(node['control']['Mult'],3.9810717055)
  self.assertEqual(g['n_inputs'],2)
  self.assertEqual(g['n_outputs'],2)
  self.assertNotIn('volume',g)
 def test_spoofed_application_name_does_not_match(self):
  s={'index':1,'properties':{'application.name':'Eden','application.process.id':'42','object.serial':'55'}}
  with patch.object(b.os,'readlink',return_value='/usr/bin/mpv'):
   self.assertIsNone(b.identity(s,{},{}))
 def test_native_stream_uses_verified_client_process(self):
  s={'index':1,'properties':{'object.serial':'55'}}
  fields=['S']+['1']*19;fields[19]='987'
  with patch.object(b.os,'readlink',return_value='/opt/eden/eden'),patch.object(pathlib.Path,'read_text',return_value='42 (eden) '+' '.join(fields)):
   r=b.identity(s,{9:{'pipewire.sec.pid':42}},{'55':{'client.id':9}})
  self.assertEqual(r,dict(pid=42,start=987,serial='55',index=1))
 def test_missing_pid_is_not_name_matched(self):
  self.assertIsNone(b.identity({'index':1,'properties':{'application.name':'Eden'}},{},{}))
 def test_helper_name_is_not_enough_if_executable_is_python(self):
  s={'index':1,'properties':{'application.process.id':'42'}}
  with patch.object(b.os,'readlink',return_value='/usr/bin/python3'):
   self.assertIsNone(b.identity(s,{},{}))
if __name__=='__main__':unittest.main()
