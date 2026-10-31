#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
scratch="$(mktemp -d "${TMPDIR:-/tmp}/gojo-bark-regression.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
python3 - "$scratch" <<'PY'
import pathlib, struct, sys, zipfile
root = pathlib.Path(sys.argv[1])
def npy(dtype, shape, values):
    header = repr(dict(descr=dtype, fortran_order=False, shape=shape)).encode()
    header += b' ' * ((-10 - len(header) - 1) % 64) + b'\n'
    fmt = {'|i1': 'b', '<f2': 'e', '<f4': 'f'}[dtype]
    return b'\x93NUMPY\x01\x00' + struct.pack('<H', len(header)) + header + struct.pack('<' + fmt * len(values), *values)
with zipfile.ZipFile(root / 'fixture.npz', 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('matrix.q.npy', npy('|i1', (2, 3), [1, -2, 3, 4, -5, 6]))
    z.writestr('matrix.s.npy', npy('<f2', (2,), [.5, 2]))
    z.writestr('bias.npy', npy('<f4', (3,), [1, -2, 3]))
(root / 'invalid.npz').write_bytes(b'PK')
PY
swiftc -O -swift-version 5 -warnings-as-errors \
    Gojo/Dictation/DictationModels.swift Gojo/Dictation/DictationSessionPlan.swift \
    Gojo/Dictation/BarkModelVariant.swift \
    Gojo/Dictation/BarkTensorArchive.swift Gojo/Dictation/BarkSpeechRuntime.swift \
    tests/bark_runtime_regression.swift -o "$scratch/regression"
"$scratch/regression" "$scratch"
