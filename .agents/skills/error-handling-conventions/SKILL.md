---
name: error-handling-conventions
description: How to define, propagate, and map errors in wegziel. Covers domain error slugs, the shipped httputil.WriteError/FromDomainError mapping, and the `_ =` discard rule. For where validation checks belong, see `validation-placement`. Apply when writing domain errors, HTTP handlers, or error translation logic.
---

# Error Handling Conventions

Source: [3dots labs — Clean Architecture](https://threedots.tech/post/introducing-clean-architecture/) and [Common anti-patterns](https://threedots.tech/post/common-anti-patterns-in-go-web-applications/).

---

## The Core Principle: Port-Agnostic Domain Errors

Domain and application layers must return errors that are **independent of transport protocol**. An error returned from a command handler must not encode HTTP status codes, gRPC codes, or any port-specific information.

This allows the same business logic to be called from HTTP handlers, event subscribers, background jobs, and tests — without each entry point needing to understand domain internals.

---

## Domain Error Types

Use `commonerrors.NewValidationError` (and equivalent constructors) to create typed errors with stable slugs:

```go
// domain/errors.go (or inline in the domain file)
var (
    ErrLeaseNotFound       = commonerrors.NewNotFoundError("lease-not-found", "lease not found")
    ErrLeaseAlreadyActive  = commonerrors.NewValidationError("lease-already-active", "lease is already active")
    ErrInvalidRentAmount   = commonerrors.NewValidationError("rent-amount-invalid", "rent amount must be positive")
)
```

Slug naming convention: `<aggregate>-<condition>` in kebab-case. These slugs are the **stable public contract** — do not rename them once in production.

**This document is the authority on slug format, and there are two shapes, not two conventions.** `<aggregate>-<condition>` is the sentinel form above; validation errors take the fuller `{prefix}-{handler-or-domain}-{field}-{rule}` fixed at the bottom of this file. A domain invariant is the second shape with the *aggregate* standing in for the handler prefix and no `cmd-`/`qry-`/`rest-`, which is why `domain-aggregate-design` writes `organisation-name-empty`: there is no handler to name. Both reduce to one lexical contract — lowercase alphanumeric words joined by single hyphens — and `commonerrors.ValidSlug` is that contract in code, so every package asserts its own slugs against it rather than re-deriving it.

---

## Error Classification

The `commonerrors` categories (`internal/common/errors/domain_error.go`) and how the shipped mapper translates them:

| Constructor | Slug suffix convention | HTTP status |
|------|----------------------|-------------|
| `NewValidationError` | `-invalid`, `-empty`, `-required` | **400 Bad Request** |
| `NewNotFoundError` | `-not-found` | 404 Not Found |
| `NewMethodNotAllowedError` | `-method-not-allowed` | 405 Method Not Allowed (caller sets the `Allow` header — see `cmd/monolith/wiring/methodprobe.go`) |
| `NewConflictError` | `-already-exists`, `-duplicate`, and aggregate-state guards (`-not-draft`, `-not-in-review`, `-archived`, …) | 409 Conflict (RFC 9110 §15.5.10) |
| `NewPreconditionFailedError` | a precondition the CLIENT supplied in a request header — `If-Match`/`If-Unmodified-Since` — evaluated false | 412 Precondition Failed (RFC 9110 §15.5.13) |
| `NewAuthenticationError` | `-missing-auth`, token problems | 401 Unauthorized |
| `NewAuthorizationError` | `-forbidden`, role/ownership denials | 403 Forbidden |
| `NewTooManyRequestsError` | `-rate-limited`, `-too-soon` | 429 Too Many Requests |
| `NewInternalError` | operator-facing config/infra faults | 500 (message shown — an explicit author opt-in) |

There is no `ForbiddenError` type and validation maps to **400**, not 422 — those were early drafts.

**429 is in the taxonomy from the first commit** because DESIGN §7.8 pins a rate limit on
pseudonym regeneration. Without a category the module that needs it answers 400 or hand-rolls
a status — and the taxonomy is a frozen wire contract, so adding the category later means
changing a status a client already saw.

A bare `*DomainError` — `NewDomainError`, no category — maps to **400**: it means the caller
broke a rule nobody classified, which is the caller's problem, not the server's.

---

## HTTP Error Mapping (shipped)

The central mapper is `internal/common/httputil/api_error.go` (`FromDomainError`) behind `httputil.WriteError(ctx, w, err)` — the **only** error-response mechanism for REST handlers. Unmapped errors are genericised to a scrubbed 500 (`internal-server-error`) and logged server-side; a typed `InternalError`'s message passes through because the author opted in. Handlers therefore never branch on error types:

```go
func (h *Handler) CreateFoo(w http.ResponseWriter, r *http.Request) {
    result, err := h.app.Commands.CreateFoo.Handle(r.Context(), cmd)
    if err != nil {
        _ = httputil.WriteError(r.Context(), w, err)
        return
    }
    _ = httputil.Write(r.Context(), w, http.StatusCreated, &result)
}
```

**Both take `ctx` first, and `Write`'s reason is not symmetry with `WriteError`'s.** Marshalling
can fail, and the failure that matters is `coord.Point.MarshalJSON`, which always errors so a
Ziel coordinate cannot be serialised into a response (`coordinate-boundary`, layer 1). That is
the most serious thing this package can witness, and `logging-strategy` permits logging only
through the context logger — so without `ctx` the line recording it would carry no `request_id`
and no `session_id`, which for *that* event is barely better than no line at all.

### The wire `Message` comes from `Description`, never `Error()`

`DomainError.Error()` appends the `Cause` — that rendering is for the log, not the client. Using
it on the wire would mean that wrapping a driver error *into* a category **disables the scrub**,
which is precisely backwards: wrapping is exactly what `WrapConflictError` exists for, and the
postgres adapter calls it on every unique violation. The cause is not lost: it stays in the
chain, and `WriteError` renders `Error()` server-side — at ERROR for a 5xx, at DEBUG for a 4xx,
because logging every rejected form at ERROR is how an error log stops being read.

This is a **latent bug in the `al-backend` original**. Do not "restore parity" with it.

**The same rule binds at the other end: never mint a `Description` from `err.Error()`.**
`NewValidationError(slug, err.Error())` routes straight round the scrub — the mapper
faithfully copies out a description the author filled with a driver message, a hostname or a
struct-field name, and no amount of care in `httputil` can tell that apart from a sentence
written for a client. The description **is** the wire contract; the cause goes in `Cause` or
behind a `%w`, where `WriteError` renders it at the levels just described. A `json.Decode`
error is the common case and the most tempting one: it reads as harmless and echoes your Go
field names and types back to the caller. `validation-placement`'s Tier-3 example is the
canonical shape — a package-level sentinel holding the stable slug and a fixed description,
and `fmt.Errorf("%w: %w", sentinel, err)` at the call site.

### The precedence is a fixed priority table with no knowledge of nesting

`FromDomainError` walks the chain once per category with `errors.As` and has no idea which
category was outermost. A chain carrying two categories therefore answers by this table
whichever way round it was wrapped:

| Rank | Category | Status | The question it answers |
|---|---|---|---|
| 1 | `AuthenticationError` | 401 | who are you |
| 2 | `AuthorizationError` | 403 | may you |
| 3 | `TooManyRequestsError` | 429 | may you *right now* |
| 4 | `ConflictError` | 409 | does it clash (uniqueness) or is the aggregate's own state right for this (a status-ladder guard) |
| 5 | `PreconditionFailedError` | 412 | did the precondition the CLIENT attached to this request (`If-Match`) hold |
| 6 | `NotFoundError` | 404 | does it exist |
| 7 | `MethodNotAllowedError` | 405 | does it exist, called wrong |
| 8 | `ValidationError` | 400 | is the input well-formed |
| 9 | `InternalError` | 500 | ours — message shown, the author opted in |
| 10 | bare `*DomainError` | 400 | uncategorised; the caller broke a rule |
| 11 | anything else | 500 | scrubbed |

**Identity ranks first, and that is a security property rather than an aesthetic one.** With
`Conflict` above `Authorization`, an adapter wrapping "you may not touch this" into "that slug
is taken by ziel `zl_7f3a`" answers 409 and discloses both that the resource exists *and its
id* to an actor with no right to know either. "May you?" is answered before "does it clash?"
and before "does it exist?". Pin both nesting directions in tests — the table is only load-
bearing if a reordering fails something.

**Adapter half of Conflict:** an app-layer uniqueness pre-check is a TOCTOU window — the postgres adapter must map the constraint loss to the *same* typed sentinel, via `WrapConflictError`, which preserves the app layer's slug, so both paths converge on 409 with one identity rather than two.

**The helpers that make this a one-liner are not built yet.** `IsUniqueViolation` and `ViolatesConstraint(err, "<constraint_name>")` belong to `common/postgres`, which is **WP0.5**; the orientation project has them at `internal/common/postgres/pgerrors.go` and the port picks them up. Until then there is no adapter in this repo to write this in — this is the pattern the first postgres adapter builds, not one it can copy from a path here.

---

## Where Validation Lives

Validation belongs in the **domain layer**, not in HTTP handlers or application layer. See [`validation-placement`](../validation-placement/SKILL.md) for the full three-tier rule, slug placement, and worked examples. The error contract above is what flows out of validated domain code; the placement skill says where to put the check.

---

## Error Wrapping Rules

- Wrap infrastructure errors with context: `fmt.Errorf("failed to save lease: %w", err)`
- Do NOT wrap domain errors with extra context that changes the type — use `%w` to preserve unwrapping.
- Do NOT convert domain errors to strings before returning from the application layer.

```go
// Wrong — loses type information
return fmt.Errorf("lease creation failed: %s", err.Error())

// Right — preserves type for the HTTP mapper
return fmt.Errorf("lease creation failed: %w", err)
```

---

## `fmt.Errorf` Without `%w` Is Only for Non-Domain Errors

Use bare `fmt.Errorf` (without `%w`) only for internal programmer errors that should always map to 500:

```go
return fmt.Errorf("handler constructed without a repository")  // programming error, always 500
return fmt.Errorf("failed to resolve tx: %w", err)             // wrap infra error, preserves type
```

**"No transaction in context" is not one of these — it is `commonerrors.ErrTxRequired`.**
Both transaction sentinels ship in `internal/common/errors/tx.go`: `InternalError`s, so still
500, but 500 with a slug an operator can grep (`tx-required`, `tx-nested`) instead of an
anonymous one, and matchable with `errors.Is` from an app handler or a conformance suite
without importing `common/postgres` and dragging pgx into a layer that must not name it. That
file is explicit that WP0.5's `RequireTx` **returns these values rather than minting its own**
— an anonymous `fmt.Errorf` at that seam is exactly the defect it argues against, because
`errors.Is` then holds nowhere. The rule generalises: a programming error that already has a
sentinel is returned, not re-minted.

---

## Never Discard With `_ =`

Every error must be either returned to the caller or logged at the appropriate level. **No `_ = someCall()` to silence an error**, including in deprecated modules.

The two legitimate exceptions:

- **Best-effort cleanup in rollback paths**, where the original error is already being returned. Log the cleanup error at `WARN`:
  ```go
  if err := tx.Rollback(ctx); err != nil {
      txLog.WarnContext(ctx, "rollback failed", "error", err)
  }
  return originalErr
  ```
- **HTTP response-write errors**, after the status code is already sent. Log at `WARN`:
  ```go
  if _, err := w.Write(body); err != nil {
      logger.Warn("write response", "error", err)
  }
  ```
  This is why `_ = httputil.Write(...)` / `_ = httputil.WriteError(...)` is the sanctioned
  handler form above rather than a lapse: the return can only ever report a write that
  happened after the status went out, and `httputil.send` logs it at WARN **because** the
  documented call site discards it. `errcheck` gates the whole tree, so the bare-statement
  form is not the third option — it fails `make gate`.

---

## Validation Error Slugs (project format)

Use `commonerrors.NewValidationError(slug, description)` for all static validation in command/query `Validate()` methods. Never `errors.New` for validation.

Slug format: `{prefix}-{handler-or-domain}-{field}-{rule}` in kebab-case.

| Layer | Prefix | Example |
|---|---|---|
| Command handler | `cmd-` | `cmd-create-user-username-required` |
| Query handler | `qry-` | `qry-get-incident-id-required` |
| REST handler | `rest-` | `rest-approve-tool-call-body-invalid` |
| Service-layer param struct | none — use the domain prefix | `iam-ensure-organisation-external-id-required` |

The slug is the machine-readable identity of the error and a stable contract. Once shipped, don't rename.

---

## Checklist

Before committing error handling code:

- [ ] Domain errors use `commonerrors` types with stable slugs
- [ ] No HTTP status codes in domain or application layer
- [ ] `errors.As` used for type-checking, not `err.Error()` string matching
- [ ] Infrastructure errors wrapped with `%w` to preserve the chain
- [ ] HTTP handlers use `httputil.WriteError`, not ad-hoc status decisions
- [ ] No `Description` built from `err.Error()` — the description is for the client, the cause for the log
- [ ] No `_ = someCall()` — every error returned or logged at the appropriate level
- [ ] `Validate()` methods use the slug format above
