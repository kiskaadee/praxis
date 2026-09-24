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

## 5. Rules of Engagement

- **Do not commit directly without explicit user instruction.**
- Keep PRs and changes focused: prefer atomic, well-tested domain increments.
- Follow PEP 8, enforce strict type annotations (`mypy` / `pyright`), and keep docstrings informative.
