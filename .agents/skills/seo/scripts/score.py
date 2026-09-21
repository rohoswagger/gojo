#!/usr/bin/env python3
"""Validate, rank, and select SEO action candidates deterministically."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

WEIGHTS = {
    "business_impact": 3,
    "evidence_strength": 2,
    "relevance": 2,
    "ctr_potential": 2,
    "link_health": 2,
    "speed": 1,
    "effort": -1,
    "risk": -2,
    "conflict": -2,
}
REQUIRED_TEXT = ("id", "lane", "target", "problem", "intent_owner", "conversion_destination")
ALLOWED_LANES = {
    "correct",
    "repair",
    "refresh",
    "consolidate",
    "prune",
    "distribute",
    "offpage",
    "editorial",
    "programmatic",
    "tool",
    "aeo",
    "measurement",
}
REPAIR_LANES = {"correct", "repair"}


def fail(message: str) -> None:
    raise SystemExit(message)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidates", type=Path)
    parser.add_argument("--write", action="store_true", help="write ranked state back to the candidate file")
    parser.add_argument("--action-bar", type=int, help="override config.json action_bar")
    return parser.parse_args()


def load_json(path: Path, label: str) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read {label}: {exc}")


def resolve_action_bar(path: Path, override: int | None) -> int:
    if override is not None:
        action_bar = override
    else:
        config_path = path.with_name("config.json")
        if config_path.exists():
            config = load_json(config_path, "config")
            if not isinstance(config, dict):
                fail("config must be a JSON object")
            action_bar = config.get("action_bar", 12)
        else:
            action_bar = 12
    if not isinstance(action_bar, int) or isinstance(action_bar, bool) or action_bar < 0:
        fail("action_bar must be a non-negative integer")
    return action_bar


def validate_candidate(candidate: object, index: int, seen: set[str]) -> dict:
    if not isinstance(candidate, dict):
        fail(f"candidate {index} is not an object")

    for field in REQUIRED_TEXT:
        value = candidate.get(field)
        if not isinstance(value, str) or not value.strip():
            fail(f"candidate {index}: {field} must be a non-empty string")

    candidate_id = candidate["id"]
    lane = candidate["lane"]
    if lane not in ALLOWED_LANES:
        fail(f"candidate {candidate_id}: unsupported lane {lane!r}")
    if candidate_id in seen:
        fail(f"duplicate candidate id: {candidate_id}")
    seen.add(candidate_id)

    evidence = candidate.get("evidence")
    if not isinstance(evidence, list) or not evidence or any(
        not isinstance(item, str) or not item.strip() for item in evidence
    ):
        fail(f"candidate {candidate_id}: evidence must be a non-empty list of strings")

    eligible = candidate.get("eligible")
    if not isinstance(eligible, bool):
        fail(f"candidate {candidate_id}: eligible must be a boolean")
    rejection_reason = candidate.get("rejection_reason")
    if eligible:
        if rejection_reason not in (None, ""):
            fail(f"candidate {candidate_id}: eligible candidates cannot have a rejection_reason")
    elif not isinstance(rejection_reason, str) or not rejection_reason.strip():
        fail(f"candidate {candidate_id}: ineligible candidates require a rejection_reason")

    evidence_age_days = candidate.get("evidence_age_days")
    if not isinstance(evidence_age_days, int) or isinstance(evidence_age_days, bool) or evidence_age_days < 0:
        fail(f"candidate {candidate_id}: evidence_age_days must be a non-negative integer")

    metrics = candidate.get("metrics")
    if not isinstance(metrics, dict):
        fail(f"candidate {candidate_id} has no metrics object")
    for metric in WEIGHTS:
        value = metrics.get(metric)
        if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 5:
            fail(f"candidate {candidate_id}: {metric} must be an integer from 0 to 5")

    return candidate


def main() -> None:
    args = parse_args()
    payload = load_json(args.candidates, "candidates")
    candidates = payload.get("candidates") if isinstance(payload, dict) else payload
    if not isinstance(candidates, list):
        fail("expected a candidate list or an object with a candidates list")

    action_bar = resolve_action_bar(args.candidates, args.action_bar)
    seen: set[str] = set()
    ranked: list[dict] = []
    for index, raw_candidate in enumerate(candidates):
        candidate = validate_candidate(raw_candidate, index, seen)
        score = sum(candidate["metrics"][metric] * weight for metric, weight in WEIGHTS.items())
        item = dict(candidate)
        item["score"] = score
        item["clears_action_bar"] = item["eligible"] and score >= action_bar
        ranked.append(item)

    ranked.sort(
        key=lambda item: (
            not item["eligible"],
            -item["score"],
            0 if item["lane"] in REPAIR_LANES else 1,
            -item["metrics"]["evidence_strength"],
            item["metrics"]["effort"],
            -item["evidence_age_days"],
            item["id"],
        )
    )
    winner = next((item["id"] for item in ranked if item["clears_action_bar"]), None)
    result = {"action_bar": action_bar, "winner": winner, "candidates": ranked}
    rendered = json.dumps(result, indent=2, sort_keys=False) + "\n"
    if args.write:
        args.candidates.write_text(rendered, encoding="utf-8")
    print(rendered, end="")


if __name__ == "__main__":
    main()
