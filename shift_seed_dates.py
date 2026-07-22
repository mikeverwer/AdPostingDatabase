#!/usr/bin/env python3
"""
Slide every date in the AdPostingDB seed files forward (or back) so that the
dataset sits near the current (or given) date.

Each seed file carries an anchor line of the form

    -- SEED_ANCHOR_DATE: YYYY-MM-DD

The shift applied is (target date - anchor date), a whole number of days, which
is added uniformly to every date and timestamp literal in the file. Because the
shift is uniform, the relative spacing between dates is untouched, so every
invariant the seed data was built around continues to hold:

    EnteredPending <= ReviewDate <= PostDate
    the mix of expired and still-active board postings
    message chronology within each conversation
    the ads deliberately left "entered pending today"

The anchor line is rewritten to the new date, so the script is idempotent:
running it twice on the same day shifts by zero the second time.

Both engine files are shifted together and then compared, because letting the
two drift apart is the failure mode this dataset is most prone to.

Usage
-----
    python shift_seed_dates.py                     # shift to today, in place
    python shift_seed_dates.py --to 2027-01-15     # shift to a specific date
    python shift_seed_dates.py --dry-run           # report, write nothing
    python shift_seed_dates.py --files a.sql b.sql # override the file list
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent

DEFAULT_FILES = [
    _REPO_ROOT / "mssql" / "MSSQL_INSERT.sql",
    _REPO_ROOT / "mysql" / "MySQL_INSERT.sql",
]

ANCHOR_RE = re.compile(r"(--\s*SEED_ANCHOR_DATE:\s*)(\d{4}-\d{2}-\d{2})")

# Quoted date or datetime literals: 'YYYY-MM-DD' or 'YYYY-MM-DD HH:MM:SS'.
# The time-of-day portion, when present, is preserved untouched.
DATE_RE = re.compile(r"'(\d{4})-(\d{2})-(\d{2})((?:\s+\d{2}:\d{2}:\d{2})?)'")


class ShiftError(RuntimeError):
    pass


def read_anchor(text: str, path: Path) -> dt.date:
    match = ANCHOR_RE.search(text)
    if match is None:
        raise ShiftError(
            f"{path}: no SEED_ANCHOR_DATE line found. Expected a comment of the "
            f"form '-- SEED_ANCHOR_DATE: YYYY-MM-DD' near the top of the file."
        )
    if len(ANCHOR_RE.findall(text)) > 1:
        raise ShiftError(f"{path}: more than one SEED_ANCHOR_DATE line found.")
    return dt.date.fromisoformat(match.group(2))


def shift_text(text: str, delta: dt.timedelta) -> tuple[str, int]:
    """Return the text with every date literal shifted, and the count shifted."""
    count = 0

    def replace(match: re.Match) -> str:
        nonlocal count
        year, month, day, time_part = match.groups()
        original = dt.date(int(year), int(month), int(day))
        shifted = original + delta
        count += 1
        return f"'{shifted.isoformat()}{time_part}'"

    return DATE_RE.sub(replace, text), count


def set_anchor(text: str, new_anchor: dt.date) -> str:
    return ANCHOR_RE.sub(
        lambda m: f"{m.group(1)}{new_anchor.isoformat()}", text, count=1
    )


def date_literals(text: str) -> list[str]:
    """Every date literal in the file, in order, for cross-file comparison."""
    return [f"{y}-{m}-{d}{t}" for y, m, d, t in DATE_RE.findall(text)]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Shift AdPostingDB seed dates to sit near the current date."
    )
    parser.add_argument(
        "--to",
        metavar="YYYY-MM-DD",
        help="Target date to shift the anchor to. Defaults to today.",
    )
    parser.add_argument(
        "--files",
        nargs="+",
        metavar="FILE",
        default=DEFAULT_FILES,
        help=f"Seed files to shift. Defaults to: {' '.join(str(f) for f in DEFAULT_FILES)}",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report what would change without writing anything.",
    )
    args = parser.parse_args(argv)

    try:
        target = (
            dt.date.fromisoformat(args.to) if args.to else dt.date.today()
        )
    except ValueError:
        print(f"error: --to must be a YYYY-MM-DD date, got {args.to!r}", file=sys.stderr)
        return 2

    paths = [Path(f) for f in args.files]
    missing = [p for p in paths if not p.is_file()]
    if missing:
        for p in missing:
            print(f"error: no such file: {p}", file=sys.stderr)
        return 2

    # ---- read and validate every file before writing any of them ----
    originals: dict[Path, str] = {}
    anchors: dict[Path, dt.date] = {}
    try:
        for path in paths:
            text = path.read_text(encoding="utf-8")
            originals[path] = text
            anchors[path] = read_anchor(text, path)
    except ShiftError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    distinct = set(anchors.values())
    if len(distinct) > 1:
        print("error: the seed files disagree about the anchor date:", file=sys.stderr)
        for path, anchor in anchors.items():
            print(f"    {path}: {anchor.isoformat()}", file=sys.stderr)
        print(
            "    Resolve this by hand before shifting; the engine files are "
            "meant to hold identical data.",
            file=sys.stderr,
        )
        return 1

    anchor = distinct.pop()
    delta = target - anchor

    if delta.days == 0:
        print(f"anchor is already {anchor.isoformat()}; nothing to do.")
        return 0

    # ---- shift ----
    results: dict[Path, str] = {}
    counts: dict[Path, int] = {}
    for path, text in originals.items():
        shifted, count = shift_text(text, delta)
        shifted = set_anchor(shifted, target)
        results[path] = shifted
        counts[path] = count

    # The anchor line itself is a date literal and gets shifted like any other,
    # then overwritten by set_anchor. Both land on the target, so this is
    # consistent either way, but the count below excludes it for clarity.
    for path in paths:
        counts[path] -= 1

    # ---- cross-file consistency ----
    literal_sets = {path: date_literals(results[path]) for path in paths}
    reference = literal_sets[paths[0]]
    for path in paths[1:]:
        if literal_sets[path] != reference:
            print(
                f"error: {paths[0]} and {path} do not contain the same dates "
                f"after shifting. The files were already out of sync before "
                f"this run; nothing has been written.",
                file=sys.stderr,
            )
            a, b = reference, literal_sets[path]
            for i, (x, y) in enumerate(zip(a, b)):
                if x != y:
                    print(f"    first difference at literal {i}: {x} vs {y}", file=sys.stderr)
                    break
            else:
                print(f"    differing counts: {len(a)} vs {len(b)}", file=sys.stderr)
            return 1

    # ---- report ----
    direction = "forward" if delta.days > 0 else "back"
    print(
        f"anchor {anchor.isoformat()} -> {target.isoformat()} "
        f"({abs(delta.days)} days {direction})"
    )
    for path in paths:
        print(f"    {path}: {counts[path]} date literals shifted")

    if args.dry_run:
        print("dry run: no files written.")
        return 0

    for path, text in results.items():
        path.write_text(text, encoding="utf-8")
    print("files rewritten in place.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
