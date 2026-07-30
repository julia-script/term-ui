# Selection

## Purpose

Browser-consistent selection model over the DOM/layout two-tree architecture: boundary points, ranges, movement with alter (move/extend), direction, and granularity semantics matching `Selection.modify` in browsers.

## Requirements

### Requirement: Selection modify supports move and extend alterations

`Selection.modify` SHALL accept an alteration parameter distinguishing `move` (collapse then reposition the caret) from `extend` (move the focus, keeping the anchor), matching the browser `Selection.modify(alter, direction, granularity)` contract.

#### Scenario: move collapses a range

- WHEN a non-collapsed selection is modified with alter=move, direction=forward, granularity=character
- THEN the selection becomes collapsed at one position beyond the previous focus, and anchor equals focus

#### Scenario: extend preserves the anchor

- WHEN a collapsed selection at offset N is modified with alter=extend, direction=forward, granularity=character
- THEN the anchor remains at offset N and the focus moves to N+1

### Requirement: Word granularity

Selection movement SHALL support `word` granularity for both move and extend, using Unicode word-boundary rules consistent with the engine's existing word-break segmentation.

#### Scenario: extend forward by word

- WHEN the caret sits mid-word and the selection is extended forward by word
- THEN the focus moves to the end of the current word

#### Scenario: extend backward by word across whitespace

- WHEN the caret sits immediately after a word followed by spaces and the selection is extended backward by word from beyond the spaces
- THEN the focus moves to the start of the preceding word

### Requirement: Movement across wrapped lines and node boundaries

Character, word, and line movement SHALL cross soft-wrap line breaks and text-node/element boundaries without skipping or duplicating positions; line movement SHALL preserve the caret's horizontal position (ghost position) across consecutive line moves.

#### Scenario: line movement keeps horizontal position

- WHEN the caret is at column X of a wrapped line and the selection moves down one line and then down again
- THEN each move places the caret at the position closest to column X on the target line

#### Scenario: character movement crosses node boundaries

- WHEN the caret is at the end of one text node and moves forward by character into a following text node
- THEN the caret lands on the first position of the following node's rendered text with no position visited twice

### Requirement: Selection rendering across wrapped lines

A non-collapsed selection SHALL render as a highlight covering exactly the selected grapheme cells, including when the range spans multiple soft-wrapped lines or multiple nodes.

#### Scenario: highlight spans a wrap

- WHEN a selection covers text that soft-wraps across two lines
- THEN the painted output highlights the selected trailing cells of the first line and the selected leading cells of the second line, and no others
