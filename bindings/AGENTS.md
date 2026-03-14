# BINDINGS KNOWLEDGE BASE

## OVERVIEW
`bindings/` is the hotkey surface of the repo: each file owns one shortcut area and is lifecycle-managed through `bindings/init.lua`.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Enable or disable a binding set | `init.lua` | Edit `bindings.enabled` in root `init.lua` |
| Binding lifecycle contract | `bindings/init.lua` | Each enabled file is required, then `start()`/`stop()` is called |
| Modifier conventions | `bindings/init.lua` | Documents `ctrl+alt`, `ctrl+shift`, and hyper usage |
| Global launcher/app shortcuts | `bindings/global.lua` | Starts `chad`, `whisper`, app launchers, and utility toggles |
| Tiling or grid shortcuts | `bindings/hhtwm.lua` and `bindings/grid.lua` | Separate hhtwm and grid paths |

## CONVENTIONS
- Every binding file returns a module table with `start()` and `stop()`, even when `stop()` is empty.
- Keep bindings grouped by interaction area, not by single key.
- Use `hyper.multiBind(...)` for hyper-driven shortcuts; keep plain `hs.hotkey.bind(...)` for non-hyper cases.
- If a shortcut triggers substantial behavior, put the behavior in `mod/`, `chad/`, `whisper/`, or `ext/` and keep the binding file thin.
- When a binding needs to participate in startup/shutdown, add its filename to `bindings.enabled` in root `init.lua`.
- Tiling bindings are selected indirectly: root `init.lua` appends either `grid`, `autogrid`, or the configured tiling binding based on `config.wm.tilingMethod`.

## ANTI-PATTERNS
- Do not hide new behavior inside `bindings/global.lua` if it deserves its own binding area.
- Do not duplicate window-management logic in bindings; call into `mod.wm`, `hhtwm`, `hs.grid`, or `ext.window` instead.
- Do not assume raw modifier meanings; follow the documented remapping comment in `bindings/init.lua`.
- Do not add a managed binding file and forget to register it in root `init.lua`.
