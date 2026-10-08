#!/usr/bin/env python3
"""Cheap, dependency-free architecture guards for lib/.  Run from the repo root.

    python3 scripts/check_code_boundaries.py

Exits non-zero (and prints every offence) if any of these regress:

1. The engine channel's name is spelled out only in
   lib/core/api/vault_engine_channel.dart.
2. The `kVaultEngineChannel` constant -- the way to reach the engine channel
   *without* dependency injection -- is referenced only from the files in
   CONSTANT_ALLOWLIST. Everything else should take an injected MethodChannel
   or a VaultXxxApi from lib/core/providers/vault_engine_providers.dart.
   To add an exception, add the file to the allow-list in the same change and
   say why in review.
3. Files that talk to the engine channel use the ChannelMethods constants, not
   raw method-name strings.
4. No empty `catch` blocks. A swallowed error must be logged (see
   logSwallowed in lib/core/api/vault_engine_types.dart, or VeLog) or carry a
   comment saying why it's safe to ignore.

The point is to stop the debt re-accumulating, not to be a linter: it uses
plain regexes, so keep the rules few and obvious.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"

CHANNEL_FILE = "lib/core/api/vault_engine_channel.dart"
CHANNEL_NAME = "com.aeidolon.vaultexplorer/engine"

# Plain const objects (or a part-of library) with no `ref` to read
# vaultEngineChannelProvider from.
CONSTANT_ALLOWLIST = {
    CHANNEL_FILE,
    "lib/core/providers/vault_engine_providers.dart",
    "lib/data/services/app_secure_storage.dart",
    "lib/data/services/file_operation_service.dart",  # part of models/file_operation.dart
    "lib/data/services/logcat_service.dart",
    "lib/data/services/thumbnail_cache_service.dart",
    "lib/data/services/password_interchange/authenticator_backup_crypto.dart",
    "lib/main.dart",  # headless scheduled-sync entry-point; no Riverpod container
}

# Files that use the engine channel and so must use ChannelMethods constants.
# quick_capture_api.dart is excluded: its raw names go to its own
# `.../quickcapture` channel.
RAW_NAME_EXEMPT = {
    "lib/core/api/quick_capture_api.dart",
    "lib/main.dart",  # 'ready' is on the scheduled_sync control channel, not the engine channel
}


def is_generated(rel: str) -> bool:
    return rel.endswith(".g.dart") or rel.endswith(".freezed.dart") or rel.startswith("lib/l10n/generated/")


def dart_files():
    for path in sorted(LIB.rglob("*.dart")):
        rel = path.relative_to(ROOT).as_posix()
        if not is_generated(rel):
            yield rel, path.read_text(encoding="utf-8", errors="replace")


def line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


RAW_NAME = re.compile(r"invoke(?:Map|List)?Method(?:<[^>(]*(?:<[^>]*>)?[^>(]*>)?\(\s*'([^']+)'")
EMPTY_CATCH = re.compile(r"\bcatch\s*\(\s*\w+(?:\s*,\s*\w+)?\s*\)\s*\{\s*\}")


def main() -> int:
    problems = []
    engine_files = set()

    for rel, text in dart_files():
        if rel != CHANNEL_FILE and CHANNEL_NAME in text:
            for m in re.finditer(re.escape(CHANNEL_NAME), text):
                problems.append(
                    f"{rel}:{line_of(text, m.start())}: spells out the engine channel name; "
                    f"use kVaultEngineChannel / an injected channel (see {CHANNEL_FILE})"
                )

        if rel not in CONSTANT_ALLOWLIST and re.search(r"\bkVaultEngineChannel(?:Name)?\b", text):
            m = re.search(r"\bkVaultEngineChannel(?:Name)?\b", text)
            problems.append(
                f"{rel}:{line_of(text, m.start())}: reaches the engine channel without injection; "
                "take a MethodChannel / VaultXxxApi from vault_engine_providers.dart instead "
                "(or add this file to CONSTANT_ALLOWLIST with a reason)"
            )

        if rel in CONSTANT_ALLOWLIST or rel.startswith("lib/core/api/"):
            engine_files.add(rel)
            if rel not in RAW_NAME_EXEMPT:
                for m in RAW_NAME.finditer(text):
                    problems.append(
                        f"{rel}:{line_of(text, m.start())}: raw method name '{m.group(1)}'; "
                        "add it to ChannelMethods and use the constant"
                    )

        for m in EMPTY_CATCH.finditer(text):
            problems.append(
                f"{rel}:{line_of(text, m.start())}: empty catch block; log it "
                "(logSwallowed / VeLog) or add a comment saying why ignoring it is safe"
            )

    if problems:
        print(f"check_code_boundaries: {len(problems)} problem(s)\n")
        for p in problems:
            print("  " + p)
        return 1

    print("check_code_boundaries: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
