# Praxis — Agent Guidelines & Architecture Rules

This repository contains **Praxis**, a self-hosted workout tracking and habit execution platform.

All AI coding assistants and contributors working on this codebase must adhere strictly to the architectural constraints, domain invariants, and coding conventions defined below.

---

## 1. Architectural Philosophy: Clean / Hexagonal Architecture

The codebase follows Ports & Adapters (Hexagonal Architecture) with explicit dependency direction:

```text
Interfaces (FastAPI, CLI)
    ↓
Application Layer (Use Cases, DTOs, Policies)
    ↓
Domain Layer (Aggregates, Entities, Value Objects)
    ↑
Infrastructure Layer (SQLAlchemy/SQLModel Repositories, Authelia Auth Adapter)
```

### Dependency Rules:
1. **Domain Purity**: The domain layer (`src/praxis/domain/`) must **never** import or depend on web frameworks (FastAPI, Starlette), ORMs (SQLModel, SQLAlchemy, Tortoise), or infrastructure libraries. Use standard library `dataclasses`, `enum`, `typing`, and pure Python logic.
2. **Ports Define Boundaries**: All external dependencies (database repositories, external identity adapters, time providers) must be declared as abstract interfaces/protocols in `src/praxis/application/ports/`.
3. **Adapters Implement Ports**: Specific technologies (PostgreSQL, SQLite, Authelia header extraction) live strictly in `src/praxis/infrastructure/adapters/`.

---

## 2. Core Domain Invariants (Non-Negotiable)

When authoring or modifying code, ensure these core domain invariants are never violated:

1. **Three-Layer Temporal Separation**:
   - **Prescription** (*What was planned*): `Routine`, `WorkoutDay`, `ExercisePrescription`, `SessionActivity`, `Phase`.
   - **Performance** (*What happened*): `WorkoutSession`, `SessionPrescriptionSnapshot`, `ExercisePerformance`, `SetPerformance`, `ActivityPerformance`.
   - **Analysis** (*What can be derived*): Workload, adherence, and exercise histories derived purely from historical sessions.
2. **Snapshot Immutability**:
   - When a `WorkoutSession` is initiated, `SessionPrescriptionSnapshot` freezes the planned work.
   - Modifying a `Routine` template must **never** alter past or currently in-progress `WorkoutSession` records.
3. **Session Lifecycle Mutability**:
   - While `status == In_Progress`, a `WorkoutSession`'s execution state is mutable (logging sets, adding movements, substituting exercises).
   - Once marked `Completed`, `Partially_Completed`, or `Skipped`, the session is finalized and locked against further mutation.
4. **Substituted History Isolation**:
   - If exercise $A$ is substituted with exercise $B$, the logged sets contribute strictly to the history of exercise $B$ (`performed_exercise_id`).
   - The prescription snapshot retains $A$ (`planned_exercise_id`) for auditability, but analysis queries for $A$ must not include sets performed for $B$.
5. **Single-Active-Routine Enforcement**:
   - `Routine` does not enforce single-active-routine itself (it cannot inspect other routines).
   - This invariant is strictly orchestrated at the application level by `ActivateRoutineUseCase`.
6. **Metric Type Validation**:
   - `SetPerformance` must validate its fields against the exercise's `MetricType` (reps required for `RepsWeight`, duration required for `Duration`).

---

## 3. Specification Documents as Source of Truth

Before proposing domain changes or implementing new features, consult the baseline documentation in `docs/`:

- [`docs/praxis-srs-v1.0.2.md`](docs/praxis-srs-v1.0.2.md): Canonical Software Requirements Specification.
- [`docs/praxis-domain-model-v1.0.1.md`](docs/praxis-domain-model-v1.0.1.md): Canonical Domain Model, Entities, Value Objects, Behavioral Contracts, and Use Cases.

If a requirement or design decision changes during development, update these specifications synchronously.

---

## 4. Testing Conventions

- **Domain Tests (`tests/unit/domain/`)**: Test aggregates, value objects, and domain policies in complete isolation without mocks or database fixtures.
- **Use Case Tests (`tests/unit/application/`)**: Test interactors using simple in-memory repository fakes (`InMemoryRoutineRepository`, etc.).
- **Integration Tests (`tests/integration/`)**: Test database adapters against SQLite (in-memory or file) or PostgreSQL test containers.

---

## 5. Toolchain & Static Analysis Constraints

All code in this repository is continuously validated by three tools. Every file you author or modify **must pass all three gates** before being committed.

### 5.1 Ruff (lint + format)

Configuration lives in `pyproject.toml` under `[tool.ruff]`.

| Concern | Rule | Constraint |
| :--- | :--- | :--- |
| Formatting | `ruff format` | Single authority for code style. Do not manually reformat. |
| Import order | `I` (isort) | `praxis` is declared `known-first-party`. Stdlib → third-party → `praxis`. |
| Type annotations | `ANN` | **All** public functions and methods must carry full type annotations. |
| Naming | `N` | PEP 8 naming enforced. `snake_case` for functions/variables, `PascalCase` for classes, `UPPER_SNAKE` for module-level constants. |
| Pytest style | `PT` | Use `pytest` idioms. No `unittest.TestCase`, no `assertEquals`. |
| Type-checking guards | `TCH` | Imports used only for type hints must be inside `if TYPE_CHECKING:` blocks. |

**Run manually**: `ruff check src/ tests/` and `ruff format src/ tests/`

### 5.2 Pyright (static type checking)

Configuration lives in `pyproject.toml` under `[tool.pyright]`.

- Mode: **`strict`** — the strictest available setting.
- `venv = ".venv"` is configured; pyright reads the project interpreter automatically.
- Two intentional relaxations (see `pyproject.toml` comments):
  - `reportMissingTypeStubs = false` — incomplete stubs in SQLModel / SQLAlchemy / FastAPI.
  - `reportUntypedFunctionDecorator = false` — FastAPI route decorators are untyped upstream.
- The domain layer (`src/praxis/domain/`) must produce **zero pyright errors at all times**. Errors in `infrastructure/` or `interfaces/` due to ORM/framework limitations may be suppressed with `# type: ignore[<code>]` accompanied by a mandatory inline comment explaining the reason.

**Run manually**: `pyright src/`

### 5.3 Pytest + Coverage

Configuration lives in `pyproject.toml` under `[tool.pytest.ini_options]` and `[tool.coverage]`.

- Two registered markers: `unit` and `integration`. Using an unregistered marker is an **error** (`--strict-markers`).
- Coverage gate: **90% minimum** on `src/praxis/`, enforced by `fail_under = 90`.
- `if TYPE_CHECKING:` blocks and `raise NotImplementedError` stubs are excluded from coverage.

**Run manually**:
```bash
pytest -m unit                          # domain + application unit tests only
pytest -m integration                   # requires DB / external services
pytest --cov --cov-report=term-missing  # full run with coverage report
```

---

## 6. Git Hook Workflow

Hooks are version-controlled in `scripts/hooks/` and must be installed into `.git/hooks/` after cloning:

```bash
bash scripts/install-hooks.sh
```

### `pre-commit` (runs on every `git commit`)

1. **`ruff format`** — auto-formats staged Python files and re-stages them.
2. **`ruff check --fix`** — applies safe lint auto-fixes and re-stages. Fails the commit if unfixable violations remain.

Overhead: **< 1 second**. Transparent in normal use.

### `pre-push` (runs on every `git push`)

1. **`pyright src/`** — strict type check. Blocks push on any error.
2. **`pytest -m unit`** — runs all `unit`-marked tests. Blocks push on any failure.

Overhead: **2–5 seconds**. Runs only at push time to avoid per-commit slowdown.

### Bypassing hooks

Use `git commit --no-verify` or `git push --no-verify` **only** for emergency commits (e.g. fixing a broken CI config). Never bypass hooks to avoid fixing type errors or test failures.

---

## 7. Rules of Engagement

- **Do not commit directly without explicit user instruction.**
- Keep changes focused: prefer atomic, well-tested domain increments.
- All committed code must satisfy the three quality gates in §5: `ruff` clean, `pyright strict` clean, domain tests green.
- All public functions, methods, and class attributes must carry explicit type annotations. Do not use `Any` in the domain layer without a `# type: ignore[<code>]` comment explaining why.
- Keep docstrings informative — document *why*, not *what*.
