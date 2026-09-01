#!/usr/bin/env python3
"""Benchmark OpenRouter models for Gojo's transcript-cleanup workload."""

from __future__ import annotations

import argparse
import difflib
import json
import math
import os
import re
import statistics
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_MODELS = [
    "deepseek/deepseek-v4-flash-0731",
    "qwen/qwen3.7-flash",
    "openai/gpt-oss-20b",
    "mistralai/ministral-8b-2512",
    "google/gemma-3-4b-it",
]

STYLE_PROMPTS = {
    "casual": (
        "Casual. Keep the wording conversational and natural. "
        "Preserve contractions and use light punctuation."
    ),
    "punctuated": (
        "Full punctuation. Use complete capitalization, punctuation, and natural "
        "paragraph breaks without changing the wording or meaning."
    ),
    "formal": (
        "Formal. Use polished, professional wording and complete punctuation "
        "without changing the meaning or adding information."
    ),
}

S1_MINI_SYSTEM_PROMPT = (
    "You are a text normalizer for speech-to-text transcripts. The input begins "
    "with a control line specifying the styling, structure, and context settings; "
    "clean the transcript to match those settings and output only the cleaned text."
)


def system_prompt(style: str) -> str:
    return (
        "You are Gojo's dictation editor. Return only the edited text, with no "
        "explanation, quotation marks, or preamble.\n"
        "Preserve the speaker's meaning, facts, names, numbers, URLs, code, and "
        "ordering. Remove only obvious filler words, false starts, and accidental "
        "repetition. Never invent details, summarize, answer questions, or turn a "
        f"request into an answer.\nStyle: {STYLE_PROMPTS[style]}"
    )


def messages(case: dict[str, Any], prompt_format: str) -> list[dict[str, str]]:
    if prompt_format == "s1-mini":
        styling = {
            "casual": "semi-casual",
            "punctuated": "semi-formal",
            "formal": "formal",
        }[case["style"]]
        control = f"[Styling: {styling}] [Structure: prose] [Context: general]"
        return [
            {"role": "system", "content": S1_MINI_SYSTEM_PROMPT},
            {"role": "user", "content": f"{control}\n{case['transcript']}"},
        ]
    return [
        {"role": "system", "content": system_prompt(case["style"])},
        {"role": "user", "content": case["transcript"]},
    ]


def load_cases(path: Path) -> list[dict[str, Any]]:
    cases: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as source:
        for line_number, line in enumerate(source, start=1):
            if not line.strip():
                continue
            row = json.loads(line)
            for field in ("id", "style", "transcript", "expected", "required_terms"):
                if field not in row:
                    raise ValueError(f"{path}:{line_number}: missing {field!r}")
            if row["style"] not in STYLE_PROMPTS:
                raise ValueError(f"{path}:{line_number}: unknown style {row['style']!r}")
            if not isinstance(row["required_terms"], list):
                raise ValueError(f"{path}:{line_number}: required_terms must be a list")
            cases.append(row)
    if not cases:
        raise ValueError(f"{path}: no cleanup cases")
    return cases


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]


def latency_summary(values: list[float]) -> dict[str, float | int] | None:
    if not values:
        return None
    return {
        "count": len(values),
        "min": round(min(values), 1),
        "mean": round(statistics.fmean(values), 1),
        "p50": round(percentile(values, 0.50), 1),
        "p95": round(percentile(values, 0.95), 1),
        "max": round(max(values), 1),
    }


def completion(
    *, api_key: str, endpoint: str, model: str, case: dict[str, Any],
    prompt_format: str, timeout: float,
) -> tuple[str, dict[str, Any], float]:
    payload = {
        "model": model,
        "messages": messages(case, prompt_format),
        "temperature": 0,
        # Match OpenRouterDictationPolisher.outputTokenBudget exactly. Some
        # reasoning-capable models consume part of this budget before emitting
        # visible text, even for a short cleanup request.
        "max_tokens": min(4_096, max(1_024, len(case["transcript"].encode("utf-8")))),
        "stream": False,
    }
    if prompt_format == "s1-mini":
        payload["chat_template_kwargs"] = {"enable_thinking": False}
    if "openrouter.ai" in endpoint:
        payload["provider"] = {"sort": "latency"}
    headers = {
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/rohoswagger/gojo",
        "X-Title": "Gojo cleanup benchmark",
    }
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"OpenRouter returned HTTP {error.code}") from error
    latency_ms = (time.perf_counter() - started) * 1_000
    choices = body.get("choices") or []
    if not choices or not isinstance(choices[0].get("message", {}).get("content"), str):
        raise RuntimeError("OpenRouter returned no text completion")
    return choices[0]["message"]["content"].strip(), body.get("usage") or {}, latency_ms


def validate(output: str, case: dict[str, Any]) -> tuple[bool, list[str], float]:
    lowered = output.casefold()
    missing = [term for term in case["required_terms"] if term.casefold() not in lowered]
    unwanted_prefixes = ("here is", "here's", "edited text", "certainly", "```")
    problems = [f"missing required term: {term}" for term in missing]
    if lowered.startswith(unwanted_prefixes):
        problems.append("added a preamble or wrapper")
    if "```" in output or "**" in output or "`" in output:
        problems.append("added Markdown formatting")
    similarity = difflib.SequenceMatcher(
        None,
        " ".join(case["expected"].casefold().split()),
        " ".join(output.casefold().split()),
    ).ratio()
    if similarity < 0.85:
        problems.append(f"reference similarity below 0.85: {similarity:.4f}")
    expected_numbers = set(re.findall(r"\d+", case["expected"]))
    output_numbers = set(re.findall(r"\d+", output))
    for number in sorted(output_numbers - expected_numbers):
        problems.append(f"invented numeric value: {number}")
    return not problems and bool(output), problems, similarity


def run_model(
    *, api_key: str, endpoint: str, model: str, cases: list[dict[str, Any]],
    prompt_format: str, runs: int, warmups: int, timeout: float,
    include_outputs: bool,
) -> dict[str, Any]:
    errors: list[str] = []
    samples: list[dict[str, Any]] = []
    for _ in range(warmups):
        try:
            completion(
                api_key=api_key,
                endpoint=endpoint,
                model=model,
                case=cases[0],
                prompt_format=prompt_format,
                timeout=timeout,
            )
        except Exception as error:  # Warmups are intentionally excluded from results.
            errors.append(f"warmup: {error}")

    for run in range(1, runs + 1):
        for case in cases:
            try:
                output, usage, latency_ms = completion(
                    api_key=api_key,
                    endpoint=endpoint,
                    model=model,
                    case=case,
                    prompt_format=prompt_format,
                    timeout=timeout,
                )
                valid, problems, similarity = validate(output, case)
                sample: dict[str, Any] = {
                    "case": case["id"],
                    "run": run,
                    "latency_ms": round(latency_ms, 1),
                    "valid": valid,
                    "problems": problems,
                    "reference_similarity": round(similarity, 4),
                    "prompt_tokens": usage.get("prompt_tokens"),
                    "completion_tokens": usage.get("completion_tokens"),
                    "cost": usage.get("cost"),
                }
                if include_outputs:
                    sample["output"] = output
                samples.append(sample)
            except Exception as error:
                errors.append(f"{case['id']} run {run}: {error}")

    latencies = [float(sample["latency_ms"]) for sample in samples]
    similarities = [float(sample["reference_similarity"]) for sample in samples]
    costs = [float(sample["cost"]) for sample in samples if isinstance(sample.get("cost"), (int, float))]
    return {
        "model": model,
        "requests": runs * len(cases),
        "successes": len(samples),
        "validation_pass_rate": (
            sum(bool(sample["valid"]) for sample in samples) / len(samples) if samples else 0
        ),
        "mean_reference_similarity": round(statistics.fmean(similarities), 4) if similarities else None,
        "latency_ms": latency_summary(latencies),
        "reported_cost": round(sum(costs), 8) if costs else None,
        "errors": errors,
        "samples": samples,
    }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fixture",
        type=Path,
        default=Path(__file__).with_name("fixtures") / "cleanup-prompts.jsonl",
    )
    parser.add_argument("--models", nargs="+", default=DEFAULT_MODELS)
    parser.add_argument(
        "--endpoint",
        default="https://openrouter.ai/api/v1/chat/completions",
        help="OpenAI-compatible chat-completions URL",
    )
    parser.add_argument("--prompt-format", choices=("gojo", "s1-mini"), default="gojo")
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--include-outputs", action="store_true")
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="validate the fixture and benchmark code without making API calls",
    )
    parser.add_argument("--json", action="store_true")
    arguments = parser.parse_args()
    if arguments.runs < 1 or arguments.warmups < 0:
        parser.error("--runs must be positive and --warmups cannot be negative")
    return arguments


def main() -> int:
    arguments = parse_arguments()
    cases = load_cases(arguments.fixture)
    if arguments.validate_only:
        print(f"cleanup-benchmark-fixture-pass cases={len(cases)}")
        return 0
    api_key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if "openrouter.ai" in arguments.endpoint and not api_key:
        print("OPENROUTER_API_KEY is required", file=sys.stderr)
        return 2
    results = [
        run_model(
            api_key=api_key,
            endpoint=arguments.endpoint,
            model=model,
            cases=cases,
            prompt_format=arguments.prompt_format,
            runs=arguments.runs,
            warmups=arguments.warmups,
            timeout=arguments.timeout,
            include_outputs=arguments.include_outputs,
        )
        for model in arguments.models
    ]
    results.sort(
        key=lambda result: (
            -(float(result["validation_pass_rate"])),
            float(result["latency_ms"]["p50"]) if result["latency_ms"] else math.inf,
        )
    )
    payload = {"cases": len(cases), "runs": arguments.runs, "models": results}
    if arguments.json:
        json.dump(payload, sys.stdout, indent=2)
        print()
    else:
        for result in results:
            latency = result["latency_ms"] or {}
            print(
                f"{result['model']}: pass={result['validation_pass_rate']:.0%} "
                f"p50={latency.get('p50', 'n/a')}ms p95={latency.get('p95', 'n/a')}ms "
                f"similarity={result['mean_reference_similarity']} cost={result['reported_cost']}"
            )
            for error in result["errors"]:
                print(f"  error: {error}")
    return 0 if all(result["successes"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
