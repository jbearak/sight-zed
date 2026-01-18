# Requirements Document

## Introduction

This document specifies the requirements for achieving feature parity between the sight-zed extension (Zed editor) and the sight extension (VS Code) for auto-closing pairs functionality. Stata has unique quoting conventions including local macro syntax (`` `macro' ``), compound strings (`` `"string"' ``), and nested patterns that require special handling beyond standard bracket matching.

## Glossary

- **Auto_Closing_Pair**: A pair of characters where typing the opening character automatically inserts the closing character
- **Skip_Over**: Behavior where typing a closing character moves the cursor past an existing closing character instead of inserting a duplicate
- **Local_Macro_Syntax**: Stata's syntax for local macros using backtick and apostrophe (`` `name' ``)
- **Compound_String**: Stata's string syntax using backtick-quote pairs (`` `"string"' ``) that allows embedded quotes and macros
- **Deletion_Cleanup**: Behavior where deleting an opening character also removes its paired closing character
- **Zed_Extension**: The sight-zed extension for the Zed editor
- **VS_Code_Extension**: The sight extension for VS Code (reference implementation)

## Requirements

### Requirement 1: Basic Auto-Closing Pairs

**User Story:** As a Stata developer using Zed, I want standard brackets and quotes to auto-close, so that I can write code faster with balanced delimiters.

#### Acceptance Criteria

1. WHEN a user types `{` THEN the Zed_Extension SHALL insert `}` after the cursor
2. WHEN a user types `[` THEN the Zed_Extension SHALL insert `]` after the cursor
3. WHEN a user types `(` THEN the Zed_Extension SHALL insert `)` after the cursor
4. WHEN a user types `"` outside of a string THEN the Zed_Extension SHALL insert `"` after the cursor
5. WHEN a user types `` ` `` THEN the Zed_Extension SHALL insert `'` after the cursor (local macro syntax)

### Requirement 2: Skip-Over Behavior for Closing Characters

**User Story:** As a Stata developer, I want typing a closing character to skip over existing closing characters, so that I don't end up with duplicate delimiters.

#### Acceptance Criteria

1. WHEN a user types `'` and the cursor is immediately before an existing `'` THEN the Zed_Extension SHALL move the cursor past the existing `'` without inserting a new character
2. WHEN a user types `'` and the cursor is immediately before `"'` (compound string close) THEN the Zed_Extension SHALL move the cursor past both characters without inserting
3. WHEN a user types `"` and the cursor is immediately before an existing `"` THEN the Zed_Extension SHALL move the cursor past the existing `"` without inserting a new character

### Requirement 3: Nested Local Macro Support

**User Story:** As a Stata developer, I want to type nested local macros, so that I can use macros within macros correctly.

#### Acceptance Criteria

1. WHEN a user types a second `` ` `` immediately after an existing `` `' `` pattern THEN the Zed_Extension SHALL insert an additional `'` to create `` ``'' ``
2. WHEN a user types `` ` `` inside an existing local macro (after `` ` `` and before `'`) THEN the Zed_Extension SHALL insert `'` to maintain balanced delimiters

### Requirement 4: Compound String Support

**User Story:** As a Stata developer, I want compound strings to auto-close correctly, so that I can use Stata's `` `"..."' `` syntax efficiently.

#### Acceptance Criteria

1. WHEN a user types `"` immediately after `` ` `` (creating `` `" ``) THEN the Zed_Extension SHALL transform the closing to `"'` (compound string close)
2. WHEN a user types `` ` `` inside a compound string THEN the Zed_Extension SHALL insert `'` for the nested local macro
3. WHEN a user types `"` to start a nested compound string inside an existing compound string THEN the Zed_Extension SHALL insert appropriate closing characters to maintain balance

### Requirement 5: Deletion Cleanup

**User Story:** As a Stata developer, I want deleting an opening character to also remove its paired closing character, so that I don't have orphaned delimiters.

#### Acceptance Criteria

1. WHEN a user deletes `` ` `` and the character immediately to the right is `'` THEN the Zed_Extension SHALL also delete the `'`
2. WHEN a user deletes `"` and the character immediately to the right is `"` THEN the Zed_Extension SHALL also delete the second `"`
3. WHEN a user deletes `'` THEN the Zed_Extension SHALL NOT delete any additional characters (apostrophe is a closing character)

### Requirement 6: Context-Aware Behavior

**User Story:** As a Stata developer, I want auto-closing to work correctly in different contexts, so that the behavior is predictable and helpful.

#### Acceptance Criteria

1. WHEN a user types `` ` `` inside a double-quoted string THEN the Zed_Extension SHALL insert `'` for local macro expansion
2. WHEN a user types `` ` `` inside a compound string THEN the Zed_Extension SHALL insert `'` for local macro expansion
3. WHEN a user has multiple cursors THEN the Zed_Extension SHALL only apply auto-closing behavior for single cursor with empty selection
4. WHEN a user has text selected THEN the Zed_Extension SHALL NOT apply custom auto-closing behavior

### Requirement 7: Platform Compatibility

**User Story:** As a Stata developer, I want the auto-closing behavior to work within Zed's extension architecture, so that it integrates seamlessly with the editor.

#### Acceptance Criteria

1. THE Zed_Extension SHALL implement auto-closing behavior using Zed's extension API capabilities
2. IF Zed's extension API does not support custom keystroke handling THEN the Zed_Extension SHALL document the limitation and implement maximum possible functionality through available APIs
3. THE Zed_Extension SHALL NOT conflict with Zed's built-in auto-closing pair functionality
