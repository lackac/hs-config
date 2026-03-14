# PROJECT KNOWLEDGE BASE

**Generated:** 2026-03-14-123920
**Commit:** 9b9dbf1
**Branch:** main

## OVERVIEW
Personal Hammerspoon configuration in Lua. `init.lua` boots bindings and long-lived modules; Nix provides the dev shell and formatting tools.

## STRUCTURE
```text
hs-config/
|- init.lua           # boot sequence; selects bindings and starts modules
|- overrides.lua      # global Hammerspoon overrides, grid behavior, IPC install
|- bindings/          # hotkey groups and modal entrypoints
|- chad/              # chooser-based Alfred replacement with plugin loading
|- hhtwm/             # custom tiling window manager and layouts
|- mod/               # background modules with start/stop lifecycle
|- ext/               # shared helpers and Hammerspoon wrappers
|- config/            # local configuration tables loaded via config/init.lua
|- urls/              # URL routing and decoder rules
|- whisper/           # voice recording + transcription flow
|- hs/                # custom hs.* extension code
|- scripts/           # standalone shell helpers
|- flake.nix          # dev shell dependencies
`- treefmt.nix        # nixfmt + stylua formatting
```

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Boot or shutdown flow | `init.lua` | Starts modules, enables bindings, chooses tiling mode |
| Global Hammerspoon behavior | `overrides.lua` | IPC install, grid overrides, animation policy |
| Add or wire a hotkey | `bindings/` | Register the file in `bindings.enabled` when it must be managed |
| Add chooser feature | `chad/` | Plugins are auto-loaded from files in that directory |
| Change tiling/window manager behavior | `hhtwm/` and `mod/wm.lua` | `mod/wm.lua` configures `hhtwm`; `hhtwm/` holds the engine |
| Update user config | `config/*.lua` | `config/init.lua` auto-requires every non-`init.lua` file |
| Change shared helpers | `ext/` | Prefer existing helpers before adding raw Hammerspoon calls |
| Change URL dispatch | `urls/init.lua` and `config/urls.lua` | Rules may be inline or loaded from files |
| Change voice transcription | `whisper/` | Recording and transcription are split into separate files |

## CONVENTIONS
- Modules that are started from `init.lua` expose `start()` and `stop()`.
- `bindings/init.lua` manages hotkey files as lifecycle modules; keep one file per binding area instead of growing `init.lua`.
- `config/init.lua` auto-loads `config/*.lua`; keep those files declarative and return plain tables.
- `overrides.lua` intentionally disables window animation globally with `hs.window.animationDuration = 0.0`.
- Prefer repo helpers such as `ext.utils.resolveExecutable`, `ext.screens`, `ext.window`, and `ext.drawing` before introducing new one-off wrappers.
- Formatting is repo-managed through treefmt: Stylua for Lua, nixfmt for Nix.

## ANTI-PATTERNS (THIS PROJECT)
- Do not hardcode a managed binding file without also wiring it through `bindings.enabled` if it needs `start()`/`stop()`.
- Do not re-enable global window animations unless the user explicitly wants that behavior changed.
- Do not bypass `config/` with ad hoc constants when the value is machine- or setup-specific.
- Do not duplicate helpers from `ext/` inside feature modules.
- Do not treat `chad/` or `hhtwm/` as generic folders; each has its own local contract documented in its child `AGENTS.md`.

## UNIQUE STYLES
- State-heavy subsystems keep mutable tables in a local `cache` and export a small module table.
- Hammerspoon callbacks and watchers are usually started in `start()` and cleaned up in `stop()`.
- The repo uses Lua diagnostics pragmas sparingly for Hammerspoon globals or duplicate field overrides.
- Comments are short and pragmatic; avoid adding narrative docs inline unless the behavior is genuinely non-obvious.

## COMMANDS
```bash
nix develop
nix fmt
treefmt
stylua .
luacheck .
```

## NOTES
- `flake.nix` installs `lua-language-server`, `stylua`, `luajit`, and `luacheck` in the dev shell.
- `hs.ipc.cliInstall()` runs from `overrides.lua`; command-line Hammerspoon access is expected to be available.
- The repo is shallow but has two dense hotspots: `chad/` and `hhtwm/`.
