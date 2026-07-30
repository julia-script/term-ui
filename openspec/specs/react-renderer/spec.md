# React Renderer

## Purpose

The React renderer binds react-reconciler to the term-ui DOM so that building a terminal app with React behaves like building for the browser: elements mount and unmount cleanly, props diff correctly, Suspense and transitions work, and input-driven updates are scheduled at the right priority.

## Requirements

### Requirement: Host instance lifecycle
The renderer SHALL create, attach, reorder, and remove DOM elements and text nodes to mirror the committed React tree, and SHALL release the underlying native handle of every host instance React deletes, once React has fully detached it. Rendering the same tree shape twice SHALL produce the same terminal output.

#### Scenario: Mount, reorder, unmount round trip
- **WHEN** a component renders a list, reorders it via keys, then unmounts it
- **THEN** the painted output reflects each committed state in order and no stale content remains after unmount

#### Scenario: Unmounted instances do not leak
- **WHEN** a component subtree is mounted and unmounted repeatedly
- **THEN** native memory in use does not grow with the number of cycles

### Requirement: Prop updates diff at commit
On every update the renderer SHALL apply the difference between previous and next props for: style, `contentEditable`, event handler props, and text content. Unchanged props SHALL NOT cause redundant native calls.

#### Scenario: contentEditable toggles after mount
- **WHEN** a mounted element re-renders with `contentEditable` changed
- **THEN** the element's editability reflects the new value

#### Scenario: Event handler identity changes
- **WHEN** an element re-renders with a new function for the same event prop
- **THEN** the old handler no longer fires and the new one does, exactly once per event

### Requirement: Suspense visibility
The renderer SHALL hide host instances (elements and text) without unmounting them when React suspends already-mounted content, and restore them when it resumes. Hidden content SHALL NOT be painted and SHALL NOT be hit-testable.

#### Scenario: Fallback over mounted content
- **WHEN** a mounted subtree re-suspends and a fallback is shown
- **THEN** the suspended subtree disappears from the painted output while the fallback is visible, and reappears with its state intact when the promise resolves

### Requirement: Concurrent feature stability
Every React feature reachable through the public API of the pinned React version (transitions, `Suspense` retries, portals, fragment refs, `useId`, StrictMode) SHALL either work or degrade gracefully; none SHALL crash the renderer with a missing-host-method error.

#### Scenario: startTransition commit
- **WHEN** state is updated inside `startTransition`
- **THEN** the update commits and paints without error

### Requirement: Input-derived update priority
Updates triggered by discrete input (key presses, mouse clicks) SHALL be scheduled at discrete priority; updates triggered by continuous input (mouse movement, wheel) SHALL be scheduled at continuous priority; all other updates default. The renderer SHALL never resolve an update to the "no priority" sentinel.

#### Scenario: Click handler state update preempts background work
- **WHEN** a click handler sets state while lower-priority work is pending
- **THEN** the click's update renders ahead of the pending work

### Requirement: Terminal-safe error surfacing
Errors reaching the root error handlers SHALL be reported without corrupting the terminal display: the renderer SHALL NOT write raw error text into the alternate screen while it owns the terminal.

#### Scenario: Uncaught render error
- **WHEN** a component throws during render with no error boundary
- **THEN** the error is reported to the user after the terminal is restored (or via a mechanism that does not interleave with painted output), and the process does not hang

### Requirement: Renderer package hygiene
Importing the renderer SHALL have no side effects on the consumer's environment: no files created, no logging, no debug instrumentation active in published builds.

#### Scenario: Import in a clean directory
- **WHEN** an app imports the renderer package and renders
- **THEN** no log or artifact files appear in the working directory
