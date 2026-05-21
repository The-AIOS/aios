---
name: python-best-practices
description: Python best practices across design patterns, error handling, project structure, and testing. Use when writing Python code, structuring new Python projects, designing APIs for libraries, implementing error handling, or setting up pytest test suites.
---

# Python Best Practices

Curated reference for writing production-quality Python — opinionated where it matters, undogmatic where it doesn't.

## When to load which reference

| Working on | Read |
|---|---|
| Module layout, public APIs, package structure | [references/project-structure.md](references/project-structure.md) |
| Design patterns (KISS, SRP, composition, DI) | [references/design-patterns.md](references/design-patterns.md) |
| Validation, exception hierarchies, partial-failure handling | [references/error-handling.md](references/error-handling.md) |
| pytest, fixtures, mocking, parameterization, TDD | [references/testing-patterns.md](references/testing-patterns.md) |

Each reference is an in-depth guide — load only the one relevant to the current task.

## Core principles (all references share)

- **Explicit over implicit** — type hints, named arguments, no magic.
- **Small over abstract** — one function per concept, no premature inheritance.
- **Fail loud at boundaries, validate at the edge** — Pydantic/dataclasses at API surfaces, raw types internally.
- **Test the behavior, not the implementation** — pytest fixtures over class-based setUp, parameterize for variants.

For test-first discipline beyond Python specifics, see [superpowers/test-driven-development](../../superpowers/test-driven-development/SKILL.md).
