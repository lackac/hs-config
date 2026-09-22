# hs.windowborder

Native active-window border support for this Hammerspoon configuration.

The implementation is intentionally gated. Build and run the standalone
private-API probe before loading any native code into Hammerspoon:

```sh
make -C hs/windowborder doctor
make -C hs/windowborder test
make -C hs/windowborder run-probe
```

Without arguments, the probe resolves the required SkyLight symbols only. To
exercise one complete private-overlay lifecycle in the standalone process,
pass a target window ID and owner PID:

```sh
make -C hs/windowborder run-probe ARGS="<window-id> <owner-pid>"
```

The lifecycle probe creates a separate-connection overlay, renders it, checks
its Space membership, orders it below the target, hides it, and destroys it.
It never modifies the target window.

At runtime, list built-in charts with `require("hs.windowborder").patterns()`.
For a live change without reloading Hammerspoon, use
`require("mod.autoborder").setPattern("picnic")` or
`require("mod.autoborder").setColor("#4A6B52")`.

## Per-application styles

Press Hyper+B while an eligible application window is focused to preview a
style for that application. The modal binds:

```text
Left/Right  pattern
Up/Down     hue
[/]         saturation
{/}         brightness
Enter       save for this application
Escape      discard the preview
Backspace   remove this application's saved style
Delete      remove this application's saved style
```

Saved pattern and color choices are stored by application bundle ID in
`hs.settings` under `windowborder.styles`. All applications without a saved
choice continue using `config/window.lua` defaults.
