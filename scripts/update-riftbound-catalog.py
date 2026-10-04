#!/usr/bin/env python3
"""Refresh the bundled text-only catalog from Riftcodex. Does not fetch images."""
import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "LiveTranscriber/CardRecognition/Resources/riftbound-catalog.json"

def fetch(url):
    result = subprocess.run(["curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "30", url], check=True, capture_output=True)
    return json.loads(result.stdout)

cards = []
page = 1
while True:
    response = fetch(f"https://api.riftcodex.com/cards?size=100&page={page}&sort=collector_number")
    assert 1 <= response["pages"] <= 100
    cards.extend(response["items"])
    print(f"Page {page}/{response['pages']}", flush=True)
    if page >= response["pages"]:
        break
    page += 1
assert len({card["id"] for card in cards}) == len(cards), "Pagination returned duplicate IDs"
assert len(cards) >= response["total"], "Incomplete catalog"
for required in ["unl-150-219", "sfd-133-221", "ogn-173-298", "ven-099-166"]:
    assert any(card["riftbound_id"] == required for card in cards), required
DESTINATION.parent.mkdir(parents=True, exist_ok=True)
# Preserve the source payload for reproducible decoding and metadata provenance.
with tempfile.NamedTemporaryFile(mode="w", dir=DESTINATION.parent, delete=False) as file:
    json.dump(cards, file, ensure_ascii=False, separators=(",", ":"))
    file.write("\n")
    temporary = pathlib.Path(file.name)
temporary.replace(DESTINATION)
print(f"Saved {len(cards)} records; {DESTINATION.stat().st_size:,} bytes. No images downloaded.")
