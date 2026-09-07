import unittest
from ad_detect import detect, parse_metadata

class DetectorTests(unittest.TestCase):
    def samples(self, overrides, duration=100):
        return [{'time':i/2,'crop':overrides.get(i,(1920,804+(i%3)*2,0,138))} for i in range(duration*2)]

    def test_jitter_and_brief_transition(self):
        s=self.samples({i:(1920,1080,0,0) for i in range(40,48)})
        self.assertEqual(detect(s,100,.5)[2],[])

    def test_ad_and_gap_merge(self):
        s=self.samples({i:(1920,1080,0,0) for i in list(range(70,90))+list(range(92,112))})
        ads=detect(s,100,.5)[2]
        self.assertEqual(len(ads),1)
        self.assertAlmostEqual(ads[0]['start'],34.75)
        self.assertAlmostEqual(ads[0]['end'],55.75)

    def test_resolution_change(self):
        s=[{'time':i,'crop':(1920,1080,0,0) if 40<=i<60 else (976,720,0,0)} for i in range(100)]
        main,_,ads=detect(s,100,1)
        self.assertEqual(main,(976,720,0,0))
        self.assertEqual(len(ads),1)

    def test_black_frames_are_unknown(self):
        self.assertEqual(detect(self.samples({i:None for i in range(60,100)}),100,.5)[2],[])

    def test_metadata_reset_uses_time(self):
        txt=''
        for frame,t in [(10,5),(0,6)]:
            txt+=f'frame:{frame} pts:0 pts_time:{t}\n'+''.join(f'lavfi.cropdetect.{k}={v}\n' for k,v in zip(('w','h','x','y'),(976,720,0,0)))
        self.assertEqual([s['time'] for s in parse_metadata(txt)],[5,6])
        with self.assertRaises(ValueError):
            parse_metadata('frame:0 pts:0 pts_time:1\nlavfi.cropdetect.w=10')

if __name__=='__main__':
    unittest.main()
