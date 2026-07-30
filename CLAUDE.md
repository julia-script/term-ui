# Claude Code Session Notes

## Project Structure
- This is a monorepo with multiple packages
- Zig code is in `packages/core/`
- Tests should be inline with code (Zig convention), not separate files
- Always reference new test files in `packages/core/src/wasm.zig` test block

## Zig-specific (packages/core only)
- Use `cd packages/core && zig build test` for testing (`-Dfilter=<substr>` to filter)
- Never run `zig test` directly - always use build script
- run `zig build test -Dupdate=true` to regenerate snapshots (file + inline)

## Coding Patterns
- Follow existing code conventions (check nearby files first)
- Use TodoWrite/TodoRead for complex multi-step tasks
- Write tests in the same file as the code being tested
- Always validate your todo list with the user before starting work
- Always do snapshot tests, and always use nodes as test inputs instead of hardcoded tokens