#!/usr/bin/env python3
"""Initialize missing local SEO operator state without overwriting files."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path.cwd()
STATE = ROOT / ".seo"

FILES = {
    "config.json": json.dumps(
        {
            "version": "1.0.0",
            "domain": "trygojo.com",
            "canonical_origin": "https://trygojo.com",
            "search_console_property": "",
            "analytics_project": "",
            "timezone": "UTC",
            "action_bar": 12,
            "conversion_targets": ["download_cta_clicked", "pricing_cta_clicked", "verified_purchase"],
            "cadence": {
                "heartbeat_minutes": 60,
                "daily_panels_hours": 24,
                "weekly_panels_days": 7,
                "census_days": 30
            },
            "competitors": ["NotchNook", "Alcove", "Droppy"],
        },
        indent=2,
    )
    + "\n",
    "truth.md": "# Truth ledger\n\nAdd only verified claims with source, checked date, and affected URLs.\n",
    "coverage.md": "# Coverage map\n\n| Cluster | Intent owner | Conversion destination | Status |\n|---|---|---|---|\n",
    "content-ledger.md": "# Content ledger\n\n| URL | Intent owner | Funnel role | Status | Last action |\n|---|---|---|---|---|\n",
    "link-inventory.md": "# Link inventory\n\n| Source | Destination | Type | Status | Checked |\n|---|---|---|---|---|\n",
    "candidates.json": json.dumps({"action_bar": 12, "winner": None, "candidates": []}, indent=2) + "\n",
    "needs-you.md": "# Needs Roshan\n\nNo open decisions.\n",
}


def main() -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    (STATE / "runs").mkdir(exist_ok=True)
    created: list[str] = []
    for relative, content in FILES.items():
        target = STATE / relative
        if target.exists():
            continue
        target.write_text(content, encoding="utf-8")
        created.append(str(target.relative_to(ROOT)))
    if created:
        print("created: " + ", ".join(created))
    else:
        print("SEO state already current; nothing changed")


if __name__ == "__main__":
    main()
