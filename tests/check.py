#!/usr/bin/env python3
"""Checks the plugin against Omarchy's plugin guidelines. Run: tests/check.py

- Every Text draws plain text, so an app or window name shaped like markup
  (<img src=...>) is shown as written instead of being rendered.
- Strings come from the plugin's own catalogs, never Omarchy's, and every key
  the code asks for exists in English.
- Every animation length goes through Style.duration(), and none eases in,
  bounces or overshoots.
"""
import glob
import json
import os
import re
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
failures = []


def fail(message):
    failures.append(message)


def block_after(text, brace):
    """The text of the block whose opening brace is at `brace`."""
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[brace:i + 1]
    return text[brace:]


def own_lines(block):
    """The block's own property lines, without its child objects."""
    out, depth = [], 0
    for line in block.splitlines():
        if depth == 1:
            out.append(line)
        depth += line.count("{") - line.count("}")
    return "\n".join(out)


qml_files = sorted(glob.glob(os.path.join(root, "**", "*.qml"), recursive=True))
english = json.load(open(os.path.join(root, "i18n", "en.json")))
used_keys = set()

for path in qml_files:
    name = os.path.relpath(path, root)
    text = open(path).read()
    code = re.sub(r"//[^\n]*", "", text)

    for match in re.finditer(r"(?<![A-Za-z_.])Text\s*\{", code):
        own = own_lines(block_after(code, match.end() - 1))
        if "textFormat: Text.PlainText" not in own:
            line = code.count("\n", 0, match.start()) + 1
            fail(f"{name}:{line}: Text without textFormat: Text.PlainText")

    if re.search(r"\bI18n\.tn?\(", code):
        fail(f"{name}: reads a string from Omarchy's catalog; use the plugin's own")

    used_keys.update(re.findall(r"\.tn?\(\"([^\"]+)\"", code))

    for match in re.finditer(r"\bduration:\s*(\S+)", code):
        if not match.group(1).startswith("Style.duration("):
            line = code.count("\n", 0, match.start()) + 1
            fail(f"{name}:{line}: animation length not through Style.duration()")

    for match in re.finditer(r"Easing\.(In\w*|\w*Bounce|\w*Elastic|\w*Back)\b", code):
        if match.group(1).startswith("InOut"):
            continue
        line = code.count("\n", 0, match.start()) + 1
        fail(f"{name}:{line}: easing {match.group(0)} eases in, bounces or overshoots")

for key in sorted(used_keys - set(english)):
    fail(f"i18n/en.json: missing string {key}")

for path in sorted(glob.glob(os.path.join(root, "i18n", "*.json"))):
    name = os.path.relpath(path, root)
    try:
        catalog = json.load(open(path))
    except ValueError as error:
        fail(f"{name}: not valid JSON ({error})")
        continue
    for key in sorted(set(catalog) - set(english)):
        fail(f"{name}: string {key} is not in en.json")

if failures:
    print("\n".join(failures))
    sys.exit(1)
print(f"ok: {len(qml_files)} QML files, {len(used_keys)} strings, "
      f"{len(glob.glob(os.path.join(root, 'i18n', '*.json')))} catalogs")
