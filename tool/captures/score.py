"""Score OCR captures by hand-typed truth (WP6a, D6a.5).

Run:  python3 -I tool/captures/score.py wp0/fixtures/private/captures/captures.tsv

Getting the captures off the phone
  1. Settings > Diagnostics > "Save OCR crops" on, then tap some bubbles.
  2. Connect the iPhone, open Finder > iPhone > Files > Yomitanuki.
  3. Copy the `ocr-captures` folder to `wp0/fixtures/private/captures/`.
     It MUST land under `wp0/fixtures/private/`: that path is gitignored and
     page photos and OCRed book text never enter git (P4).

Adding the truth
  Open `captures.tsv` in a spreadsheet or editor and add a ninth column named
  `truth` holding what the bubble really says (look at the PNG named in the
  `png` column). Rows with an empty or missing `truth` are skipped and
  counted.

What is printed
  Exact-match rate and character error rate (total Levenshtein distance over
  total truth length, so long bubbles weigh more), overall and bucketed by
  `crop_w` (< 150, 150-299, >= 300 px), then one line per mismatch. Crop width
  is the variable the accuracy question turns on (C7).

Standard library only.
"""

import sys
from dataclasses import dataclass

BUCKETS = ("< 150", "150-299", ">= 300")


def levenshtein(a, b):
    """Edit distance between two strings, counted in code points."""
    if len(a) < len(b):
        a, b = b, a
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, start=1):
        current = [i]
        for j, cb in enumerate(b, start=1):
            current.append(
                min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + (ca != cb),
                )
            )
        previous = current
    return previous[-1]


def bucket(crop_w):
    if crop_w < 150:
        return BUCKETS[0]
    if crop_w < 300:
        return BUCKETS[1]
    return BUCKETS[2]


@dataclass
class Row:
    png: str
    crop_w: int
    text: str
    truth: str

    @property
    def edits(self):
        return levenshtein(self.text, self.truth)


@dataclass
class Tally:
    count: int = 0
    exact: int = 0
    edits: int = 0
    truth_chars: int = 0

    def add(self, row):
        self.count += 1
        self.exact += row.text == row.truth
        self.edits += row.edits
        self.truth_chars += len(row.truth)

    @property
    def cer(self):
        return self.edits / self.truth_chars if self.truth_chars else 0.0


def _int(cell):
    """A spreadsheet round trip may write `150.0` or leave the cell blank."""
    try:
        return int(float(cell))
    except ValueError:
        return 0


def read_rows(path):
    """Returns (rows with a truth, number of rows skipped for lacking one)."""
    rows, skipped = [], 0
    with open(path, encoding="utf-8", newline="") as f:
        # Not splitlines(): it also breaks on VT, FF, NEL and friends, which a
        # TSV cell may legitimately hold. Rows end with LF (CRLF tolerated).
        lines = [l.rstrip("\r") for l in f.read().split("\n")]
    header = lines[0].split("\t") if lines else []
    index = {name: i for i, name in enumerate(header)}
    for line in lines[1:]:
        if not line.strip():
            continue
        cells = line.split("\t")

        def cell(name):
            i = index.get(name)
            return cells[i].strip() if i is not None and i < len(cells) else ""

        truth = cell("truth")
        if not truth:
            skipped += 1
            continue
        rows.append(Row(cell("png"), _int(cell("crop_w")), cell("text"), truth))
    return rows, skipped


def summarise(rows):
    overall = Tally()
    buckets = {name: Tally() for name in BUCKETS}
    for row in rows:
        overall.add(row)
        buckets[bucket(row.crop_w)].add(row)
    return {"overall": overall, "buckets": buckets}


def _line(label, tally):
    if tally.count == 0:
        return f"{label:<10} no rows"
    return (
        f"{label:<10} exact {tally.exact}/{tally.count} "
        f"({tally.exact / tally.count:.1%})  CER {tally.cer:.1%}"
    )


def main(argv, out=sys.stdout):
    if len(argv) != 1:
        print("usage: python3 -I score.py captures.tsv", file=out)
        return 2
    rows, skipped = read_rows(argv[0])
    print(f"skipped (no truth): {skipped}", file=out)
    if not rows:
        print("no rows with a truth column filled in", file=out)
        return 1
    report = summarise(rows)
    print(_line("overall", report["overall"]), file=out)
    for name in BUCKETS:
        print(_line(f"w {name}", report["buckets"][name]), file=out)
    mismatches = [r for r in rows if r.text != r.truth]
    if mismatches:
        print("\nmismatches:", file=out)
    for r in mismatches:
        print(
            f"{r.png}  w={r.crop_w}  edits={r.edits}\n"
            f"  ocr:   {r.text}\n  truth: {r.truth}",
            file=out,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
