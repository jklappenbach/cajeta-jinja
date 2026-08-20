#!/usr/bin/env python3
"""
gen_fixtures.py — the reference oracle (cajeta-jinja plan 1.1.1 / 1.2.3).

Runs REAL Jinja2 over every fixture definition and writes the expected
rendering next to it. Expectations are never hand-written (spec 6.1):
each fixture directory under src/test/fixtures/ holds

    template.j2      the template source
    context.json     the render context (JSON object)
    settings.json    engine settings (all optional):
                       trim_blocks, lstrip_blocks, autoescape (bools)
                       strict_undefined (bool)
                       now_epoch_seconds (int, injected clock)
    expected.out     WRITTEN BY THIS SCRIPT — the oracle's bytes

Run from the repo root:  python3 tools/gen_fixtures.py
The Jinja2 version is PINNED below; a mismatch aborts rather than
generating references against semantics nobody agreed to. Regenerate on
purpose, review the diff, and commit expected.out like any other source.
"""

import json
import pathlib
import sys

PINNED_JINJA2 = "3.1.6"

try:
    import jinja2
except ImportError:
    sys.exit("jinja2 is not installed: pip install jinja2==" + PINNED_JINJA2)

if jinja2.__version__ != PINNED_JINJA2:
    sys.exit(
        "jinja2 %s found but the corpus is pinned to %s — install the pin "
        "or bump PINNED_JINJA2 deliberately (it changes every reference)"
        % (jinja2.__version__, PINNED_JINJA2))

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "src" / "test" / "fixtures"


def build_env(settings: dict) -> jinja2.Environment:
    env = jinja2.Environment(
        # transformers enables loopcontrols; the engine always supports
        # break/continue (spec 2.11), so the oracle must too.
        extensions=["jinja2.ext.loopcontrols"],
        trim_blocks=settings.get("trim_blocks", False),
        lstrip_blocks=settings.get("lstrip_blocks", False),
        autoescape=settings.get("autoescape", False),
        undefined=(jinja2.StrictUndefined
                   if settings.get("strict_undefined", False)
                   else jinja2.Undefined),
        keep_trailing_newline=True,
    )
    now = settings.get("now_epoch_seconds")
    if now is not None:
        import datetime

        def strftime_now(fmt):
            dt = datetime.datetime.fromtimestamp(
                now, tz=datetime.timezone.utc)
            return dt.strftime(fmt)

        env.globals["strftime_now"] = strftime_now
    return env


def main() -> int:
    if not FIXTURES.is_dir():
        sys.exit("no fixture root at %s" % FIXTURES)
    wrote = 0
    for d in sorted(p for p in FIXTURES.iterdir() if p.is_dir()):
        tpl_path = d / "template.j2"
        if not tpl_path.is_file():
            continue
        template = tpl_path.read_text(encoding="utf-8")
        ctx_path = d / "context.json"
        context = (json.loads(ctx_path.read_text(encoding="utf-8"))
                   if ctx_path.is_file() else {})
        st_path = d / "settings.json"
        settings = (json.loads(st_path.read_text(encoding="utf-8"))
                    if st_path.is_file() else {})
        env = build_env(settings)
        out = env.from_string(template).render(**context)
        (d / "expected.out").write_bytes(out.encode("utf-8"))
        wrote += 1
        print("  %-32s %4d bytes" % (d.name, len(out.encode("utf-8"))))
    print("wrote %d expected.out files (jinja2 %s)" % (wrote, PINNED_JINJA2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
