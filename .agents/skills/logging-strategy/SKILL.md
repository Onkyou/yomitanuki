---
name: logging-strategy
description: Guides correct structured logging decisions for wegziel. Use when adding log statements, reviewing logging coverage, deciding between log levels, or fixing improperly instrumented code. Use when a file uses bare slog.* package functions instead of commonlog.LoggerFromContext, or when unsure whether to log at DEBUG vs INFO vs WARN vs ERROR.
---

# Logging Strategy

## Quick Reference — Level Decision

| Level   | Question to ask                                           | Examples                                                      |
| ------- | --------------------------------------------------------- | ------------------------------------------------------------- |
| `ERROR` | Did something fail we cannot recover from in this flow?   | Repo error, outbox publish failed, nil where non-nil required  |
| `WARN`  | Did something abnormal happen that we _can_ recover from? | Reference image skipped for a missing rendition, push token rejected by the provider |
| `INFO`  | What high-level intent or outcome occurred?               | "hunt started", "attempt submitted", "adjudication recorded"   |
| `DEBUG` | _How/why_ was this code path taken?                       | Branch chosen, computed count, resolved ID, inputs to the judge call |

> **Rule of thumb:** `INFO` = _what happened_. `DEBUG` = _why that path_.
>
> **One exclusion, and it is shipped, not aspirational:** an error you are returning from a
> REST handler is not yours to log at all — `httputil.WriteError` logs it, ERROR for a 5xx
> and DEBUG for a 4xx. See *A 4xx is not an ERROR* below.

---

## The One Rule: Always Use the Context Logger

```go
// ✅ Correct — carries request_id, user_id and session_id
log := commonlog.LoggerFromContext(ctx)
log.InfoContext(ctx, "attempt submitted", "attempt_id", cmd.AttemptID)

// ❌ Wrong — loses request_id, user_id and session_id
slog.InfoContext(ctx, "attempt submitted", "attempt_id", cmd.AttemptID)
import "log/slog"
```

Any file that imports `"log/slog"` and calls `slog.*Context(ctx, ...)` directly is
incorrect. Replace with `commonlog.LoggerFromContext(ctx).*Context(...)`.

**Do not store `*slog.Logger` as a struct field** in request handlers or per-request-scoped types. Always derive from the request context via `commonlog.LoggerFromContext(ctx)`. The stored-logger pattern silently strips `request_id` and `user_id` from log lines because the field is captured before middleware enriches the context.

This applies to the **non-`Context` form too** — a bare `slog.Info(...)` /
`slog.Error(...)` is just as wrong as `slog.InfoContext(...)`: it loses
`request_id`, `user_id`, and `session_id`. Grep for both forms:

```
# catches slog.Info(  slog.InfoContext(  slog.Warn(  ... — any bare slog.* level call
grep -rnE 'slog\.(Info|Warn|Error|Debug)' internal/
```

Any hit outside `internal/common/log/` (which defines the wrapper) is a bug.
The only sanctioned bare-`slog` sites are pre-context boot logging in `cmd/`
(before any request/message boundary exists).

Do **not** store a captured logger in a struct field either
(`logger: slog.Default().With("component", …)` at construction time strips the
per-request fields, because the field is captured before middleware enriches the
context). Retrieve `commonlog.LoggerFromContext(ctx)` inside each method instead.

---

## Request-scoped trace fields (`internal/common/reqctx`)

`request_id`, `correlation_id`, `user_id` and `session_id` are owned by the `reqctx`
package, not `commonlog`. `commonlog` owns only the `*slog.Logger` in context; `reqctx`
depends on it (one-way) to enrich that logger when a boundary stamps a field.

**Wegziel has no tenancy** — no organisations, no RLS, no `set_config`, no org-resolution
middleware (see `architecture-conventions`). If you find yourself reaching for an
`organisation_id` or `tenant_id` log field, you are porting a layer this project
deliberately does not have.

`session_id` is the wegziel-specific one and it is load-bearing: two of the four success
metrics are computed from it, so it must be stamped at the boundary and must be the
server's value, not a client claim.

- **Only boundary middleware writes the holder** — the HTTP `LoggingHandler`, the Watermill
  `LoggingMiddleware`, and the auth resolution middleware. Module and handler code **never**
  calls the `reqctx.With*` setters.
- **Setters return a new context you MUST propagate** (`ctx = reqctx.WithUserID(ctx, id)`
  then `r.WithContext(ctx)`). Dropping the returned ctx updates the holder but not the
  logger — a half-applied state nothing catches.

---

## Never log a coordinate

A log line is a wire format. `coord.Point`'s `MarshalJSON` returns an error so it cannot be
serialized into a response (see `coordinate-boundary`) — **but `slog` never calls
`MarshalJSON`**, and neither does `fmt`. `slog.Any("ziel", z)` or `%v` on a struct holding a
`Point` will happily print the latitude and longitude into a file that gets shipped,
grepped and retained.

Close all three doors on the type itself:

```go
func (Point) MarshalJSON() ([]byte, error) {          // JSON responses
    return nil, errors.New("coord.Point must never be serialized")
}
func (Point) LogValue() slog.Value {                   // structured logs
    return slog.StringValue("coord.Point(redacted)")
}
func (Point) String() string {                         // fmt, %v, error strings
    return "coord.Point(redacted)"
}
```

`LogValue` is the one people forget, and it is the one that matters most: an accidental
coordinate in a response is caught by the route sweep, while an accidental coordinate in a
log is caught by nobody.

---

## Workflows

### Adding Logging to a New Handler

1. Retrieve the logger at the top of `Handle`: `log := commonlog.LoggerFromContext(ctx)`
2. `INFO` at entry: handler intent + primary domain identifiers (IDs, band, `session_id`)
3. **Do not log the error you are returning.** Return it. `httputil.WriteError` logs every
   error that reaches a REST handler exactly once, and at the level the *status* earns:
   ERROR for a 5xx, DEBUG for a 4xx (`TestWriteError_LogsClientErrorsAtDebugNotError`)
4. `DEBUG` for internal branches: resolved IDs, computed counts, chosen code paths
5. Inside `RunInTransaction`: re-derive `txLog := commonlog.LoggerFromContext(txCtx)` and use it

### A 4xx is not an ERROR

**Logging every returned error at ERROR is how an error log stops being read.** A validation
failure is the caller's problem and there is nothing for an operator to do about it; a
handler that logs one at ERROR *and* returns it also double-logs — `WriteError` logs it
again — so an operator scanning for incidents finds two lines per rejected form and none of
them an incident. The rule is shipped in `internal/common/httputil`, not merely written
here, and it is pinned by a test, so a handler that reinstates the old workflow is
disagreeing with code.

The cause is not lost by the demotion: `WriteError` renders `Error()`, cause included, into
the DEBUG line, which is where "why did this path run" belongs. What still earns an
explicit `ERROR` in a handler is a failure with **no** error path out — a background or
subscriber flow with no `WriteError` to reach, a best-effort call whose failure you swallow,
a partial write you decided to continue past.

### Deciding What to Log at DEBUG

Add `DebugContext` when a future reader would ask _"which branch ran here?"_:

- Which `Ziel` selection branch ran — warmth-armed, hot cell, or fallback
- The resolved distance `Band` and hex `Cell` a request landed in (never the coordinate)
- Count of evidence frames or reference images before processing
- Inputs to any external call (blob upload, the judge adapter, push delivery)
- Result of a fast-path check — already-discovered, already-reported

### What NOT to Log

- SQL query text (use pgx tracing instead)
- Request/response bodies (PII risk)
- Per-iteration lines inside large loops (log the count)
- Inside domain constructors (`NewZiel`, `NewAttempt`) — pure functions; callers log errors
- The same message at both INFO and DEBUG with identical fields
- An error you are returning to a REST handler — `WriteError` owns that line

---

## Enabling Debug Level at Runtime

```go
// cmd/monolith/main.go
logger, level := commonlog.NewJSONLogger(os.Stdout, cfg.LogLevel)
slog.SetDefault(logger)

// `level` is the runtime flip. Hold it in the composition root and DEBUG can be
// turned on for a live incident without a restart that loses the incident — a
// level baked into HandlerOptions can only be changed by building a new logger,
// which every context already carrying the old one keeps using.
level.Set(slog.LevelDebug)
```

`commonlog.NewJSONLogger` is the one sanctioned way to build the process logger. Hand-rolling
`slog.NewJSONHandler` here works and is what this snippet used to show — but it puts the
`LevelVar` wiring at the call site, where it is one refactor away from being replaced by a
plain `slog.LevelInfo` and the flip disappearing.

Set `DEBUG=true` (or equivalent config key) in `.env` for local development.

---

## Checklist

- [ ] No bare `slog.*Context` calls — all log via `commonlog.LoggerFromContext(ctx)`
- [ ] `INFO` at command handler entry with primary domain IDs
- [ ] Errors returned to a REST handler are **not** logged on the way out — `httputil.WriteError` logs them once, ERROR for a 5xx and DEBUG for a 4xx
- [ ] `ERROR` reserved for a failure with no error path out (subscriber, background job, swallowed best-effort call), with `"error", err`
- [ ] `WARN` for recoverable-abnormal paths (not errors, not noise)
- [ ] `DEBUG` for branch decisions and computed values inside the handler
- [ ] `txLog` derived from `txCtx` inside `RunInTransaction`, not outer `log`
- [ ] No logging inside domain constructors or pure functions
