"""alerts/record.py

Records the Notify NYC feed to the committed archive, raw.

The feed is a rolling window of roughly the last hour (64 minutes in the one
sample measured, 2026-08-03). Anything that falls out of it is gone
permanently and cannot be recovered from any source. This script is the only
thing standing between the project and losing that history.

It is a RECORDER, not the alerts service. It applies none of the eight rules in
ALERTS_SERVICE.md - no status, msgType, expiry, certainty or Queens filtering -
because the point is an untouched corpus: to measure what the UI must design
for, and to replay the service against later as test fixtures. Filtering here
would bake today's reading of the rules into the only copy of the data.

The one thing it does apply is the English filter, and only to decide which CAP
files to download. Every RSS item, in all 13 languages, is still logged.

Run every 15 minutes by .github/workflows/record-alerts.yml. Standard library
only, so the workflow needs no install step.

Usage:
    python3 alerts/record.py
    python3 alerts/record.py --feed file:///tmp/feed.xml --archive /tmp/archive

Exit status is 0 when everything was recorded, 1 when anything needs a human -
a failed fetch, a failed CAP download, or the English-filter monitor tripping.
Whatever was recorded before a failure is still written, so the workflow can
commit partial progress and still go red.
"""

import argparse
import csv
import re
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

FEED_URL = "https://feeds.everbridge.net/feeds/453003085617722/rss/rss.xml"

# The exact literal. Everbridge encodes the language in a human-readable label
# rather than a CAP field - see "The monitoring rule" in ALERTS_SERVICE.md.
ENGLISH_AUTHOR = "NYCEM [English]"

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ARCHIVE = REPO_ROOT / "data" / "archive" / "alerts"

ITEMS_COLUMNS = ["guid", "author", "title", "category", "pub_date", "link", "first_seen"]

# guids become filenames. Every observed guid is a 16-digit number; anything
# else is a change in the feed worth stopping for, not something to sanitise.
GUID_PATTERN = re.compile(r"^[0-9]+$")

TIMEOUT_S = 30


def fetch(url):
    """GET with one retry. Returns bytes; raises after the second failure."""
    request = urllib.request.Request(url, headers={"User-Agent": "q-map-alerts-recorder"})
    for attempt in (1, 2):
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
                return response.read()
        except OSError as error:  # URLError, HTTPError and timeouts all subclass it
            if attempt == 2:
                raise
            print(f"  retrying after: {error}", file=sys.stderr)
            time.sleep(5)


def parse_items(feed_bytes):
    """RSS bytes -> list of dicts, one per <item>. Raises on a non-RSS body."""
    root = ET.fromstring(feed_bytes)
    if root.tag != "rss" or root.find("channel") is None:
        raise ValueError(f"not an RSS document: root element <{root.tag}>")

    items = []
    for item in root.iter("item"):
        enclosure = item.find("enclosure")
        items.append({
            "guid": (item.findtext("guid") or "").strip(),
            "author": (item.findtext("author") or "").strip(),
            "title": (item.findtext("title") or "").strip(),
            "category": (item.findtext("category") or "").strip(),
            "pub_date": (item.findtext("pubDate") or "").strip(),
            # <link> and <enclosure> point at the same CAP file; prefer <link>.
            "link": (item.findtext("link") or "").strip()
                    or (enclosure.get("url", "") if enclosure is not None else ""),
        })
    return items


def read_seen(items_path):
    """guids already in items.csv. The archive, not memory, is the state."""
    if not items_path.exists():
        return set()
    with items_path.open(newline="", encoding="utf-8") as f:
        return {row["guid"] for row in csv.DictReader(f)}


def append_rows(items_path, rows):
    new_file = not items_path.exists()
    with items_path.open("a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=ITEMS_COLUMNS)
        if new_file:
            writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--feed", default=FEED_URL)
    parser.add_argument("--archive", type=Path, default=DEFAULT_ARCHIVE)
    args = parser.parse_args()

    now = datetime.now(timezone.utc).replace(microsecond=0)
    stamp = now.strftime("%Y-%m-%dT%H-%M-%SZ")  # filename-safe ISO 8601
    items_path = args.archive / "items.csv"
    cap_dir = args.archive / "cap"
    rss_dir = args.archive / "rss"

    try:
        feed_bytes = fetch(args.feed)
        items = parse_items(feed_bytes)
    except (OSError, ET.ParseError, ValueError) as error:
        print(f"::error::feed unreadable: {error}")
        return 1

    english = [i for i in items if i["author"] == ENGLISH_AUTHOR]
    print(f"Feed: {len(items)} items, {len(english)} English")

    # An empty feed is a quiet hour, not an outage - observed 2026-09-28 17:04
    # UTC. The outage signal is English missing while other languages are
    # present: the filter string has changed, not the weather.
    monitor_tripped = bool(items) and not english
    if monitor_tripped:
        authors = sorted({i["author"] for i in items})
        print(f"::error::{len(items)} items but none authored {ENGLISH_AUTHOR!r}. "
              f"Authors seen: {authors}")

    bad = [i["guid"] for i in items if not GUID_PATTERN.match(i["guid"])]
    if bad:
        print(f"::error::unexpected guid format, refusing to record: {bad[:5]}")
        return 1

    seen = read_seen(items_path)
    new = [i for i in items if i["guid"] not in seen]
    if not new:
        print("Nothing new since the last run")
        return 1 if monitor_tripped else 0

    # Two-tier fetch: CAP only for new English guids. A guid is recorded as
    # seen only once its CAP file is on disk, so a failed download is retried
    # next run - the item stays in the feed for about an hour, four runs.
    cap_dir.mkdir(parents=True, exist_ok=True)
    recorded, failed = [], []
    for item in new:
        if item["author"] == ENGLISH_AUTHOR:
            try:
                cap_bytes = fetch(item["link"])
                # A 200 carrying an error page would otherwise be archived as
                # the alert. Check it is CAP; keep the bytes exactly as sent.
                if not ET.fromstring(cap_bytes).tag.endswith("alert"):
                    raise ValueError("response is not a CAP <alert>")
                (cap_dir / f"{item['guid']}.xml").write_bytes(cap_bytes)
            except (OSError, ET.ParseError, ValueError) as error:
                print(f"::warning::CAP fetch failed for {item['guid']}: {error}")
                failed.append(item["guid"])
                continue
        recorded.append({**item, "first_seen": now.isoformat()})

    if recorded:
        # The raw feed, kept only when it told us something new. It holds the
        # RSS <description> for every language, which items.csv omits.
        rss_dir.mkdir(parents=True, exist_ok=True)
        (rss_dir / f"{stamp}.xml").write_bytes(feed_bytes)
        append_rows(items_path, recorded)

    n_cap = sum(1 for r in recorded if r["author"] == ENGLISH_AUTHOR)
    print(f"Recorded {len(recorded)} new items ({n_cap} CAP files); "
          f"{len(failed)} CAP downloads failed and will retry")
    return 1 if (failed or monitor_tripped) else 0


if __name__ == "__main__":
    sys.exit(main())
