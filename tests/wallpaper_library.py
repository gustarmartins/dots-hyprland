#!/usr/bin/env python3
"""Exercise retention and restore using real local files; no network/desktop changes."""
import fcntl
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
SCRIPTS = REPO / 'dots/.config/quickshell/ii/scripts/colors/random'
sys.path.insert(0, str(SCRIPTS))
import wallpaper_library as library
import discover_wallpaper as discovery

MIB = library.MIB


class Retention(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='wallpaper-library-test-')
        self.root = Path(self.temp.name)
        self.collection = self.root / 'Pictures/Wallpapers/Discovery'
        for module in [library, discovery]:
            module.CONFIG = self.root / 'config'
            module.STATE = self.root / 'state/wallpaper-discovery'
            module.CACHE = self.root / 'cache/wallpaper-discovery'
        self.store = library.Library(self.collection)
        self.config = library.CONFIG / 'illogical-impulse/config.json'
        self.config.parent.mkdir(parents=True)
        self.settings(limit=5, reserve=0)
        self.serial = 0

    def tearDown(self):
        self.temp.cleanup()

    def settings(self, limit=5, reserve=0, current=None):
        library.atomic_json(self.config, {'background': {'wallpaperPath': str(current or ''),
            'discovery': {'storageLimitMiB':limit, 'minFreeMiB':reserve}}, 'sentinel': [42, 'keep']})

    def original(self, name, size=MIB, favorite=False, current=False, timestamp=None):
        self.serial += 1
        path = self.collection / ('mario-' + name + '.png')
        output=io.BytesIO();Image.new('RGB',(1920,1080),'navy').save(output,'PNG')
        content=output.getvalue();path.write_bytes(content + b'\0' * max(0,size-len(content)))
        record=dict(id=name,path=str(path),theme='mario',label='Mario worlds',width=1920,height=1080,
            fetchedAt=timestamp if timestamp is not None else self.serial, favorite=favorite)
        library.atomic_json(self.store.metadata_path(name), record)
        if current:
            self.settings(current=path)
            library.atomic_json(library.STATE/'current.json',record)
        return path

    def test_oldest_first_kept_current_and_restart(self):
        current=self.original('current',current=True)
        kept=self.original('kept',favorite=True)
        oldest=self.original('oldest',timestamp=0)
        newest=self.original('newest',timestamp=10)
        self.settings(limit=4,current=current)
        result=self.store.enforce(incoming_bytes=MIB)
        self.assertFalse(oldest.exists());self.assertTrue(newest.exists())
        self.assertTrue(current.exists());self.assertTrue(kept.exists())
        fresh=library.Library(self.collection).snapshot()
        self.assertEqual(fresh['count'],3)
        self.assertEqual(fresh['keptCount'],1)
        self.assertEqual(result['removed'],['oldest'])

    def test_full_of_protected_images_stops_without_deleting(self):
        current=self.original('current',size=3*MIB,current=True)
        kept=self.original('kept',size=3*MIB,favorite=True)
        self.settings(limit=4,current=current)
        with self.assertRaises(library.StorageFull):self.store.enforce()
        self.assertTrue(current.exists());self.assertTrue(kept.exists())
        self.assertTrue(self.store.snapshot()['overBudget'])

    def test_free_space_reserve_is_enforced(self):
        current=self.original('current',size=2*MIB,current=True)
        old=self.original('old',size=3*MIB)
        self.settings(limit=20,reserve=6,current=current)
        def capacity(_):
            used=sum(p.stat().st_size for p in self.collection.glob('*.png'))
            return type('Usage',(),{'free':10*MIB-used})()
        with patch.object(library.shutil,'disk_usage',side_effect=capacity):
            self.store.enforce()
            self.assertFalse(old.exists());self.assertTrue(current.exists())
            with self.assertRaises(library.StorageFull):self.store.enforce(incoming_bytes=3*MIB)

    def test_user_files_and_symlinks_never_pruned(self):
        user=self.collection/'my-photo.png';user.write_bytes(b'user bytes')
        outside=self.root/'outside.png';outside.write_bytes(b'x'*(2*MIB))
        link=self.collection/'mario-external.png';link.symlink_to(outside)
        library.atomic_json(self.store.metadata_path('external'),dict(id='external',path=str(link),theme='mario',fetchedAt=1))
        self.settings(limit=1)
        with self.assertRaises(library.StorageFull):self.store.enforce()
        self.assertTrue(user.exists());self.assertTrue(link.is_symlink());self.assertEqual(outside.stat().st_size,2*MIB)

    def test_keep_survives_reuse_and_unkeep(self):
        path=self.original('favorite')
        self.store.keep('favorite',True)
        self.store.remember(dict(id='favorite',path=str(path),theme='mario',fetchedAt=20))
        self.assertTrue(library.read_json(self.store.metadata_path('favorite'),{})['favorite'])
        self.store.keep('favorite',False)
        self.assertFalse(self.store.snapshot()['entries'][0]['favorite'])
        with self.assertRaises(ValueError):self.store.keep('../../outside',True)

    def test_restore_updates_actual_current_and_history_after_success(self):
        first=self.original('first',current=True)
        second=self.original('second',favorite=True)
        def apply(command, **kwargs):
            self.assertEqual(command[-2:],['--image',str(second)])
            self.settings(current=second)
            return subprocess.CompletedProcess(command,0)
        with patch.object(library.subprocess,'run',side_effect=apply):self.store.restore('second')
        self.assertEqual(library.read_json(library.STATE/'current.json',{})['id'],'second')
        self.assertEqual(library.read_json(library.STATE/'history.json',[])[-1]['id'],'second')
        snapshot=library.Library(self.collection).snapshot()
        self.assertTrue(next(t for t in snapshot['entries'] if t['id']=='second')['current'])
        self.assertTrue(first.exists())
        with patch.object(library.subprocess,'run',side_effect=subprocess.CalledProcessError(1,['switchwall'])):
            with self.assertRaises(subprocess.CalledProcessError):self.store.restore('first')
        self.assertEqual(library.read_json(library.STATE/'current.json',{})['id'],'second')
        self.assertTrue(second.exists())
        self.assertEqual(library.read_json(self.config,{})['sentinel'],[42,'keep'])

    def test_failed_apply_still_records_download(self):
        previous=self.original('previous',current=True)
        new=self.collection/'mario-new.png';Image.new('RGB',(1920,1080),'red').save(new)
        entry=dict(id='new',path=str(new),theme='mario',label='Mario worlds',width=1920,height=1080,fetchedAt=10)
        with patch.object(discovery.subprocess,'run',side_effect=subprocess.CalledProcessError(1,['switchwall'])):
            self.assertEqual(discovery.finish(entry,[],False),1)
        self.assertTrue(new.exists());self.assertTrue(self.store.metadata_path('new').exists())
        self.assertEqual(library.read_json(library.STATE/'current.json',{})['id'],'previous')
        self.assertTrue(previous.exists())

    def response(self, content):
        class Response(io.BytesIO):
            url='https://w.wallhaven.cc/full/xx/wallhaven-new.png'
            headers={'Content-Length':str(len(content))}
        return Response(content)

    def test_bad_download_does_not_evict_old_originals(self):
        first=self.original('first');second=self.original('second')
        self.settings(limit=2)
        item={'id':'new','path':'https://w.wallhaven.cc/full/xx/new.png','provider':'Wallhaven'}
        with patch.object(discovery.urllib.request,'urlopen',return_value=self.response(b'not an image')):
            with self.assertRaises(OSError):discovery.download(item,'mario',self.collection)
        self.assertTrue(first.exists());self.assertTrue(second.exists())
        self.assertFalse(list(self.collection.glob('.download-*')))

    def test_valid_download_is_saved_within_limit(self):
        current=self.original('current',current=True);old=self.original('oldest',timestamp=0)
        self.settings(limit=2,current=current)
        payload=io.BytesIO();Image.new('RGB',(1920,1080),'green').save(payload,'PNG')
        item={'id':'new','path':'https://w.wallhaven.cc/full/xx/new.png','provider':'Wallhaven'}
        with patch.object(discovery.urllib.request,'urlopen',return_value=self.response(payload.getvalue())):
            path,w,h=discovery.download(item,'mario',self.collection)
        discovery.finish(dict(id='new',path=str(path),theme='mario',label='Mario worlds',width=w,height=h,fetchedAt=50),[],True)
        self.assertTrue(path.exists());self.assertTrue(current.exists());self.assertFalse(old.exists())
        self.assertLessEqual(self.store.snapshot()['totalBytes'],2*MIB)
        self.assertEqual(library.read_json(library.STATE/'current.json',{})['id'],'current')

    def test_prefetch_batch_never_applies_or_changes_current(self):
        self.original('current',current=True)
        before=library.read_json(self.config,{})
        saved=[]
        def fetch(*args):
            identity='queue'+str(len(saved)+1)
            path=self.original(identity,size=100000)
            saved.append(identity)
            return library.read_json(self.store.metadata_path(identity),{}),False
        argv=['discover','--theme','mario','--prefetch','3','--output-dir',str(self.collection)]
        with patch.object(sys,'argv',argv),patch.object(discovery,'fetch_one',side_effect=fetch), \
             patch.object(discovery.subprocess,'run',side_effect=AssertionError('Prefetch tried to apply colors')):
            self.assertEqual(discovery.main(),0)
        self.assertEqual(library.read_json(self.config,{}),before)
        self.assertEqual(library.read_json(library.STATE/'current.json',{})['id'],'current')
        self.assertEqual(self.store.snapshot()['queuedCount'],3)
        self.assertTrue(all(library.read_json(self.store.metadata_path(identity),{})['queued'] for identity in saved))
        self.assertEqual(library.read_json(library.STATE/'status.json',{})['operation'],'prefetch')
        self.assertFalse(library.read_json(library.STATE/'status.json',{})['busy'])

    def test_rotation_uses_ready_original_without_any_api(self):
        self.original('current',current=True)
        ready=self.original('ready',favorite=True)
        entry=library.read_json(self.store.metadata_path('ready'),{});entry['queued']=True
        library.atomic_json(self.store.metadata_path('ready'),entry)
        def apply(command,**kwargs):
            self.assertEqual(command[-1],str(ready));self.settings(current=ready)
            return subprocess.CompletedProcess(command,0)
        with patch.object(sys,'argv',['discover','--theme','mario','--output-dir',str(self.collection)]), \
             patch.object(discovery,'fetch_one',side_effect=AssertionError('Rotation requested the API')), \
             patch.object(discovery.subprocess,'run',side_effect=apply):
            self.assertEqual(discovery.main(),0)
        record=library.read_json(self.store.metadata_path('ready'),{})
        self.assertFalse(record['queued']);self.assertTrue(record['favorite'])
        self.assertEqual(self.store.snapshot()['queuedCount'],0)

    def test_prefetch_does_not_evict_its_own_partial_batch(self):
        current=self.original('current',current=True)
        first=self.original('batch-first')
        self.settings(limit=2,current=current)
        payload=io.BytesIO();Image.new('RGB',(1920,1080),'green').save(payload,'PNG')
        item={'id':'batch-next','path':'https://w.wallhaven.cc/full/xx/batch-next.png','provider':'Wallhaven'}
        discovery.PREFETCH_PROTECTED.append(str(first))
        try:
            with patch.object(discovery.urllib.request,'urlopen',return_value=self.response(payload.getvalue())):
                with self.assertRaises(library.StorageFull):discovery.download(item,'mario',self.collection)
            self.assertTrue(first.exists());self.assertTrue(current.exists())
            self.assertFalse(list(self.collection.glob('.download-*')))
        finally:
            discovery.PREFETCH_PROTECTED.clear()

    def test_exhausted_search_cache_gets_fresh_candidates(self):
        def item(identity):return {'id':identity,'purity':'sfw','category':'general','dimension_x':1920,'dimension_y':1080,'file_size':10000,'tags':[{'name':'Super Mario'}]}
        calls=[]
        def fetch(url,key=None,force=False):
            calls.append((url,force))
            if '/search?' in url:return {'data':[item('fresh' if force else 'seen')]}
            return {'data':item('fresh')}
        with patch.object(discovery,'fetch_json',side_effect=fetch):
            candidate=next(discovery.candidates('mario',{'seen'}))
        self.assertEqual(candidate['id'],'fresh')
        self.assertTrue(any(force for url,force in calls if '/search?' in url))

    def test_missing_and_corrupt_records_dont_break_gallery(self):
        self.original('valid')
        (library.STATE/'sources/corrupt.json').write_text('{invalid')
        library.atomic_json(library.STATE/'sources/missing.json',dict(id='missing',path=str(self.root/'absent.png')))
        self.assertEqual(self.store.snapshot()['count'],1)

    def test_fetch_and_history_share_lock(self):
        self.original('valid')
        env=os.environ.copy();env.update(HOME=str(self.root),XDG_CONFIG_HOME=str(library.CONFIG),
            XDG_STATE_HOME=str(self.root/'state'),XDG_CACHE_HOME=str(self.root/'cache'))
        with (library.STATE/'fetch.lock').open('a') as held:
            fcntl.flock(held,fcntl.LOCK_EX|fcntl.LOCK_NB)
            result=subprocess.run([sys.executable,str(SCRIPTS/'wallpaper_library.py'),'list'],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,2)
            self.assertIn('already running',json.loads(result.stdout)['error'])


if __name__=='__main__':unittest.main(verbosity=2)
