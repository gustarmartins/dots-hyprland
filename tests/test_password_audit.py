import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

REPO=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('password_audit',REPO/'dots/.local/share/imak-sspr/audit.py')
audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)

def event(i='a',name='Reset password (self-service)'):
    return dict(id=i,activityDateTime='2026-10-14T01:00:00Z',activityDisplayName=name,result='success',
                initiatedBy=dict(user=dict(userPrincipalName='fixture@example.invalid')),
                targetResources=[dict(id='user-id',userPrincipalName='fixture@example.invalid',type='User',modifiedProperties=[dict(newValue='secret')])],
                additionalDetails=[dict(key='phone',value='secret')])

class AuditTest(unittest.TestCase):
    def test_archive_omits_authentication_values(self):
        x=audit.clean(event())
        self.assertNotIn('secret',json.dumps(x));self.assertEqual(x['result'],'success')
        self.assertIsNone(audit.clean(event(name='Add member to group')))

    def test_pagination_and_repeated_collection_deduplicate(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(audit,'ROOT',Path(tmp)),patch.object(audit,'verify_tenant'),patch.object(audit,'notify',return_value=0):
            next_url='https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?$skiptoken=fixture'
            pages=[json.dumps({'value':[event()],'@odata.nextLink':next_url}),json.dumps({'value':[event('b')]})]
            with patch.object(audit,'cli',side_effect=pages):self.assertEqual(audit.collect()['newEvents'],2)
            with patch.object(audit,'cli',side_effect=pages):self.assertEqual(audit.collect()['newEvents'],0)
            self.assertEqual(len((Path(tmp)/'events.jsonl').read_text().splitlines()),2)
            self.assertNotIn('secret',(Path(tmp)/'events.jsonl').read_text())

    def test_foreign_pagination_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(audit,'ROOT',Path(tmp)),patch.object(audit,'verify_tenant'),patch.object(audit,'cli',return_value=json.dumps({'value':[],'@odata.nextLink':'https://example.invalid/capture'})) as request:
            with self.assertRaisesRegex(RuntimeError,'pagination'):audit.collect()
            self.assertEqual(request.call_count,1)

    def test_failure_does_not_advance_success(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(audit,'ROOT',Path(tmp)),patch.object(audit,'verify_tenant'),patch.object(audit,'cli',side_effect=RuntimeError('offline')):
            with self.assertRaises(RuntimeError):audit.collect()
            self.assertFalse((Path(tmp)/'status.json').exists())

    def test_disabled_features_skip_alerts_and_progress(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(audit,'ROOT',Path(tmp)),patch.object(audit,'config',return_value=dict(desktop=True,resets=False,recovery=False)),patch.object(audit.subprocess,'run') as notify:
            db=audit.connect()
            for i,name in [('a','Reset password (self-service)'),('b','User registered security info'),('c','Self-service password reset flow activity progress')]:
                x=audit.clean(event(i,name));db.execute('INSERT INTO events VALUES(?,?,?,0)',(i,x['time'],json.dumps(x)))
            self.assertEqual(audit.notify(db),0);notify.assert_not_called()
            self.assertEqual(db.execute('SELECT COUNT(*) FROM events WHERE notified=0').fetchone()[0],0)

    def test_burst_is_one_popup_and_not_replayed(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(audit,'ROOT',Path(tmp)),patch.object(audit,'config',return_value=dict(desktop=True,resets=True,recovery=True)),patch.object(audit.subprocess,'run') as notify:
            notify.return_value.returncode=0;db=audit.connect()
            for i in range(12):
                x=audit.clean(event(str(i)));db.execute('INSERT INTO events VALUES(?,?,?,0)',(x['id'],x['time'],json.dumps(x)))
            self.assertEqual(audit.notify(db),12);self.assertEqual(notify.call_count,1)
            self.assertTrue(any('12 events' in arg for arg in notify.call_args.args[0]))
            self.assertEqual(audit.notify(db),0);self.assertEqual(notify.call_count,1)

    def test_notification_failure_retains_queue(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(audit,'ROOT',Path(tmp)),patch.object(audit,'config',return_value=dict(desktop=True,resets=True,recovery=True)),patch.object(audit.subprocess,'run') as notify:
            notify.return_value.returncode=1;db=audit.connect();x=audit.clean(event())
            db.execute('INSERT INTO events VALUES(?,?,?,0)',(x['id'],x['time'],json.dumps(x)))
            with self.assertRaisesRegex(RuntimeError,'queued'):audit.notify(db)
            self.assertEqual(db.execute('SELECT notified FROM events').fetchone()[0],0)

if __name__=='__main__':unittest.main()
