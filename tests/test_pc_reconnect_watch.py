import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

REPO=Path(__file__).resolve().parents[1]
loader=importlib.machinery.SourceFileLoader('reconnect',str(REPO/'dots/.local/bin/pc-reconnect-watch'))
spec=importlib.util.spec_from_loader(loader.name,loader);watch=importlib.util.module_from_spec(spec);loader.exec_module(watch)

class WatchTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.patches=[patch.object(watch,'ROOT',self.root/'state'),patch.object(watch,'CONFIG',self.root/'config.json')]
        for p in self.patches:p.start()
        watch.save_config(dict(enabled=True,desktop=True,repeat=False,wakeCodex=True,sshAlias='fixture-pc',displayName='Fixture PC'))
    def tearDown(self):
        for p in self.patches:p.stop()
        self.tmp.cleanup()

    def test_offline_does_not_notify_or_wake(self):
        with patch.object(watch,'probe',return_value=(False,'offline')),patch.object(watch,'notify') as notify,patch.object(watch,'wake') as wake:
            self.assertFalse(watch.check()['online']);notify.assert_not_called();wake.assert_not_called()

    def test_success_notifies_wakes_and_disarms_once(self):
        with patch.object(watch,'probe',return_value=(True,'online')),patch.object(watch,'notify',return_value=True) as notify,patch.object(watch,'wake',return_value=True) as wake,patch.object(watch,'systemctl') as system:
            system.return_value.returncode=0
            state=watch.check();self.assertEqual(state['alerts'],1);self.assertFalse(watch.config()['enabled'])
            self.assertIn('skipped',watch.check());self.assertEqual(notify.call_count,1);self.assertEqual(wake.call_count,1)
            system.assert_called_once_with('disable','--now',watch.TIMER)

    def test_wake_retry_does_not_duplicate_desktop_notification(self):
        with patch.object(watch,'probe',return_value=(True,'online')),patch.object(watch,'notify',return_value=True) as notify,patch.object(watch,'wake',side_effect=[False,True]) as wake,patch.object(watch,'systemctl') as system:
            system.return_value.returncode=0
            self.assertTrue(watch.check()['wakePending']);self.assertTrue(watch.config()['enabled'])
            self.assertFalse(watch.check()['wakePending']);self.assertFalse(watch.config()['enabled'])
            self.assertEqual(notify.call_count,1);self.assertEqual(wake.call_count,2)

    def test_notification_retry_does_not_duplicate_wake(self):
        with patch.object(watch,'probe',return_value=(True,'online')),patch.object(watch,'notify',side_effect=[False,True]) as notify,patch.object(watch,'wake',return_value=True) as wake,patch.object(watch,'systemctl') as system:
            system.return_value.returncode=0
            self.assertTrue(watch.check()['notificationPending']);self.assertFalse(watch.check()['notificationPending'])
            self.assertEqual(wake.call_count,1);self.assertEqual(notify.call_count,2)

    def test_repeat_mode_alerts_only_on_offline_to_online_transition(self):
        c=watch.config();c['repeat']=True;watch.save_config(c)
        with patch.object(watch,'probe',side_effect=[(True,'online'),(True,'online'),(False,'offline'),(True,'online')]),patch.object(watch,'notify',return_value=True) as notify,patch.object(watch,'wake',return_value=True) as wake:
            for _ in range(4):watch.check()
            self.assertTrue(watch.config()['enabled']);self.assertEqual(notify.call_count,2);self.assertEqual(wake.call_count,2)

    def test_off_during_probe_prevents_any_delivery(self):
        def offline_switch(alias):
            c=watch.config();c['enabled']=False;watch.save_config(c);return True,'online'
        with patch.object(watch,'probe',side_effect=offline_switch),patch.object(watch,'notify') as notify,patch.object(watch,'wake') as wake:
            watch.check();notify.assert_not_called();wake.assert_not_called()

    def test_probe_never_relaxes_pins_or_executes_alias_as_options(self):
        with patch.object(watch.subprocess,'run') as run:
            run.return_value.returncode=0;run.return_value.stdout='PC_RECONNECT_READY\n'
            self.assertTrue(watch.probe('fixture-pc')[0]);args=run.call_args.args[0]
            self.assertIn('StrictHostKeyChecking=yes',args);self.assertIn('BatchMode=yes',args)
            self.assertEqual(args[-2:],[ 'fixture-pc','cmd.exe /d /c echo PC_RECONNECT_READY'])
            run.reset_mock();self.assertFalse(watch.probe('-oProxyCommand=bad')[0]);run.assert_not_called()

if __name__=='__main__':unittest.main()
