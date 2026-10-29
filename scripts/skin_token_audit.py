#!/usr/bin/env python3
"""Lists widgets that still read a Material color role by hand
(`cs.surfaceContainerHigh`, `colorScheme.primary`, ...) instead of a skin token,
with the token the line most likely means.

Direct reads still work: `applySkinAreaToScheme` maps each role onto one token
(see docs/skin-tokens.md). They only follow a *different* token than the one
the line is about when the role is shared by several jobs. This report finds
those lines so they can be moved to `SkinAreaScope.colorOf(context, token, ...)`
(or deleted, when a component theme already covers them).

Dry run only: it never edits a file.

  python3 scripts/skin_token_audit.py            # summary
  python3 scripts/skin_token_audit.py --lines    # every line
  python3 scripts/skin_token_audit.py --file lib/features/tools
"""
import argparse, collections, glob, re

ROLE = re.compile(r"\b(?:cs|scheme|colors|colorScheme)\.(\w+)\b")
# (regex on the line, token) -- first match wins. Order matters: most specific first.
HINTS = [
    (r"fillColor|InputDecoration|hintText|TextField", "surface.field"),
    (r"inactiveColor|inactiveTrack|linearTrackColor|circularTrackColor|trackColor|backgroundColor:.*Progress|LinearProgress", "control.track"),
    (r"activeColor|activeTrack|thumbColor|Switch|Checkbox|Radio|Slider", "control.active"),
    (r"Chip|SegmentedButton|FilterChip|ChoiceChip", "choice.*"),
    (r"Divider|BorderSide|border:|Border\.", "border.divider / border.outline"),
    (r"FilledButton|FilledButton\.styleFrom", "action.primary"),
    (r"ElevatedButton|FilledButton\.tonal", "action.tonal"),
    (r"TextButton|OutlinedButton", "action.text"),
    (r"SnackBar|Banner|toast", "floating.toast"),
    (r"Tooltip", "floating.tooltip"),
    (r"showDialog|AlertDialog|Dialog\(", "overlay.dialog"),
    (r"BottomSheet|showModalBottomSheet", "overlay.sheet"),
    (r"PopupMenu|MenuAnchor|MenuItem", "overlay.menu"),
    (r"selected|isSelected|Selection|highlight", "selection.fill"),
    (r"Icon\(|iconColor|IconTheme|icon:", "content.icon"),
    (r"TextStyle|style:|\.copyWith\(color", "content.primary / content.secondary"),
    (r"Card\(|ListTile|Tile\(|DecoratedBox|ColoredBox", "surface.card / surface.tile"),
]
# Lines that match no hint are reported as "?": decide those by hand.
# Roles the bridge already routes to one obvious token: no ambiguity.
BRIDGED = {
    "surface": "surface.page", "onSurface": "content.primary",
    "onSurfaceVariant": "content.secondary", "surfaceContainerHigh": "surface.card",
    "surfaceContainerHighest": "surface.tile", "primary": "action.primary",
    "onPrimary": "action.onPrimary", "outline": "border.outline",
    "outlineVariant": "border.divider", "primaryContainer": "selection.fill",
    "onPrimaryContainer": "selection.on",
}

ap = argparse.ArgumentParser()
ap.add_argument("--lines", action="store_true")
ap.add_argument("--file", default="lib")
args = ap.parse_args()

by_file = collections.Counter()
by_pair = collections.Counter()
rows = []
for path in sorted(glob.glob(args.file + "/**/*.dart", recursive=True) if not args.file.endswith(".dart") else [args.file]):
    if "/l10n/" in path or "/core/theme/" in path:
        continue
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        for role in ROLE.findall(line):
            if role not in BRIDGED and not role.startswith(("surfaceContainer", "secondaryContainer", "onSecondaryContainer", "inverse", "onInverse")):
                continue
            guess = next((tok for rx, tok in HINTS if re.search(rx, line)), "?")
            by_file[path] += 1
            by_pair[(role, guess)] += 1
            rows.append((path, n, role, guess, line.strip()))

if args.lines:
    for path, n, role, guess, text in rows:
        print(f"{path}:{n}: {role} -> {guess}\n    {text[:140]}")
else:
    print(f"{len(rows)} direct reads in {len(by_file)} files\n")
    print("role -> likely token (count)")
    for (role, guess), c in by_pair.most_common(30):
        print(f"  {c:5d}  {role:26s} -> {guess}")
    print("\nbusiest files")
    for path, c in by_file.most_common(12):
        print(f"  {c:5d}  {path}")
