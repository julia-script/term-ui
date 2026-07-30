# Caret Positioning

Mapping between screen coordinates and DOM positions (caret-from-point) with WebKit-style nearest-position fallback, and caret geometry queries for rendering.

## ADDED Requirements

### Requirement: Caret from point with nearest-position fallback

Given viewport coordinates, the engine SHALL return a boundary point (node + offset) for the caret. When the point does not hit text directly, it SHALL fall back to the most reasonable nearby caret position (nearest text position within the hit block) rather than returning nothing, consistent with WebKit's `caretPositionFromPoint` behavior.

#### Scenario: click on a grapheme

- WHEN the point is over the left half of a grapheme cell
- THEN the returned boundary point is before that grapheme; over the right half, after it

#### Scenario: click past the end of a line

- WHEN the point is to the right of the last grapheme of a wrapped line inside a text block
- THEN the returned boundary point is the end-of-line position of that visual line, not the start of the next

#### Scenario: click on empty space inside a text-bearing block

- WHEN the point is inside a block that contains text but not over any text fragment
- THEN a boundary point at the nearest text position is returned instead of null

### Requirement: Caret geometry query

For any boundary point in rendered content, the engine SHALL report the caret's visual position (cell coordinates) so a host can draw or place the terminal cursor; positions at a soft-wrap boundary SHALL resolve according to the selection's affinity (end of the earlier line for upstream, start of the later line for downstream).

#### Scenario: caret position round-trip

- WHEN a boundary point is obtained from a point query and its geometry is then queried
- THEN the reported caret cell is within the cell nearest the original point
