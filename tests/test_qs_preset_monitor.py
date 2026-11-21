#!/usr/bin/env python3
import contextlib
import csv
import io
from pathlib import Path
import runpy
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

TOOL = Path(__file__).resolve().parents[1]/'dots/.local/bin/qs-preset-monitor'


class PresetMonitor(unittest.TestCase):
    def test_switch_excludes_mixed_samples_and_keeps_missing_metrics_empty(self):
        main = runpy.run_path(str(TOOL))['main']
        clock = iter(range(20))
        names = iter(['light','light','balanced','balanced','cinematic','cinematic','aurora','aurora'])
        time = Mock(monotonic=lambda:next(clock),sleep=lambda _:None,time=lambda:1000.0)
        def values(*_):
            return {'cpu':4, 'gpu':None, 'ram':5000, 'vram':400, 'gtt':600}
        with tempfile.TemporaryDirectory() as directory:
            csvfile=Path(directory)/'test.csv'
            with patch.dict(main.__globals__, time=time,preset=lambda:next(names),gpu_card=lambda _:None,
                            cpu_ticks=lambda:(100,20),sample=values), patch.object(sys, 'argv',
                            [str(TOOL),'--samples','7','--settle','0','--csv',str(csvfile)]), contextlib.redirect_stdout(io.StringIO()):
                main()
            with csvfile.open() as source:rows=list(csv.DictReader(source))
            self.assertEqual([r['preset'] for r in rows if r['settled']=='1'], ['light','balanced','cinematic','aurora'])
            self.assertTrue(all(r['gpu_percent']=='' and r['vram_used_mib']=='400' for r in rows))
            self.assertEqual([r['settled'] for r in rows],list('1010101'))


if __name__=='__main__':
    unittest.main()
