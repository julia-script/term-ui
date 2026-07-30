## ADDED Requirements

### Requirement: Held keys repeat

A key held down SHALL keep acting for as long as the terminal reports repeats: repeat events SHALL insert text and drive editing defaults (deletion, caret movement) identically to the initial press. Key release SHALL never insert text.

#### Scenario: holding a character key types it repeatedly

- **WHEN** a terminal delivers a key press followed by repeat events for the same character while an editable region has a collapsed caret
- **THEN** one character is inserted per press and per repeat, and none on the release

#### Scenario: holding backspace keeps deleting

- **WHEN** a terminal delivers a backspace press followed by repeat events
- **THEN** one character is removed per press and per repeat

### Requirement: Modifier chords do not produce text

A key event carrying a non-shift modifier (Ctrl, Alt, Super, Hyper, Meta) SHALL NOT contribute text, whatever encoding the terminal used. Shift is exempt: it composes the character.

#### Scenario: control chord in an editable region

- **WHEN** a Ctrl-modified key arrives while an editable region has a collapsed caret, in either the legacy C0 encoding or the kitty encoding
- **THEN** no text is inserted and the document content is unchanged

### Requirement: Line-feed input means a line break

A bare line-feed byte SHALL be reported as Enter with the Shift modifier, not as a control chord, so that terminals whose newline keybind emits a raw line feed insert a line break rather than typing a character. Plain Enter (carriage return) SHALL remain unmodified.

#### Scenario: newline keybind in an editable region

- **WHEN** the terminal emits a bare line-feed byte while an editable region has a collapsed caret
- **THEN** a keydown for Enter with Shift is delivered and a line break is inserted at the caret

### Requirement: Empty lines are navigable

In text whose white-space handling preserves segment breaks, every break SHALL yield a line the caret can occupy — including a break at the very end of the text, and consecutive breaks that leave a line with no characters. Vertical caret movement SHALL traverse such lines rather than skipping or stalling on them.

#### Scenario: caret lands after a trailing line break

- **WHEN** a line break is inserted at the end of an editable region's text
- **THEN** the caret sits on a new, empty final line and typing there appends to that line

#### Scenario: arrows move through an empty line

- **WHEN** the caret moves down from a line above an empty line and then down again
- **THEN** it stops on the empty line first and reaches the following line on the second move, and moving up retraces the same path
