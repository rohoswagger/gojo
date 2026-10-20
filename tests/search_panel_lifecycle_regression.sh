#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-search-panel-lifecycle.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT
cd "$repo_root"
swiftc -swift-version 5 \
  Gojo/components/Search/SearchPanelController.swift \
  Gojo/components/Search/Models/SearchPanelHostingPolicy.swift \
  Gojo/components/Search/Models/SearchPanelLayout.swift \
  Gojo/components/Search/Models/SearchPanelResizeQueue.swift \
  Gojo/components/Search/Models/SearchPanelSpacePolicy.swift \
  Gojo/components/Search/Models/SearchResult.swift \
  tests/search_panel_lifecycle_regression.swift -o "$binary_path"
python3 - "$binary_path" <<'PYTHON'
import subprocess
import sys
try:
    subprocess.run([sys.argv[1]], check=True, timeout=15)
except subprocess.TimeoutExpired:
    sys.exit("Search native panel lifecycle regression timed out")
except subprocess.CalledProcessError as error:
    sys.exit(error.returncode)
PYTHON
