#!/usr/bin/env python3
"""Validate core.l10n() usage against l10n/<Context>/<Locale>.yaml files.

For each mod (identified by the directory containing its .omwscripts file):
  - Find every core.l10n('Context', 'fallbackLocale') call in that mod's Lua files.
  - Confirm l10n/<Context>/ exists.
  - Confirm l10n/<Context>/<fallbackLocale>.yaml exists (fallback must be present).
  - Parse every .yaml file under l10n/ to catch syntax errors early.
  - Warn (don't fail) on locale filenames that don't match {lang}_{COUNTRY} form,
    since OpenMW requires exact lowercase/uppercase + underscore to recognize them.
"""

import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("::error::PyYAML not installed (pip install pyyaml)")
    sys.exit(1)

L10N_CALL_RE = re.compile(
    r"""core\.l10n\(\s*['"]([^'"]+)['"]\s*(?:,\s*['"]([^'"]+)['"])?\s*\)"""
)
LOCALE_FILENAME_RE = re.compile(r"^[a-z]{2}(_[A-Z]{2})?\.yaml$")

errors = []
warnings = []


def find_mod_roots(repo_root: Path):
    return {p.parent for p in repo_root.rglob("*.omwscripts")}


def check_mod(root: Path):
    scripts_dir = root / "scripts"
    if not scripts_dir.is_dir():
        return

    seen_contexts = {}  # context -> set of fallback locales requested

    for lua_file in scripts_dir.rglob("*.lua"):
        text = lua_file.read_text(encoding="utf-8", errors="replace")
        for match in L10N_CALL_RE.finditer(text):
            context, fallback = match.group(1), match.group(2)
            seen_contexts.setdefault(context, set())
            if fallback:
                seen_contexts[context].add(fallback)
            else:
                warnings.append(
                    f"{lua_file}: core.l10n('{context}') called with no "
                    f"fallbackLocale -- if no translation matches the player's "
                    f"locale, message keys will be shown as-is."
                )

    for context, fallbacks in seen_contexts.items():
        context_dir = root / "l10n" / context
        if not context_dir.is_dir():
            errors.append(
                f"{root}: core.l10n('{context}', ...) is called but "
                f"'{context_dir.relative_to(root)}' does not exist."
            )
            continue
        for fallback in fallbacks:
            fallback_file = context_dir / f"{fallback}.yaml"
            if not fallback_file.is_file():
                errors.append(
                    f"{root}: fallback locale '{fallback}' declared in code but "
                    f"'{fallback_file.relative_to(root)}' does not exist."
                )

    # Validate every yaml file under l10n/, and flag suspicious filenames.
    l10n_dir = root / "l10n"
    if l10n_dir.is_dir():
        for yaml_file in l10n_dir.rglob("*.yaml"):
            if not LOCALE_FILENAME_RE.match(yaml_file.name):
                warnings.append(
                    f"{yaml_file}: filename doesn't match the expected "
                    f"{{lang}}_{{COUNTRY}}.yaml pattern (e.g. 'en.yaml', 'de_DE.yaml'). "
                    f"OpenMW requires exact case/separator to recognize a locale file."
                )
            try:
                yaml.safe_load(yaml_file.read_text(encoding="utf-8"))
            except yaml.YAMLError as e:
                errors.append(f"{yaml_file}: invalid YAML -- {e}")


def main():
    repo_root = Path(".").resolve()
    for root in sorted(find_mod_roots(repo_root)):
        check_mod(root)

    for w in warnings:
        print(f"::warning::{w}")
    for e in errors:
        print(f"::error::{e}")

    if errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
