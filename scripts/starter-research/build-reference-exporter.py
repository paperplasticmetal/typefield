#!/usr/bin/env python3
"""Build a research-only CLI from an isolated snapshot of Typefield's sources."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=Path("/tmp/typefield-reference-exporter"))
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
output = args.output.resolve()
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="typefield-reference-build-") as directory:
    snapshot = Path(directory)
    for source in (root / "Sources").glob("*.swift"):
        shutil.copy2(source, snapshot / source.name)
    main = snapshot / "main.swift"
    marker = '} else if CommandLine.arguments.contains("--starter-quality-audit") {'
    source = main.read_text()
    if source.count(marker) != 1:
        raise RuntimeError("The CLI entry point changed; inspect it before rebuilding.")
    branch = '''} else if CommandLine.arguments.contains("--export-model-references") {
    do { try ResearchReferenceExport.run() }
    catch { fputs("Reference export failed: \\(error.localizedDescription)\\n", stderr); exit(1) }
    exit(0)
'''
    main.write_text(source.replace(marker, branch + marker))
    shutil.copy2(root / "scripts/starter-research/export-model-references.swift", snapshot / "ResearchReferenceExport.swift")
    subprocess.run([
        "swiftc", "-warnings-as-errors", "-swift-version", "5", "-O",
        "-module-cache-path", "/tmp/typefield-research-module-cache",
        "-target", "arm64-apple-macosx13.0",
        *map(str, sorted(snapshot.glob("*.swift"))), "-o", str(output),
    ], check=True)
print(output)
