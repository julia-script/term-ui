# Wasm Boundary

## Purpose

Ownership and lifetime contract of the wasm↔JS interface: how memory crosses the boundary in both directions, who frees what, and the guarantees application code can rely on.

## Requirements

### Requirement: Transient outputs live in a reply arena

Every export returning transient data (text, geometry, hit-test results, dumps, child lists) SHALL write it into a reply arena owned by the wasm side. The data SHALL remain valid until the next call into any wasm export, at which point the arena MAY be reset. The client SHALL NOT free transient outputs.

#### Scenario: output survives until the next call

- WHEN an export returns a transient buffer and the client reads it before making another wasm call
- THEN the read observes the complete, unmodified output

#### Scenario: no client-side free

- WHEN a client has consumed any number of transient outputs
- THEN no free/release call for those outputs is required or available, and steady-state memory does not grow with the number of such calls

### Requirement: Transient outputs are not size-capped

Variable-length results (hit-test lists, dumps, text) SHALL be sized to their content rather than truncated to a fixed-capacity buffer.

#### Scenario: large hit-test result

- WHEN a hit test intersects more items than any previous fixed buffer capacity (e.g. >512)
- THEN all intersecting items are returned

### Requirement: Raw pointers do not escape the client wrapper layer

The JS wrapper layer SHALL materialize every wasm output into ordinary JS values (strings, arrays, objects) before returning to application code. Application-facing APIs SHALL NOT expose wasm memory addresses or views into wasm memory.

#### Scenario: value stability across subsequent calls

- WHEN application code obtains a value (e.g. a node's text) and then performs further wasm calls, including ones that reallocate or grow wasm memory
- THEN the previously obtained value is unaffected

### Requirement: Inbound arguments are freed by the callee

For arguments allocated in wasm memory by the client (strings, byte buffers), ownership SHALL transfer on the call: the export consumes and frees them. The client SHALL NOT use or free such an argument after the call.

#### Scenario: repeated string-taking calls

- WHEN a client makes many calls passing allocated strings (styles, text, attribute names/values)
- THEN steady-state memory does not grow with the number of calls

### Requirement: Long-lived handles have explicit disposal

Objects with identity across calls (tree/document, renderer, input buffer, selection) SHALL be created and destroyed through explicit lifecycle exports, and disposal SHALL release all memory owned by the object.

#### Scenario: full lifecycle is leak-free

- WHEN a client creates a document, builds and mutates content, paints, uses selection and input, then disposes everything
- THEN a subsequent leak check reports zero surviving allocations

### Requirement: Steady-state operation does not accumulate memory

Repeated mutate→layout→paint cycles on a live document SHALL NOT grow live allocations beyond a stable working set.

#### Scenario: high-water mark stabilizes

- WHEN hundreds of mutation/layout/paint cycles run against one document
- THEN the live-allocation count after the run equals the count after the first few warm-up cycles
