#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bazel_cmd=(bazel --nohome_rc)
if [[ -n "${BAZEL_OUTPUT_USER_ROOT:-}" ]]; then
    bazel_cmd+=(--output_user_root="$BAZEL_OUTPUT_USER_ROOT")
fi

"${bazel_cmd[@]}" mod tidy
"${bazel_cmd[@]}" test //examples:strong_test //examples:weak_test
"${bazel_cmd[@]}" test --config=mull //examples:strong_test
python3 tools/report.py bazel-testlogs/examples/strong_test/test.outputs/mull.sqlite reports/strong

# The weak test passes normally but must fail mutation testing with a survivor.
status=0
"${bazel_cmd[@]}" test --config=mull //examples:weak_test || status=$?
if [[ "$status" -ne 3 ]]; then
    echo "Expected Bazel test failure (3), got $status" >&2
    exit 1
fi
python3 tools/report.py bazel-testlogs/examples/weak_test/test.outputs/mull.sqlite reports/weak

"${bazel_cmd[@]}" aquery --config=mull 'mnemonic("CppCompile", deps(//examples:strong_test))' --output=jsonproto > reports/actions.json

python3 - <<'PYTHON'
from pathlib import Path
import json
import sqlite3
import subprocess

actions = json.loads(Path("reports/actions.json").read_text())["actions"]
for source, instrumented in [("examples/arithmetic.cc", True), ("examples/arithmetic_test.cc", False), ("examples/header_generator.cc", False)]:
    matches = [action for action in actions if source in action["arguments"]]
    assert matches, source
    for action in matches:
        assert any(arg.startswith("-fpass-plugin=") for arg in action["arguments"]) == instrumented, source
        assert any(env["key"] == "MULL_CONFIG" for env in action.get("environmentVariables", [])) == instrumented, source

for case, expected in [("strong", {1: 2}), ("weak", {1: 1, 2: 1})]:
    with sqlite3.connect(f"file:reports/{case}/mull.sqlite?mode=ro", uri=True) as db:
        counts = dict(db.execute("SELECT execution_status, count(*) FROM mutant GROUP BY execution_status"))
        assert counts == expected, (case, counts)
        paths = db.execute("SELECT DISTINCT filename FROM mutant").fetchall()
        assert paths == [("examples/arithmetic.cc",)], paths
    report = json.loads(Path(f"reports/{case}/mull.json").read_text())
    assert "int add(" in report["files"]["examples/arithmetic.cc"]["source"]

# All three mutations exist in the binary; coverage filters the third one.
sections = subprocess.check_output(["readelf", "-p", ".mull_mutants", "bazel-bin/examples/strong_test"], text=True)
assert sections.count("cxx_add_to_sub:/workspace/examples/arithmetic.cc:") == 3, sections
print("Verified: normal tests pass; two covered mutants; one intentional survivor; uncovered mutant skipped; source-backed reports.")
PYTHON

"${bazel_cmd[@]}" test --config=mull --enable_mull=false //examples:strong_test
