#!/usr/bin/env python3
"""Score ASR reference/hypothesis JSONL with dependency-free WER and CER."""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
import unicodedata
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Sequence


@dataclass(frozen=True)
class EditCounts:
    substitutions: int = 0
    deletions: int = 0
    insertions: int = 0

    @property
    def errors(self) -> int:
        return self.substitutions + self.deletions + self.insertions

    def __add__(self, other: "EditCounts") -> "EditCounts":
        return EditCounts(
            substitutions=self.substitutions + other.substitutions,
            deletions=self.deletions + other.deletions,
            insertions=self.insertions + other.insertions,
        )


def normalize(text: str, mode: str) -> str:
    if mode == "none":
        return " ".join(text.split())

    normalized = unicodedata.normalize("NFKC", text).casefold()
    normalized = "".join(
        " " if unicodedata.category(character)[0] in {"P", "S"} else character
        for character in normalized
    )
    return " ".join(normalized.split())


def edit_counts(reference: Sequence[str], hypothesis: Sequence[str]) -> EditCounts:
    """Return one optimal Levenshtein alignment with S/D/I counts."""
    rows = len(reference) + 1
    columns = len(hypothesis) + 1
    costs = [[0] * columns for _ in range(rows)]
    operations = [[""] * columns for _ in range(rows)]

    for row in range(1, rows):
        costs[row][0] = row
        operations[row][0] = "D"
    for column in range(1, columns):
        costs[0][column] = column
        operations[0][column] = "I"

    for row in range(1, rows):
        for column in range(1, columns):
            if reference[row - 1] == hypothesis[column - 1]:
                costs[row][column] = costs[row - 1][column - 1]
                operations[row][column] = "M"
                continue

            candidates = (
                (costs[row - 1][column - 1] + 1, 0, "S"),
                (costs[row - 1][column] + 1, 1, "D"),
                (costs[row][column - 1] + 1, 2, "I"),
            )
            cost, _, operation = min(candidates)
            costs[row][column] = cost
            operations[row][column] = operation

    row = len(reference)
    column = len(hypothesis)
    substitutions = deletions = insertions = 0
    while row or column:
        operation = operations[row][column]
        if operation == "M":
            row -= 1
            column -= 1
        elif operation == "S":
            substitutions += 1
            row -= 1
            column -= 1
        elif operation == "D":
            deletions += 1
            row -= 1
        elif operation == "I":
            insertions += 1
            column -= 1
        else:
            raise RuntimeError(f"invalid alignment state at ({row}, {column})")

    return EditCounts(substitutions, deletions, insertions)


def safe_rate(numerator: int, denominator: int) -> float | None:
    return numerator / denominator if denominator else None


def load_rows(path: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    with path.open("r", encoding="utf-8") as source:
        for line_number, line in enumerate(source, start=1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(f"{path}:{line_number}: invalid JSON: {error.msg}") from error
            if not isinstance(row, dict):
                raise ValueError(f"{path}:{line_number}: expected a JSON object")
            for field in ("id", "reference", "hypothesis"):
                if field not in row:
                    raise ValueError(f"{path}:{line_number}: missing required field {field!r}")
                if not isinstance(row[field], str):
                    raise ValueError(f"{path}:{line_number}: field {field!r} must be a string")
            rows.append(row)
    if not rows:
        raise ValueError(f"{path}: no transcript rows")
    return rows


def score(rows: list[dict[str, object]], normalization: str) -> dict[str, object]:
    word_counts = EditCounts()
    character_counts = EditCounts()
    reference_words = 0
    reference_characters = 0
    exact_matches = 0
    silence_utterances = 0
    silence_hallucinations = 0

    for row in rows:
        reference = normalize(str(row["reference"]), normalization)
        hypothesis = normalize(str(row["hypothesis"]), normalization)
        reference_word_tokens = reference.split()
        hypothesis_word_tokens = hypothesis.split()
        reference_character_tokens = list(reference.replace(" ", ""))
        hypothesis_character_tokens = list(hypothesis.replace(" ", ""))

        word_counts += edit_counts(reference_word_tokens, hypothesis_word_tokens)
        character_counts += edit_counts(reference_character_tokens, hypothesis_character_tokens)
        reference_words += len(reference_word_tokens)
        reference_characters += len(reference_character_tokens)
        exact_matches += int(reference == hypothesis)

        if not reference:
            silence_utterances += 1
            silence_hallucinations += int(bool(hypothesis))

    return {
        "utterances": len(rows),
        "normalization": normalization,
        "exact_matches": exact_matches,
        "exact_match_rate": exact_matches / len(rows),
        "word_counts": asdict(word_counts) | {"errors": word_counts.errors},
        "reference_words": reference_words,
        "wer": safe_rate(word_counts.errors, reference_words),
        "character_counts": asdict(character_counts) | {"errors": character_counts.errors},
        "reference_characters": reference_characters,
        "cer": safe_rate(character_counts.errors, reference_characters),
        "silence_utterances": silence_utterances,
        "silence_hallucinations": silence_hallucinations,
        "silence_hallucination_rate": safe_rate(silence_hallucinations, silence_utterances),
        "latency_ms": numeric_summary(rows, "final_latency_ms"),
        "real_time_factor": numeric_summary(rows, "real_time_factor"),
    }


def numeric_summary(rows: list[dict[str, object]], field: str) -> dict[str, float | int] | None:
    values = [float(row[field]) for row in rows if isinstance(row.get(field), (int, float))]
    if not values:
        return None
    ordered = sorted(values)

    def percentile(fraction: float) -> float:
        return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]

    return {
        "count": len(ordered),
        "min": ordered[0],
        "mean": statistics.fmean(ordered),
        "p50": percentile(0.50),
        "p95": percentile(0.95),
        "p99": percentile(0.99),
        "max": ordered[-1],
    }


def format_rate(value: object) -> str:
    return "n/a" if value is None else f"{float(value):.4%}"


def print_human(result: dict[str, object]) -> None:
    print(f"utterances: {result['utterances']}")
    print(f"normalization: {result['normalization']}")
    print(f"exact match rate: {format_rate(result['exact_match_rate'])}")
    print(f"WER: {format_rate(result['wer'])}")
    print(f"CER: {format_rate(result['cer'])}")
    print(f"silence hallucination rate: {format_rate(result['silence_hallucination_rate'])}")
    if result["latency_ms"] is not None:
        print(f"latency ms: {json.dumps(result['latency_ms'], sort_keys=True)}")
    if result["real_time_factor"] is not None:
        print(f"real-time factor: {json.dumps(result['real_time_factor'], sort_keys=True)}")
    print(f"word counts: {json.dumps(result['word_counts'], sort_keys=True)}")
    print(f"character counts: {json.dumps(result['character_counts'], sort_keys=True)}")


def threshold_failures(result: dict[str, object], arguments: argparse.Namespace) -> list[str]:
    failures: list[str] = []
    thresholds = (
        ("wer", arguments.max_wer),
        ("cer", arguments.max_cer),
        ("silence_hallucination_rate", arguments.max_silence_hallucination_rate),
    )
    for metric, threshold in thresholds:
        if threshold is None:
            continue
        value = result[metric]
        if value is None:
            failures.append(f"{metric} is undefined; cannot apply threshold {threshold}")
        elif float(value) > threshold:
            failures.append(f"{metric} {float(value):.6f} exceeds threshold {threshold:.6f}")
    return failures


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("manifest", type=Path, help="UTF-8 JSONL transcript manifest")
    result.add_argument(
        "--normalization",
        choices=("basic", "none"),
        default="basic",
        help="basic strips case/punctuation/symbol differences; none only collapses whitespace",
    )
    result.add_argument("--json", action="store_true", help="print machine-readable JSON")
    result.add_argument("--max-wer", type=float)
    result.add_argument("--max-cer", type=float)
    result.add_argument("--max-silence-hallucination-rate", type=float)
    return result


def main() -> int:
    arguments = parser().parse_args()
    try:
        rows = load_rows(arguments.manifest)
        result = score(rows, arguments.normalization)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    if arguments.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print_human(result)

    failures = threshold_failures(result, arguments)
    for failure in failures:
        print(f"threshold failed: {failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
