---
name: testability-seams
description: The four sources of ambient nondeterminism that must be ports from the first commit — time, identity, randomness and network — and the two carve-outs where the seam must NOT be used. Apply when writing any aggregate, handler, worker or adapter; when reaching for time.Now, a UUID, a random pick or an HTTP client; or when reviewing anything that will need to be asserted on twice.
---

# Testability Seams

Every source of ambient nondeterminism is a **port, injected from the first commit**.

This is the most expensive lesson carried over from `al-backend`: its clock convention was
adopted after the code existed, and at last count **71 non-test `time.Now()` calls still sit
inside `domain/` packages**. Freezing the clock in a test there does not freeze the columns
those packages stamp — communication decides a 24-hour service window on the injected clock
while stamping `created_at` from ambient `time.Now()`. A convention introduced after the code
is a migration. Introduced before it, it is a habit.

## The four sources

| Source | Seam | Rule |
|---|---|---|
| **Time** | `common/clock.Clock` — one method, `Now() time.Time`, UTC | Handlers, services and workers hold a `Clock`. **Aggregates never do.** They take `now time.Time` as their **last fixed parameter**, before any variadic. A handler reads the clock **once per command**, so every timestamp in one transaction agrees |
| **Identity** | `common/idgen` with a swappable source | A KSUID embeds a timestamp, so **an id generator is a second clock a frozen `Clock` does not control**. Without `SetSource` + a deterministic source, a replayed test mints different ids and nothing asserting on one passes twice |
| **Randomness** | injected source | The pseudonym generator picks word pairs (DESIGN §7.8). Unseeded, no test can assert what a registration produced |
| **Network** | ports — `Judge`, `BlobStore`, `Notifier` | The judge has a fake and a golden-set regression; the blob store has a conformance suite run against every backend; the notifier collects instead of sending |

Keep `Clock` at **exactly one method**. No `Sleep`/`After`/`Tick` — Go's `testing/synctest`
fakes timers and context deadlines for a goroutine bubble with no production change.

## The two carve-outs

State these, or someone will "fix" them later:

1. **Elapsed time uses raw `time.Since`.** A `Clock` returns wall-clock instants; `Now()`
   returning UTC strips the monotonic reading, which makes the value safe to store and
   useless for measuring durations. `time.Since(x)` where `x` came from a database row or a
   message is *not* elapsed-time measurement — neither operand has a monotonic reading — so
   use `clock.Now().Sub(x)` there.
2. **Anything that must not be client-influenced uses server-side SQL `now()`.** Leases,
   expiries and sweep watermarks. A client-driven lease is a split-brain source.

A `time.Now()` that is never persisted, never sent, and never drives a decision is not a
defect and must not be swept.

## The mechanical guard

One `forbidigo` rule banning `time.Now` under `internal/*/domain/**`, from the first commit.
Free now; a multi-slice migration in December.

## Two seams that are design properties, not packages

- **The warmth ramp is a pure function** of the device's own position and the hex warmth
  field (DESIGN §9.2, Loop B). Keeping it pure is what lets it be table-tested at a desk
  instead of tuned on foot in the December dark.
- **The curator tool logs a GPS trace from September** (DESIGN §11). October's fieldwork then
  yields recorded traces for free, and November's "tune the ramp outdoors" becomes replaying
  them plus one confirmation walk.

## The test pyramid this buys

- **Pure domain, table tests:** the §7.5 state machine is literally a table. Plus confidence
  arithmetic, solar-position availability, pseudonym generation and its pair blocklist,
  retention classification, and the warmth ramp.
- **The judge:** never unit-test the model. A **golden set** of 60–100 hand-labelled real
  captures — collected during October's seeding, where every reference shoot yields free
  negatives — run as a scored regression, never in CI. It is simultaneously the November
  tuning instrument and §14's false-negative measurement.
- **Two-phase capture:** contract tests over in-memory adapters — out-of-order arrival,
  duplicate upload, one half missing, `EvidenceComplete` gating the verdict, timeout → queue
  → **idempotent** deferred delivery. A reveal shown twice devalues the one moment §4 builds
  to; this is the highest-value integration test in the system.
- **Repositories:** conformance suites run against **both** the in-memory and Postgres
  adapters. The rule that makes them honest: **a persisted field is asserted through Update,
  never only through Add→Get** — the two adapters enforce the same rule by different
  mechanisms, so a rule implemented in one place passes every unit test and fails in
  production.
- **Sweeps:** the coordinate leak sweep and the route-auth sweep **allow-list exemptions, never
  skip them.** `al-backend` proved this by mutation: with a plain skip, downgrading a route to
  public kept the suite green.

## Checklist

- [ ] No `time.Now()` in `domain/` — the aggregate takes `now` as a parameter
- [ ] The handler read the clock **once**, not per call
- [ ] Ids come from `idgen`, not `ksuid.New()` directly
- [ ] Any random pick draws from an injected source
- [ ] Every external call is behind a port with a fake
- [ ] A new repository method is covered by the conformance suite, not just one adapter
- [ ] A new sweep exempts by allow-list with a written reason, never by skipping
