# Implementation Plan: Auto-Closing Pairs Parity

## Overview

This implementation fixes the auto-closing pairs behavior in sight-zed to achieve feature parity with the VS Code extension. The primary fix is updating the `autoclose_before` setting to include `'` and `"`, which enables compound string and nested macro typing sequences.

## Tasks

- [x] 1. Update bracket configuration in config.toml
  - [x] 1.1 Add apostrophe and double quote to `autoclose_before` setting
    - Change `autoclose_before = ";:.,=}])>\` \n\t"` to `autoclose_before = ";:.,=}])>'\"\` \n\t"`
    - This enables auto-closing when cursor is before `'` or `"`
    - _Requirements: 4.1, 4.2, 3.1, 3.2_
  
  - [x] 1.2 Add `not_in` scope to double quote bracket definition
    - Change `{ start = "\"", end = "\"", close = true, newline = false }` to include `not_in = ["string"]`
    - This prevents double quote auto-closing inside existing strings
    - _Requirements: 1.4_

- [x] 2. Create overrides.scm for syntax scopes
  - [x] 2.1 Create `sight-zed/languages/stata/overrides.scm` file
    - Define `@string` scope for string literals
    - Define `@comment` scope for comments
    - This enables the `not_in = ["string"]` configuration to work
    - _Requirements: 1.4, 6.1, 6.2_

- [x] 3. Checkpoint - Verify configuration syntax
  - Ensure all TOML and Tree-sitter query syntax is valid
  - Ask the user if questions arise

- [x] 4. Manual verification testing
  - [x] 4.1 Test basic bracket auto-closing
    - Verify `{`, `[`, `(`, `` ` ``, `"` all auto-close correctly
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_
  
  - [x] 4.2 Test compound string typing sequence
    - Type `` ` `` then `"` and verify result is `` `"|"' ``
    - **Property 4: Compound String Typing Sequence**
    - **Validates: Requirements 4.1, 4.2**
  
  - [x] 4.3 Test nested backtick typing
    - Type `` ` `` inside existing `` `' `` and verify nested result
    - **Property 5: Nested Backtick Typing Sequence**
    - **Validates: Requirements 3.1, 3.2**
  
  - [x] 4.4 Test context-aware double quote behavior
    - Verify `"` does not auto-close inside existing strings
    - **Property 2: Context-Aware Double Quote Behavior**
    - **Validates: Requirements 1.4**

- [x] 5. Final checkpoint - All manual tests pass
  - Ensure all test cases pass in Zed editor
  - Ask the user if questions arise

## Notes

- This implementation uses only static configuration changes (no Rust code changes needed)
- The `lib.rs` file remains unchanged as Zed's extension API doesn't support custom keystroke handling
- Skip-over behavior and deletion cleanup cannot be implemented due to API limitations
- All changes are in the `sight-zed/languages/stata/` directory
