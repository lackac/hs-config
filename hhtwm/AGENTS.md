# HHTWM KNOWLEDGE BASE

## OVERVIEW
`hhtwm/` is a custom tiling window manager. `hhtwm/init.lua` owns window and space state; `hhtwm/layouts.lua` defines frame calculators for named layouts.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Main tiling engine | `hhtwm/init.lua` | Cache management, tiling, floating, throws, layout persistence |
| Layout geometry | `hhtwm/layouts.lua` | Named layout functions return frames or `nil` |
| Repo-specific setup | `mod/wm.lua` | Configures filters, margins, resize step, display layouts |
| User-facing layout defaults | `config/wm.lua` | Declares display layouts and managed layouts |

## CONVENTIONS
- `cache` is the source of truth for tiled windows, floating windows, per-space layouts, and layout options.
- Most operations resolve a space first, then update cache, then call `module.tile()`.
- Layout functions receive `(window, windows, screen, index, layoutOptions)` and return either a frame table or `nil` to float the window.
- `layoutOptions.mainPaneRatio` is the primary tunable for split layouts; preserve that contract when adding layouts.
- Persistence uses `hs.settings` keys for options, tiling cache, and floating cache; keep new persisted state compatible with restart/reload.
- `mod/wm.lua` is the right place for repo-specific defaults such as filters, margins, and per-display layout choices.
- `config.wm.displayLayouts[...]` is ordered: `mod/wm.lua` uses the first entry as startup default and cycles through the full list later.
- Managed layouts are a higher-level feature wired from `bindings/hhtwm.lua` into `config.wm.managedLayouts`; applying one can add spaces and move windows across screens.

## ANTI-PATTERNS
- Do not edit layout math in `hhtwm/layouts.lua` when the real change belongs in `config/wm.lua` or `mod/wm.lua`.
- Do not update cache tables without understanding the corresponding cleanup path in `module.tile()`.
- Do not bypass floating/tiled helpers like `findTiledWindow`, `isTiled`, `isFloating`, and `ensureSpaceCache`.
- Do not introduce a new layout without handling the single-window case consistently.
