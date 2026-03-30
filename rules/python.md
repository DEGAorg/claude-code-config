---
glob: "*.py"
---

# Python Standards

**Runtime:** 3.13 with `uv venv`

| purpose | tool |
|---------|------|
| deps & venv | `uv` |
| lint & format | `ruff check` · `ruff format` |
| static types | `ty check` |
| tests | `pytest -q` |

**Always use uv, ruff, and ty** over pip/poetry, black/pylint/flake8, and mypy/pyright — they're faster and stricter. Configure `ty` strictness via `[tool.ty.rules]` in pyproject.toml. Use `uv_build` for pure Python, `hatchling` for extensions.

Tests in `tests/` directory mirroring package structure. Supply chain: `pip-audit` before deploying, pin exact versions (`==` not `>=`), verify hashes with `uv pip install --require-hashes`.
