# Scroll & Overflow

Overflow clipping and scrollable-container behavior: how oversized content is clipped, how scroll state behaves, and how scrolling interacts with input, geometry, and the caret.

## ADDED Requirements

### Requirement: Overflow clipping

A container with `overflow: hidden` or `overflow: scroll` SHALL clip descendant painting to its bounds, including partially visible text lines; `overflow: visible` SHALL NOT clip. Nested clip regions SHALL intersect.

#### Scenario: oversized content is clipped

- WHEN a `hidden`/`scroll` container holds content taller than its box
- THEN painted output contains only the rows inside the container's bounds, and rows outside show surrounding content unaffected

#### Scenario: nested containers clip to the intersection

- WHEN a scroll container is nested inside another clipping container and their regions partially overlap
- THEN content paints only inside the intersection

### Requirement: Scroll state and clamping

A scrollable container SHALL expose `scrollTop`/`scrollLeft` that are clamped to `[0, scrollSize − clientSize]` per axis, where scrollSize reflects the container's laid-out content extent. Setting an offset SHALL shift descendant geometry and repaint accordingly.

#### Scenario: clamping

- WHEN `scrollTop` is set beyond the maximum (or negative)
- THEN the effective value is the clamped bound and rendering matches it

#### Scenario: scrolled content shifts

- WHEN `scrollTop` is N rows on a container with wrapped text
- THEN painting shows the content starting N rows into the container, with earlier rows clipped away

### Requirement: Scrolling is an invalidation like any other

Changing a scroll offset SHALL produce rendering identical to a freshly laid-out tree with the same offset (no stale content from caching).

#### Scenario: oracle parity with scroll ops

- WHEN random mutation sequences including scroll-offset changes run incrementally with caches
- THEN geometry and paint match a cold rebuild replaying the same sequence

### Requirement: Wheel and keyboard scrolling

A wheel event SHALL scroll the nearest scrollable ancestor of the element under the pointer by the wheel delta (clamped); PgUp/PgDn SHALL scroll the active scroll container by one client-height page. Applications MAY cancel via `preventDefault` on the wheel event.

#### Scenario: wheel scrolls the nearest scrollable ancestor

- WHEN the pointer is over content nested inside a scrollable container and a wheel-down event arrives
- THEN that container's `scrollTop` increases and the repaint reflects it, and containers further up do not scroll

#### Scenario: prevented wheel does not scroll

- WHEN a listener calls `preventDefault` on the wheel event
- THEN no scroll offset changes

### Requirement: Geometry is consistent under scroll

Hit testing, caret-from-point, and rect queries SHALL use viewport coordinates that account for applied scroll offsets, and SHALL NOT match content that is clipped out of view.

#### Scenario: click hits the scrolled content

- WHEN a container is scrolled by N rows and the user clicks a visible line
- THEN the caret lands in the line actually displayed at that position (the line N rows deeper in the content)

#### Scenario: clipped content is not hit

- WHEN content is scrolled out of a container's visible region
- THEN pointer queries over the container's bounds never resolve to the clipped-out content

### Requirement: Caret stays visible in scrollable editables

When caret movement or typing inside an editable region within a scrollable container places the caret outside the visible region, the container SHALL scroll the minimum amount to bring the caret into view.

#### Scenario: arrow past the fold

- WHEN the caret moves down past the last visible line of a scrollable editable
- THEN the container scrolls down so the caret's line is visible and the selection/highlight renders at the correct position
