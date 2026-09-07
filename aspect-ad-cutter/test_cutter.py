import unittest
from cutter import merge_ranges,remap_chapters,make_plan,export

class CutTests(unittest.TestCase):
    def test_merge(self):
        self.assertEqual(merge_ranges([[10,20],[19,22],[30,40]]),[[10,22],[30,40]])

    def test_chapter_remap(self):
        pieces=[dict(start=0,end=10,keep=True),dict(start=10,end=20,keep=False),dict(start=20,end=40,keep=True)]
        ch=[dict(start_time=5,end_time=25,tags={'title':'横跨广告'}),dict(start_time=12,end_time=18,tags={})]
        self.assertEqual(remap_chapters(ch,pieces),[{'start':5,'end':15,'tags':{'title':'横跨广告'}}])

    def test_fully_removed_chapter(self):
        self.assertEqual(remap_chapters([dict(start_time=5,end_time=10)], [dict(start=0,end=15,keep=False)]),[])

if __name__=='__main__':
    unittest.main()
