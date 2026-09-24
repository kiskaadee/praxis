---
title: Implementation Blueprint
description: Translates the approved SRS (v1.0.2) and Domain Model (v1.0.1) into concrete Python implementation decisions. Records all design choices made during the Phase 0 implementation-readiness pass.
version: 0.2.0
status: Phase 0 Complete
date: 2026-09-24
tags:
  - implementation
  - blueprint
  - architecture
  - python
---

# Implementation Blueprint

> Translates the approved **SRS v1.0.2** and **Domain Model v1.0.1** into concrete Python implementation decisions.
> This document records *how* the approved model will be represented in Python.
> It does **not** redefine the domain.

| Document Attribute | Specification |
| :--- | :--- |
| **Document Version** | `0.2.0` |
| **Status** | Phase 0 Complete |
| **Last Updated** | 2026-09-24 |
| **SRS Baseline** | [`praxis-srs-v1.0.2.md`](praxis-srs-v1.0.2.md) |
| **Domain Model Baseline** | [`praxis-domain-model-v1.0.1.md`](praxis-domain-model-v1.0.1.md) |

---

> [!IMPORTANT]
> **Document purpose**: Every decision recorded here was made to resolve an implementation ambiguity from the approved specs. If a decision here conflicts with SRS or Domain Model, the specs take precedence and this document must be updated.

---

## 1. Package Structure

```text
src/praxis/
├── domain/
│   ├── __init__.py
│   ├── aggregates/
│   │   ├── __init__.py
│   │   ├── exercise.py          # Exercise aggregate root
│   │   ├── routine.py           # Routine + WorkoutDay + ExercisePrescription + SessionActivity + Phase
│   │   └── workout_session.py   # WorkoutSession + ExercisePerformance + SetPerformance + ActivityPerformance
│   ├── value_objects/
│   │   ├── __init__.py
│   │   ├── identifiers.py       # UserId, ExerciseId, RoutineId, SessionId, PrescriptionId, …
│   │   ├── measurement.py       # Weight, Duration, Distance, RIR, RepRange
│   │   ├── enums.py             # Weekday, DayKind, MetricType, SessionStatus, MuscleGroup, Equipment, Unit
│   │   ├── set_data.py          # SetData (input value object for MetricValidationPolicy and record_set)
│   │   └── snapshot.py          # SessionPrescriptionSnapshot, PrescriptionSnapshotItem, ActivitySnapshotItem, SubstitutionContext
│   ├── policies/
│   │   ├── __init__.py
│   │   ├── completion_policy.py     # CompletionPolicy, CompletionResult
│   │   ├── metric_validation.py     # MetricValidationPolicy (governs SetPerformance creation)
│   │   ├── workload_calculator.py   # WorkloadCalculator, Workload result type
│   │   └── adherence_calculator.py  # AdherenceCalculator, AdherenceResult
│   └── factories/
│       ├── __init__.py
│       └── session_snapshot_factory.py  # SessionSnapshotFactory
│
├── application/
│   ├── __init__.py
│   ├── ports/
│   │   ├── __init__.py
│   │   ├── repositories.py      # RoutineRepository, WorkoutSessionRepository, ExerciseRepository, UserRepository (protocols)
│   │   ├── auth_provider.py     # IdentityAdapter protocol
│   │   └── clock.py             # ClockPort protocol
│   ├── use_cases/
│   │   ├── __init__.py
│   │   ├── routine/
│   │   │   ├── create_routine.py
│   │   │   └── activate_routine.py
│   │   ├── session/
│   │   │   ├── initiate_workout.py
│   │   │   ├── record_set.py
│   │   │   ├── remove_set.py
│   │   │   ├── substitute_exercise.py
│   │   │   ├── add_ad_hoc_exercise.py
│   │   │   ├── record_activity.py
│   │   │   ├── finish_workout.py
│   │   │   └── skip_workout.py
│   │   └── query/
│   │       ├── query_weekly_calendar.py
│   │       ├── query_exercise_history.py
│   │       └── calculate_adherence.py
│   └── dtos/
│       ├── __init__.py
│       ├── routine_dtos.py
│       ├── session_dtos.py
│       └── exercise_dtos.py
│
└── infrastructure/           # Phase 3 — not started yet
    ├── adapters/
    └── persistence/

tests/
├── unit/
│   ├── domain/
│   │   ├── test_value_objects.py
│   │   ├── test_exercise.py
│   │   ├── test_routine.py
│   │   ├── test_workout_session.py
│   │   ├── test_session_snapshot_factory.py
│   │   ├── test_completion_policy.py
│   │   ├── test_metric_validation.py
│   │   ├── test_workload_calculator.py
│   │   └── test_adherence_calculator.py
│   └── application/
│       └── (use case tests against in-memory fakes — Phase 2)
└── integration/
    └── (database adapter tests — Phase 3)
```

---

## 2. Dependency Direction

```text
                 ┌──────────────────┐
                 │   interfaces/    │  (Phase 4 — FastAPI)
                 └────────┬─────────┘
                          │ imports
                          ▼
                 ┌──────────────────┐
                 │   application/   │  use_cases/ + dtos/ + ports/
                 └────────┬─────────┘
                          │ imports
               ┌──────────┴──────────┐
               ▼                     ▼
      ┌──────────────┐      ┌──────────────────┐
      │   domain/    │      │  application/    │
      │  (pure Python│      │  ports/          │
      │   stdlib)    │      │  (Protocol stubs)│
      └──────────────┘      └────────┬─────────┘
                                     ▲ implements (structurally)
                                     │
                            ┌────────┴─────────┐
                            │  infrastructure/ │
                            │  adapters/       │
                            └──────────────────┘
```

The critical relationship: **both** `application/` and `infrastructure/` depend on `application/ports/`. `infrastructure/` never depends on `application/use_cases/`, and `application/` never depends on `infrastructure/`. The protocol is satisfied structurally — no base class import required.

**In import terms:**

```text
interfaces/fastapi/       → application/use_cases/
application/use_cases/    → domain/  +  application/ports/
domain/                   → stdlib only (dataclasses, enum, uuid, datetime, decimal)
infrastructure/adapters/  → application/ports/  (satisfies Protocol structurally)
tests/unit/domain/        → domain/ only  (no mocks, no fakes)
tests/unit/application/   → application/  +  domain/  (in-memory port fakes)
tests/integration/        → infrastructure/  (real DB — Phase 3)
```

**Absolute prohibition**: `domain/` must not import from `application/`, `infrastructure/`, or any third-party library.

---

## 3. Dataclass & Immutability Strategy

### Value Objects → `@dataclass(frozen=True)`

All value objects are frozen dataclasses. They cannot be mutated after construction. Equality is structural (all fields must match).

```python
from dataclasses import dataclass
from decimal import Decimal
from enum import Enum

@dataclass(frozen=True)
class Weight:
    value: Decimal
    unit: Unit  # KG | LBS

    def __post_init__(self) -> None:
        if self.value < Decimal("0"):
            raise ValueError("Weight cannot be negative")

    def to_kg(self) -> Decimal:
        if self.unit == Unit.KG:
            return self.value
        return (self.value * Decimal("0.453592")).quantize(Decimal("0.001"))
```

### Entities (non-root) → `@dataclass(eq=False)`

Entities have identity, not structural equality. `eq=False` disables auto-generated `__eq__` so the default identity comparison (`is`) applies unless an explicit `__eq__` based on `id` is added.

```python
@dataclass(eq=False)
class SetPerformance:
    id: SetPerformanceId
    actual_reps: int | None
    actual_weight: Weight | None
    actual_duration: Duration | None
    reps_in_reserve: RIR | None
    notes: str

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, SetPerformance):
            return NotImplemented
        return self.id == other.id
```

### Aggregate Roots → `@dataclass(eq=False)`

Same pattern as entities. Internal mutable state (list of sets, session status) is held in regular Python lists and primitive fields.

### `SessionPrescriptionSnapshot` → `@dataclass(frozen=True)` with tuple children

Because the snapshot is a value object containing lists, use `tuple` (not `list`) for `exercise_prescriptions` and `activities` to guarantee physical immutability.

```python
@dataclass(frozen=True)
class SessionPrescriptionSnapshot:
    routine_id: RoutineId
    routine_name: str
    phase_name: str
    exercise_prescriptions: tuple[PrescriptionSnapshotItem, ...]
    activities: tuple[ActivitySnapshotItem, ...]
```

---

## 4. ID Representation

**Decision**: All IDs are newtype-style frozen dataclasses wrapping `uuid.UUID`.

```python
import uuid
from dataclasses import dataclass

@dataclass(frozen=True)
class ExerciseId:
    value: uuid.UUID

    @classmethod
    def generate(cls) -> "ExerciseId":
        return cls(uuid.uuid4())

    def __str__(self) -> str:
        return str(self.value)
```

**Rationale**: Strong typing prevents passing a `RoutineId` where an `ExerciseId` is expected. Wrapping `uuid.UUID` (not raw `str`) gives canonical comparison semantics and clean serialisation.

All IDs are defined in `praxis/domain/value_objects/identifiers.py`.

---

## 5. Enum Strategy

All enums inherit from both `str` and `Enum` for convenient serialization:

```python
from enum import Enum

class MetricType(str, Enum):
    REPS_WEIGHT = "RepsWeight"
    DURATION = "Duration"
    DISTANCE_DURATION = "DistanceDuration"

class SessionStatus(str, Enum):
    IN_PROGRESS = "In_Progress"
    COMPLETED = "Completed"
    PARTIALLY_COMPLETED = "Partially_Completed"
    SKIPPED = "Skipped"
```

---

## 6. Exception Strategy

Domain exceptions live in `praxis/domain/exceptions.py`. No third-party libraries.

```python
class PraxisDomainError(Exception):
    """Base class for all domain rule violations."""

class SessionFinalizedError(PraxisDomainError):
    """Raised when a mutation is attempted on a finalized WorkoutSession."""

class InvalidMetricDataError(PraxisDomainError):
    """Raised when SetPerformance data does not match the exercise MetricType."""

class SubstitutionNotAllowedError(PraxisDomainError):
    """Raised when substitution is attempted after sets have been logged."""

class PerformanceNotFoundError(PraxisDomainError):
    """Raised when performance_id is not found within the session."""
```

Application-level errors (e.g. "routine not found") are separate and live in `application/exceptions.py`.

---

## 7. Clock / Time Abstraction

**Decision**: Inject a `ClockPort` protocol into use cases. Never call `datetime.now()` directly in domain or application code.

```python
# application/ports/clock.py
from typing import Protocol
from datetime import datetime, date

class ClockPort(Protocol):
    def now(self) -> datetime: ...
    def today(self) -> date: ...
```

Domain factories and aggregate methods that need the current time receive `now: datetime` as an argument, not the clock directly. The use case resolves the clock and passes the concrete value down.

---

## 8. Aggregate Construction

The **public construction API** for aggregate roots is a `create()` classmethod. It carries the invariant checks and ID generation that must happen at construction time. The underlying dataclass `__init__` remains available as the implementation mechanism — `create()` calls it via `cls(...)`.

This distinction matters: do not fight Python's generated `__init__` or mark it private. It is used internally by `create()` and will also be needed by infrastructure adapters when rehydrating persisted aggregates from storage (where invariants were already satisfied on the way in).

```python
@classmethod
def create(
    cls,
    owner_id: UserId,
    name: str,
    schedule: dict[Weekday, WorkoutDay],
    phases: list[Phase],
) -> "Routine":
    if not name.strip():
        raise ValueError("Routine name must not be blank")
    if not phases:
        raise ValueError("Routine must have at least one Phase")
    return cls(
        id=RoutineId.generate(),
        owner_id=owner_id,
        name=name,
        is_active=False,
        activated_at=None,
        phases=phases,
        schedule=schedule,
    )
```

`SessionSnapshotFactory` is a standalone domain service (not a method on `Routine`) so that it can cross aggregate boundaries under domain control without coupling the aggregates to each other.

---

## 9. Resolved Pre-Implementation Ambiguities

### 9.1. `SetPerformance` — Metric Field Requirements (Decision)

The domain model lists `actual_reps`, `actual_weight`, and `actual_duration` on `SetPerformance`. The SRS workload rules (FR-ANL-2) also reference distance. `DistanceDuration` exercises cover two distinct activity patterns that require different representations:

```text
DistanceDuration
├── Continuous activity (e.g. 20-min stationary bike)
│     → ActivityPerformance.actual_distance / actual_duration
└── Discrete interval set (e.g. 400m sprint as one logged set)
      → SetPerformance.actual_distance / actual_duration
```

**Decision**: `actual_distance: Distance | None` is added to `SetPerformance` to cover the discrete-interval case. `ActivityPerformance.actual_distance` covers the continuous-activity case. Both fields are optional; `MetricValidationPolicy` requires at least one to be non-null when the metric type is `DistanceDuration`.

| Metric Type | Required on `SetPerformance` | Optional on `SetPerformance` |
| :--- | :--- | :--- |
| `RepsWeight` | `actual_reps` (int ≥ 0) | `actual_weight` (null = bodyweight) |
| `Duration` | `actual_duration` (Duration) | — |
| `DistanceDuration` | at least one of `actual_duration` or `actual_distance` | the other |

**Rationale**: Treating sprint intervals as sets is consistent with how strength training is logged — a 400m sprint is a discrete effort with a start and end, not a continuous session activity. The two-case split keeps `ActivityPerformance` for unstructured/continuous cardio and `SetPerformance` for structured intervals.

`MetricValidationPolicy` enforces these rules in `praxis/domain/policies/metric_validation.py`.

---

### 9.2. `SetData` — Input Value Object (Decision)

`MetricValidationPolicy.validate()` and `WorkoutSession.record_set()` both need a typed input value. Rather than accepting loose keyword arguments, they receive a `SetData` value object.

**Decision**: `SetData` is a frozen dataclass defined in `praxis/domain/value_objects/set_data.py`.

```python
# praxis/domain/value_objects/set_data.py
from __future__ import annotations
from dataclasses import dataclass
from praxis.domain.value_objects.measurement import Weight, Duration, Distance, RIR

@dataclass(frozen=True)
class SetData:
    """Carries the raw input for one logged set before it becomes a SetPerformance.

    All measurement fields are optional at construction; MetricValidationPolicy
    determines which combination is valid for a given MetricType.
    """
    actual_reps: int | None = None
    actual_weight: Weight | None = None
    actual_duration: Duration | None = None
    actual_distance: Distance | None = None
    reps_in_reserve: RIR | None = None
    notes: str = ""
```

`SetData` lives in the domain layer so that `MetricValidationPolicy` (also domain) can reference it without any application or infrastructure imports.

---

### 9.3. Completion Semantics — `CompletionPolicy` vs. SRS "Honest Effort" (Decision)

SRS FR-STAT-2 says: *"An exercise is evaluated as complete when all prescribed sets have been attempted with honest effort (logging reps within target range or completing full sets short of failure with RIR/notes)."*

Domain Model §6.2 reduces this to: *"Exercise complete if `count(valid sets logged) >= target_sets from snapshot`."*

**Decision**: The domain's `CompletionPolicy` uses the **count-based rule exclusively**. "Honest effort" is a UX concern surfaced via the Smart Completion Suggestion (FR-STAT-3), not a domain invariant.

Concretely:
- A logged set is always counted (no effort gating in the domain).
- The policy counts sets per performance against the snapshot's `target_sets`.
- "Honest effort" language is surfaced in the suggestion UI's copy, not encoded as a predicate.

**Rationale**: RIR and notes are optional (FR-LOG-2). Gating completion on their presence would prevent valid sessions from completing. The count rule is deterministic, testable, and honours user autonomy (FR-LOG-3 "session autonomy").

```python
@dataclass(frozen=True)
class CompletionResult:
    suggested_status: SessionStatus
    completed_exercises: int
    total_prescribed_exercises: int
    set_adherence_rate: Decimal  # total_logged / total_prescribed

class CompletionPolicy:
    def evaluate(self, session: "WorkoutSession") -> CompletionResult:
        ...
```

---

### 9.4. `WorkoutSession.finish()` — Legal Override States (Decision)

The domain model permits an `Optional[override_status]` parameter. The question is which states are valid overrides.

**Decision**: Legal override values are `Completed` and `Partially_Completed` only.

- `In_Progress` is **not** a legal override (you cannot "finish" into In_Progress).
- `Skipped` is **not** a legal finish override; use `session.skip(reason)` instead.
- Passing an illegal override raises `InvalidSessionStatusError(PraxisDomainError)`.

```python
_LEGAL_FINISH_OVERRIDES: frozenset[SessionStatus] = frozenset({
    SessionStatus.COMPLETED,
    SessionStatus.PARTIALLY_COMPLETED,
})
```

This is enforced inside `WorkoutSession.finish()` before any state transition occurs.

---

### 9.5. Metric Snapshotting — What Gets Frozen (Decision)

The snapshot must make each session historically stable even if the live `Exercise` aggregate is later updated (e.g., name changed, category corrected).

**Decision**: `PrescriptionSnapshotItem` freezes:

```python
@dataclass(frozen=True)
class PrescriptionSnapshotItem:
    prescription_id: PrescriptionId
    exercise_id: ExerciseId
    exercise_name: str          # frozen name at snapshot time
    metric_type: MetricType     # frozen metric type at snapshot time
    target_sets: int
    rep_range: RepRange | None
    target_duration: Duration | None
    target_weight: Weight | None
    is_unilateral: bool
    order_index: int
    notes: str
```

`metric_type` is explicitly snapshotted so that `MetricValidationPolicy` during the session uses the metric type the exercise had *at the time the session started*, not whatever it might be if the exercise is later recategorised.

---

### 9.6. `ScheduledWorkout` — Aggregate vs. Read Model (Decision)

SRS FR-CAL-1/CAL-2 references `ScheduledWorkout` as a projection. Domain Model §7 use case #11 (`QueryWeeklyCalendarUseCase`) returns projected items.

**Decision**: `ScheduledWorkout` is a **read model / application DTO**, not a domain aggregate.

It is never persisted independently. `QueryWeeklyCalendarUseCase` constructs it on the fly by:
1. Loading the user's active `Routine`.
2. Computing which `WorkoutDay` falls on each date in the requested window.
3. Resolving the active `Phase` for each date.
4. Merging with any existing `WorkoutSession` records for those dates.
5. Returning a `WeeklyCalendarView` DTO.

```python
# application/dtos/session_dtos.py
@dataclass(frozen=True)
class ScheduledWorkoutProjection:
    date: date
    weekday: Weekday
    day_kind: DayKind
    routine_id: RoutineId
    workout_day_id: WorkoutDayId
    phase_name: str
    session: WorkoutSessionSummary | None  # None if not yet initiated
```

**Rationale**: `ScheduledWorkout` has no identity across time, no invariants to enforce, and no lifecycle of its own. Treating it as an aggregate would require persisting it and managing its state transitions — adding complexity with no domain benefit.

---

## 10. Repository Port Shapes

> [!NOTE]
> The method signatures below are **provisional** — derived from the approved use case inventory in Domain Model §7. They will be refined in Phase 2 as each use case is implemented. The existence and structure of ports (as `Protocol` classes in `application/ports/`) is architectural and frozen; the exact query methods are not.

Ports are declared as `Protocol` classes in `praxis/application/ports/repositories.py`. No base classes, no generics superclass — each port is explicit and minimal.

```python
from typing import Protocol
from praxis.domain.aggregates.routine import Routine
from praxis.domain.value_objects.identifiers import UserId, RoutineId

class RoutineRepository(Protocol):
    def save(self, routine: Routine) -> None: ...
    def get_by_id(self, routine_id: RoutineId) -> Routine | None: ...
    def get_active(self, user_id: UserId) -> Routine | None: ...
    def list_for_user(self, user_id: UserId) -> list[Routine]: ...
    def delete(self, routine_id: RoutineId) -> None: ...

class WorkoutSessionRepository(Protocol):
    def save(self, session: WorkoutSession) -> None: ...
    def get_by_id(self, session_id: SessionId) -> WorkoutSession | None: ...
    def get_by_date(self, user_id: UserId, date: date) -> WorkoutSession | None: ...
    def list_for_user_in_range(self, user_id: UserId, start: date, end: date) -> list[WorkoutSession]: ...

class ExerciseRepository(Protocol):
    def save(self, exercise: Exercise) -> None: ...
    def get_by_id(self, exercise_id: ExerciseId) -> Exercise | None: ...
    def list_all(self, user_id: UserId) -> list[Exercise]: ...

class UserRepository(Protocol):
    def save(self, user: User) -> None: ...
    def get_by_id(self, user_id: UserId) -> User | None: ...
    def get_by_external_id(self, external_id: str) -> User | None: ...
```

---

## 11. Policy Interfaces

Domain policies are plain classes (not abstract base classes). They receive domain objects and return value-object results. They do not interact with repositories.

| Policy | Input | Output |
| :--- | :--- | :--- |
| `MetricValidationPolicy.validate(metric_type, set_data)` | `MetricType`, `SetData` | `None` or raises `InvalidMetricDataError` |
| `CompletionPolicy.evaluate(session)` | `WorkoutSession` | `CompletionResult` |
| `WorkloadCalculator.calculate(performances)` | `list[ExercisePerformance]` | `Workload` |
| `AdherenceCalculator.calculate(sessions, scheduled_count)` | `list[WorkoutSession]`, `int` | `AdherenceResult` |
| `SessionSnapshotFactory.create(routine, workout_day, session_date, now)` | domain objects | `WorkoutSession` |

Policies are stateless. Use cases instantiate them directly (no dependency injection needed at this layer).

---

## 12. Testing Strategy

### Order of implementation (test-first per layer)

```text
1. Value objects & enums             → tests/unit/domain/test_value_objects.py
2. Exercise aggregate                → tests/unit/domain/test_exercise.py
3. Routine aggregate                 → tests/unit/domain/test_routine.py
4. MetricValidationPolicy            → tests/unit/domain/test_metric_validation.py
5. SessionSnapshotFactory            → tests/unit/domain/test_session_snapshot_factory.py
6. WorkoutSession aggregate          → tests/unit/domain/test_workout_session.py
7. CompletionPolicy                  → tests/unit/domain/test_completion_policy.py
8. WorkloadCalculator                → tests/unit/domain/test_workload_calculator.py
9. AdherenceCalculator               → tests/unit/domain/test_adherence_calculator.py
```

### Domain test rules

- **No mocks**. No `unittest.mock`. No fakes.
- **No database**. No SQLite, no SQLAlchemy, no fixtures.
- **No HTTP**. No FastAPI test client.
- Pure Python construction of domain objects and assertion against their state.
- Use `pytest` with `pytest-cov`. Coverage gate: 90% on `src/praxis/domain/`.

### Application test rules (Phase 2)

- Use simple in-memory fakes implementing the repository ports:
  ```python
  class InMemoryRoutineRepository:
      def __init__(self) -> None:
          self._store: dict[RoutineId, Routine] = {}
      def save(self, routine: Routine) -> None:
          self._store[routine.id] = routine
      def get_by_id(self, routine_id: RoutineId) -> Routine | None:
          return self._store.get(routine_id)
      ...
  ```
- Fakes live in `tests/unit/application/fakes.py`.
- No mocks. Fakes implement the port Protocol fully.

---

## 13. Serialisation Boundaries

The domain layer has **zero serialisation code**. No `to_dict()`, no `model_dump()`, no JSON methods on domain objects.

Serialisation happens exclusively at:
1. **Application DTOs** (`application/dtos/`) — translate domain objects into output structures.
2. **Infrastructure persistence** (`infrastructure/persistence/`) — map domain objects to/from ORM models.
3. **Interface layer** (`interfaces/fastapi/`) — Pydantic schemas for HTTP request/response.

This means `SetPerformance` has no `to_dict()`. The persistence adapter is responsible for knowing how to store and restore it.

---

## 14. Implementation Phase Sequence

| Phase | Scope | Entry Criterion | Done When |
| :--- | :--- | :--- | :--- |
| **Phase 0** | Implementation Readiness | Specs baselined | All Phase-1-blocking ambiguities resolved; implementation conventions frozen; remaining questions explicitly deferred |
| **Phase 1** | Pure Domain Foundation | Phase 0 complete | All domain tests green; `ruff` and `pyright strict` clean |
| **Phase 2** | Application Layer | Phase 1 complete | All use case tests green with in-memory fakes |
| **Phase 3** | Infrastructure | Phase 2 complete | Integration tests pass with SQLite |
| **Phase 4** | FastAPI Interface | Phase 3 complete | OpenAPI spec generated, integration round-trips pass |
| **Phase 5** | Containerisation | Phase 4 complete | Docker Compose stack runs, Authelia header adapter wired |

> [!NOTE]
> **Coverage and linting are project quality policy, not domain architecture.** The 90% coverage gate and `pyright strict` requirement are enforced by the pre-push hook and `pyproject.toml` configuration (see `AGENTS.md §5`). They apply across all phases, but they are toolchain constraints — they do not determine whether a concept belongs in the domain layer.

---

## 15. Open Questions

Questions are classified by when they become blocking.

### Resolved

| # | Question | Resolution |
| :--- | :--- | :--- |
| **OQ-2** | `Phase.end_week = None` means open-ended. What should `get_current_phase()` return when no phase matches the current week? | **Resolved**: Return the phase with the highest `start_week` (the last-defined phase). This implements "Week 3+" semantics from the reference training program. An empty `phases` list raises `ValueError` at construction. |

### Deferred (not blocking Phase 1)

| # | Question | Blocking |
| :--- | :--- | :--- |
| OQ-1 | `WorkoutSession.routine_id` is nullable for ad-hoc sessions. Should `session_date` uniqueness be enforced at application or DB level? | Phase 2 |
| OQ-3 | Weight unit preference — stored on `User.profile` or derived per-request? | Phase 2 |
| OQ-4 | `ExercisePrescription.target_weight = None` is valid (bodyweight). How is this communicated to the snapshot consumer / UI? | Phase 4 |
| OQ-5 | Exercise catalog seeding (FR-EX-1) — migration fixture or Python data file? | Phase 3 |
