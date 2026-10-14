"""Tests for score.py. Run: python3 -I tool/captures/test_score.py

`-I` leaves the script's folder off sys.path, so score.py is loaded by path.
"""

import importlib.util
import io
import os
import tempfile
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "score", Path(__file__).with_name("score.py")
)
score = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(score)

HEADER = "timestamp\tpng\tcrop_w\tcrop_h\tframe_w\tframe_h\telapsed_ms\ttext\ttruth"


def row(png, crop_w, text, truth=None):
    cells = ["2026-10-14T09:08:07", png, str(crop_w), "100", "1080", "1920", "400", text]
    if truth is not None:
        cells.append(truth)
    return "\t".join(cells)


_tmp = tempfile.TemporaryDirectory()


def write_tsv(lines):
    handle, path = tempfile.mkstemp(suffix=".tsv", dir=_tmp.name)
    with os.fdopen(handle, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return path


class LevenshteinTest(unittest.TestCase):
    def test_distances(self):
        self.assertEqual(score.levenshtein("", ""), 0)
        self.assertEqual(score.levenshtein("abc", "abc"), 0)
        self.assertEqual(score.levenshtein("abc", ""), 3)
        self.assertEqual(score.levenshtein("", "abc"), 3)
        self.assertEqual(score.levenshtein("kitten", "sitting"), 3)
        self.assertEqual(score.levenshtein("食べる", "喰べる"), 1)


class BucketTest(unittest.TestCase):
    def test_boundaries(self):
        self.assertEqual(score.bucket(0), "< 150")
        self.assertEqual(score.bucket(149), "< 150")
        self.assertEqual(score.bucket(150), "150-299")
        self.assertEqual(score.bucket(299), "150-299")
        self.assertEqual(score.bucket(300), ">= 300")


class ScoreTest(unittest.TestCase):
    def test_rows_without_truth_are_skipped_and_counted(self):
        path = write_tsv(
            [
                HEADER,
                row("a.png", 120, "食べる", "食べる"),
                row("b.png", 120, "読む"),  # no truth cell at all
                row("c.png", 120, "行く", ""),  # empty truth cell
            ]
        )
        rows, skipped = score.read_rows(path)
        self.assertEqual(len(rows), 1)
        self.assertEqual(skipped, 2)

    def test_exact_match_and_cer_overall_and_by_bucket(self):
        path = write_tsv(
            [
                HEADER,
                row("a.png", 100, "食べる", "食べる"),  # exact
                row("b.png", 200, "喰べる", "食べる"),  # 1 edit / 3
                row("c.png", 400, "あ", "あいうえ"),  # 3 edits / 4
            ]
        )
        rows, _ = score.read_rows(path)
        report = score.summarise(rows)

        overall = report["overall"]
        self.assertEqual(overall.count, 3)
        self.assertEqual(overall.exact, 1)
        self.assertAlmostEqual(overall.cer, 4 / 10)
        self.assertEqual(report["buckets"]["< 150"].exact, 1)
        self.assertAlmostEqual(report["buckets"]["150-299"].cer, 1 / 3)
        self.assertAlmostEqual(report["buckets"][">= 300"].cer, 3 / 4)

    def test_failed_reads_count_as_misses(self):
        path = write_tsv([HEADER, row("a.png", 100, "", "食べる")])
        rows, _ = score.read_rows(path)
        overall = score.summarise(rows)["overall"]
        self.assertEqual(overall.exact, 0)
        self.assertAlmostEqual(overall.cer, 1.0)

    def test_report_lists_each_mismatch_and_the_skipped_count(self):
        path = write_tsv(
            [
                HEADER,
                row("a.png", 100, "食べる", "食べる"),
                row("b.png", 200, "喰べる", "食べる"),
                row("c.png", 200, "読む"),
            ]
        )
        out = io.StringIO()
        score.main([path], out)
        text = out.getvalue()
        self.assertIn("b.png", text)
        self.assertIn("喰べる", text)
        self.assertNotIn("a.png", text)
        self.assertIn("skipped (no truth): 1", text)
        self.assertIn("exact 1/2", text)

    def test_no_scored_rows_says_so(self):
        path = write_tsv([HEADER, row("a.png", 100, "食べる")])
        out = io.StringIO()
        self.assertEqual(score.main([path], out), 1)
        self.assertIn("no rows with a truth", out.getvalue())


if __name__ == "__main__":
    unittest.main()
