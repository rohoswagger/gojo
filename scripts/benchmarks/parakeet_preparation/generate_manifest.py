from pathlib import Path
import hashlib
import json
import re
import sys

root = Path(sys.argv[2])
source = Path(sys.argv[1])
text = source.read_text()
body = re.search(r"private static let modelSHA256: \[String: String\] = \[(.*?)\n    \]", text, re.S).group(1)
hashes = dict(re.findall(r'"([^"\n]+)": "([a-f0-9]{64})"', body))
maximum = int(re.search(r"maximumModelBytes: UInt64 = ([\d_]+)", text).group(1).replace("_", ""))
revision = re.search(r'private static let revision = "([^"\n]+)"', text).group(1)
assert len(hashes) == 14
cache_source = root / "Sources/GojoParakeetBenchmark/DictationModelValidationCache.swift"
cache_digest = hashlib.sha256(cache_source.read_bytes()).hexdigest() if cache_source.exists() else "unavailable"
lines = ["enum PinnedModelManifest {", f"    static let maximumBytes: UInt64 = {maximum}", f'    static let revision = "{revision}"', f'    static let cacheSourceSHA256 = "{cache_digest}"', "    static let hashes: [String: String] = ["]
lines += [f'        "{name}": "{digest}",' for name, digest in hashes.items()]
lines += ["    ]", "}", ""]
(root / "Sources/GojoParakeetBenchmark/PinnedModelManifest.swift").write_text("\n".join(lines))
(root / "pinned-manifest.json").write_text(json.dumps({"revision": revision, "maximumBytes": maximum, "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(), "cacheSourceSHA256": cache_digest, "hashes": hashes}, indent=2) + "\n")
