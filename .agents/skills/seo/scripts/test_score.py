#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("score.py")


def candidate(
    candidate_id: str,
    impact: int,
    *,
    eligible: bool = True,
    lane: str = "editorial",
    evidence_strength: int = 3,
    effort: int = 1,
    evidence_age_days: int = 1,
) -> dict:
    metrics = {
        "business_impact": impact,
        "evidence_strength": evidence_strength,
        "relevance": 5,
        "ctr_potential": 1,
        "link_health": 1,
        "speed": 0,
        "effort": effort,
        "risk": 0,
        "conflict": 0,
    }
    return {
        "id": candidate_id,
        "lane": lane,
        "target": "https://trygojo.com/example/",
        "problem": "Observed test problem",
        "evidence": ["Current first-party test evidence"],
        "evidence_age_days": evidence_age_days,
        "intent_owner": "test intent",
        "conversion_destination": "https://trygojo.com/downloads/",
        "metrics": metrics,
        "eligible": eligible,
        "rejection_reason": None if eligible else "blocked in test",
    }


class ScoreTests(unittest.TestCase):
    def run_score(
        self, payload: object, *, config: dict | None = None, write: bool = False
    ) -> tuple[subprocess.CompletedProcess[str], str]:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "candidates.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            if config is not None:
                path.with_name("config.json").write_text(json.dumps(config), encoding="utf-8")
            command = ["python3", str(SCRIPT), str(path)]
            if write:
                command.append("--write")
            result = subprocess.run(command, text=True, capture_output=True, check=False)
            return result, path.read_text(encoding="utf-8")

    def test_ranks_and_selects_by_weighted_score(self) -> None:
        result, _ = self.run_score({"candidates": [candidate("low", 1), candidate("high", 5)]})
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual([item["id"] for item in payload["candidates"]], ["high", "low"])
        self.assertEqual(payload["winner"], "high")

    def test_ineligible_candidate_never_clears_bar(self) -> None:
        result, _ = self.run_score([candidate("blocked", 5, eligible=False)])
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertFalse(payload["candidates"][0]["clears_action_bar"])
        self.assertIsNone(payload["winner"])

    def test_requires_boolean_eligibility(self) -> None:
        item = candidate("bad", 5)
        item["eligible"] = "false"
        result, _ = self.run_score([item])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("eligible must be a boolean", result.stderr)

    def test_requires_descriptive_fields(self) -> None:
        item = candidate("bad", 5)
        del item["intent_owner"]
        result, _ = self.run_score([item])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("intent_owner must be a non-empty string", result.stderr)

    def test_rejects_unknown_lane(self) -> None:
        item = candidate("bad-lane", 5)
        item["lane"] = "repiar"
        result, _ = self.run_score([item])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported lane 'repiar'", result.stderr)

    def test_repair_wins_equal_score_tie(self) -> None:
        editorial = candidate("a-editorial", 3, lane="editorial")
        repair = candidate("z-repair", 3, lane="repair")
        result, _ = self.run_score([editorial, repair])
        self.assertEqual(result.returncode, 0, result.stderr)
        ranked = json.loads(result.stdout)["candidates"]
        self.assertEqual([item["id"] for item in ranked], ["z-repair", "a-editorial"])

    def test_uses_configured_action_bar_and_writes_state(self) -> None:
        result, saved = self.run_score(
            {"candidates": [candidate("below", 1)]},
            config={"action_bar": 40},
            write=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(saved)["action_bar"], 40)
        self.assertIsNone(json.loads(saved)["winner"])

    def test_rejects_out_of_range_metric(self) -> None:
        item = candidate("bad", 5)
        item["metrics"]["risk"] = 6
        result, _ = self.run_score([item])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("risk must be an integer from 0 to 5", result.stderr)


if __name__ == "__main__":
    unittest.main()
