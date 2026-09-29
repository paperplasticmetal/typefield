#!/usr/bin/env python3
"""Build a disposable Typefield audit binary with the n-derived lowercase w pilot."""
from __future__ import annotations

import argparse
import pathlib
import shutil
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    root = args.source_root.resolve()
    output = args.output.resolve()
    source_dir = output / "Sources"
    source_dir.mkdir(parents=True, exist_ok=True)
    for path in (root / "Sources").glob("*.swift"):
        shutil.copy2(path, source_dir / path.name)

    assist = source_dir / "FontLabStarterAssist.swift"
    text = assist.read_text()
    signature = "    static func sourceDerived(_ character: String, sources: [String: FontLabGlyph], style: FontLabStarterStyle, reuseCapStems: Bool) -> FontLabStarterDerivation? {\n"
    insertion = signature + '''        // Pilot hypothesis: reflect the supplied n arch over the x-height and repeat it.
        // A lower-case w is two descending arches; no target outline is consulted.
        if character == "w", let source = sources["n"],
           let inverted = transformed(source, to: "n", width: source.resolvedDesignWidth,
                                     x: { $0 },
                                     y: { style.metrics.baseline + style.metrics.xHeight - $0 },
                                     reverseWinding: true, verticalSlant: style.slant),
           let glyph = repeatedN(inverted, weight: style.safeWeight, character: "w") {
            return .init(glyph: glyph, sources: ["n"], method: "Inverted source arch pair",
                         explanation: "Two reflected copies of the drawn n arch form a w. Refine the valley and spacing.")
        }
'''
    if signature not in text:
        raise SystemExit("sourceDerived insertion point changed; refusing to patch")
    text = text.replace(signature, insertion, 1)

    repeated_signature = "    static func repeatedN(_ source: FontLabGlyph, weight: Double) -> FontLabGlyph? {"
    repeated_replacement = "    static func repeatedN(_ source: FontLabGlyph, weight: Double, character: String = \"m\") -> FontLabGlyph? {"
    if repeated_signature not in text:
        raise SystemExit("repeatedN signature changed; refusing to patch")
    text = text.replace(repeated_signature, repeated_replacement, 1)
    final_glyph = 'let glyph = FontLabGlyph(character: "m", strokes: first.strokes + second.strokes,'
    if final_glyph not in text:
        raise SystemExit("repeatedN constructor changed; refusing to patch")
    text = text.replace(final_glyph, 'let glyph = FontLabGlyph(character: character, strokes: first.strokes + second.strokes,', 1)
    assist.write_text(text)

    binary = output / "typefield-structure-pilot"
    cache = output / "module-cache"
    cache.mkdir(exist_ok=True)
    command = ["swiftc", "-warnings-as-errors", "-swift-version", "5", "-O",
               "-module-cache-path", str(cache), "-target", "arm64-apple-macosx13.0",
               *map(str, sorted(source_dir.glob("*.swift"))), "-o", str(binary)]
    print("BUILD", " ".join(command), flush=True)
    subprocess.run(command, check=True)
    print("READY", binary)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode)
