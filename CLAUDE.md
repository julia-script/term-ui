# Claude Code Session Notes

## Project Structure
- This is a monorepo with multiple packages
- Zig code is in `packages/core/`
- Tests should be inline with code (Zig convention), not separate files
- Always reference new test files in `packages/core/src/wasm.zig` test block

## Zig-specific (packages/core only)
- Use `cd packages/core && zig build debugbuild -Dtest-filter=<dir> && ./zig-out/bin/test` for testing
- Never run `zig test` directly - always use build script
- run UPDATE_SNAPSHOTS=true zig build test to update the snapshots

## Coding Patterns
- Follow existing code conventions (check nearby files first)
- Use TodoWrite/TodoRead for complex multi-step tasks
- Write tests in the same file as the code being tested
- Always validate your todo list with the user before starting work
- Always do snapshot tests, and always use nodes as test inputs instead of hardcoded tokens