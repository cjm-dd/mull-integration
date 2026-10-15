#!/usr/bin/env python3
"""Render one Mull 0.34 SQLite result against this exact source checkout."""

import argparse
from pathlib import Path
import sqlite3
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PREFIX = "/workspace/"
STATUSES = {
    0: "invalid", 1: "killed", 2: "survived", 3: "timeout", 4: "crashed",
    5: "abnormal exit", 6: "dry run", 7: "fail fast", 8: "not covered",
}


def render(database, output):
    output.mkdir(parents=True, exist_ok=True)
    normalized = output / "mull.sqlite"
    if database.resolve() == normalized.resolve():
        raise ValueError("The output must differ from the raw test database")
    # Preserve the raw test artifact; only rebase paths in a report copy.
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True) as source:
        with sqlite3.connect(normalized) as dest:
            source.backup(dest)
            rows = dest.execute("SELECT rowid, mutant_id, filename FROM mutant").fetchall()
            if not rows:
                raise ValueError("Mull produced no mutation results")
            for rowid, mutant_id, filename in rows:
                if not filename.startswith(SOURCE_PREFIX):
                    raise ValueError(f"Unexpected source path: {filename}")
                relative = filename.removeprefix(SOURCE_PREFIX)
                path = (ROOT / relative).resolve()
                if not path.is_relative_to(ROOT) or not path.is_file():
                    raise ValueError(f"Source is not in this checkout: {relative}")
                if (":" + filename + ":") not in mutant_id:
                    raise ValueError(f"Mutation ID does not match its source: {mutant_id}")
                dest.execute(
                    "UPDATE mutant SET mutant_id = ?, filename = ?, directory = '' WHERE rowid = ?",
                    (mutant_id.replace(":" + filename + ":", ":" + relative + ":", 1), relative, rowid),
                )
            counts = dict(dest.execute(
                "SELECT execution_status, count(*) FROM mutant GROUP BY execution_status"
            ).fetchall())
    print(", ".join(f"{count} {STATUSES.get(status, 'unknown')}" for status, count in sorted(counts.items())))
    subprocess.run([
        "mull-reporter-19", str(normalized.resolve()),
        "--reporters", "IDE", "--reporters", "Elements", "--reporters", "Sarif",
        "--report-dir", str(output.resolve()), "--report-name", "mull",
        "--report-patch-base", ".", "--allow-surviving",
    ], cwd=ROOT, check=True)
    # Keep the generated viewer version explicit instead of using upstream's
    # unversioned CDN URL. JSON and HTML remain ordinary static artifacts.
    html = output / "mull.html"
    html.write_text(html.read_text().replace(
        "https://www.unpkg.com/mutation-testing-elements",
        "https://unpkg.com/mutation-testing-elements@3.9.0/dist/mutation-test-elements.js",
    ))
    print(f"Reports: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    render(args.database, args.output)
