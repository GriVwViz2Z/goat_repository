"""Small reproducible FFmpeg integration fixture, including Chinese/spaced paths."""
import tempfile
import unittest
from pathlib import Path
from cutter import run,probe,make_plan,export,fingerprint

class Integration(unittest.TestCase):
    def test_stream_copy_and_guards(self):
        with tempfile.TemporaryDirectory(prefix='aspect-integration-') as td:
            d=Path(td)
            (d/'sub.srt').write_text('1\n00:00:01,000 --> 00:00:02,000\n开场\n\n2\n00:00:09,000 --> 00:00:11,000\n结尾\n')
            (d/'meta.txt').write_text(';FFMETADATA1\ntitle=测试电影\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=4000\ntitle=开场\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=4000\nEND=8000\ntitle=广告\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=8000\nEND=12000\ntitle=结尾\n')
            source=d/'中文 电影.mkv'
            run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=320x180:rate=25:duration=12','-f','lavfi','-i','sine=frequency=440:duration=12','-f','lavfi','-i','sine=frequency=880:duration=12','-i',str(d/'sub.srt'),'-f','ffmetadata','-i',str(d/'meta.txt'),'-map','0:v','-map','1:a','-map','2:a','-map','3:s','-map_metadata','4','-map_chapters','4','-c:v','libx264','-g','50','-keyint_min','50','-sc_threshold','0','-bf','0','-c:a','aac','-c:s','srt','-metadata:s:a:0','language=zho','-metadata:s:a:1','language=eng',str(source)])
            before=fingerprint(source)
            plan=make_plan(source,[[4.2,7.8]])
            target=d/'干净 电影.mkv'
            result=export(plan,target)
            info=probe(target)
            self.assertEqual(result['streams'],4)
            self.assertEqual(info['format']['tags']['title'],'测试电影')
            self.assertEqual([s.get('tags',{}).get('language') for s in info['streams'] if s['codec_type']=='audio'],['zho','eng'])
            self.assertEqual(fingerprint(source),before)
            self.assertLess(abs(result['duration']-plan['expected_duration']),.5)
            self.assertTrue(info['chapters'])
            with self.assertRaises(ValueError): export(plan,source)
            with self.assertRaises(ValueError): export(plan,target)
            with self.assertRaises(ValueError): make_plan(source,[[8,2]])
            with self.assertRaises(ValueError): make_plan(source,[[0,12.023]])
            for label,ranges in [('head',[[0,2.5]]),('tail',[[9,plan['duration']]])]:
                export(make_plan(source,ranges),d/(label+'.mkv'))

if __name__=='__main__':
    unittest.main()
