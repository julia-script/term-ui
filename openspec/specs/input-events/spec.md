# Input Events

## Purpose

Terminal input parsed and delivered as DOM-style events through the JS layer, driving caret and selection end to end. First-release mouse scope: click-to-place-caret and drag-to-select (wheel/hover deferred).

## Requirements

### Requirement: Keyboard-driven caret and selection

Arrow keys SHALL move the caret by character (left/right) and by line (up/down); with Shift held they SHALL extend the selection instead; with the word modifier (Alt/Option on macOS conventions, Ctrl elsewhere) they SHALL move or extend by word. These SHALL work end to end from raw terminal bytes through the DOM event layer in an editable region.

#### Scenario: shift+arrow extends

- WHEN a terminal delivers a Shift+Right key sequence while an editable region is focused with a collapsed caret
- THEN the selection extends forward by one character and the repaint shows the highlight

#### Scenario: word-modifier arrow moves by word

- WHEN a terminal delivers a word-modifier+Right sequence with a collapsed caret mid-word
- THEN the caret moves to the end of the current word

### Requirement: Mouse click places the caret

A mouse press event with coordinates over rendered content SHALL collapse the selection to the caret-from-point boundary at those coordinates.

#### Scenario: click in text

- WHEN a mouse press arrives at a cell inside rendered text
- THEN the selection collapses to the corresponding boundary point and the caret is at that cell

### Requirement: Mouse drag extends a selection

While the primary button is held, mouse movement SHALL extend the selection from the press-point anchor to the boundary under the current pointer position, including across wrapped lines.

#### Scenario: drag across a wrap

- WHEN the user presses at one text position and drags to a position on a later visual line before releasing
- THEN the selection anchor is the press position, the focus follows the pointer, and the highlight spans the wrapped lines between them

### Requirement: Event delivery through the DOM layer

Parsed input SHALL surface as DOM-style events (`keydown`, mouse press/move/release) on the document/element layer so applications can subscribe with `addEventListener`; selection-changing defaults SHALL be applied by the engine without requiring application code.

#### Scenario: application observes keydown

- WHEN a key sequence is parsed from the terminal stream
- THEN listeners registered for `keydown` on the document receive an event carrying the key, modifiers, and action before default caret behavior is applied
