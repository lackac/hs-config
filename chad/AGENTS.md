# CHAD KNOWLEDGE BASE

## OVERVIEW
`chad/` is a chooser-based Alfred replacement. `chad/init.lua` owns the UI, plugin loading, query history, keyword activation, preview rendering, and reload flow.

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|
| Core chooser behavior | `chad/init.lua` | Plugin loading, query handling, preview, history, modal bindings |
| Plugin skeleton | `chad/_template.lua` | Canonical shape for new chooser plugins |
| Keyword or auto-activation patterns | existing plugin files | See `calculator.lua`, `emojis.lua`, `define.lua`, `deepl.lua` |
| Persistent plugin state | individual plugins | Usually stored via `hs.settings` under `module.requireName` |

## CONVENTIONS
- Plugin files are auto-discovered from `chad/`; files starting with `_` are skipped.
- A plugin usually exports `compileChoices(query)`, `complete(choice)`, `start(main, pluginName)`, and `stop()`.
- Plugin metadata is declarative: `keyword`, `autoActivate`, `placeholder`, `tip`, `useFzf`, and optional `fzfOpts`.
- `start(main, pluginName)` receives the parent module; use `module.main` rather than recreating chooser state locally.
- Choice tables should be shaped for chooser display and may include `id`, `text`, `subText`, `fullText`, `source`, or `fzfInput`.
- Choices that expect plugin callbacks should consistently set `source = module.requireName`; completion dispatch routes through that field.
- Persist plugin-specific state under namespaced `hs.settings` keys, typically based on `module.requireName`.

## ANTI-PATTERNS
- Do not manually register plugins in `chad/init.lua`; file discovery is the registration mechanism.
- Do not mutate chooser internals from a plugin except through the parent module API already exposed in `main`.
- Do not assume a plugin runs alone; `chad/init.lua` merges outputs from multiple active plugins and may route through fzf.
- Do not reuse an existing `keyword` or `autoActivate` token casually; duplicate keywords only log a warning and the first loaded plugin keeps the slot.
- Do not use `_template.lua` conventions selectively; new plugins should match that contract unless there is a clear reason not to.
