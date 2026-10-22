# Design mode vs the options panel — the client-side facts (orchestrator, 2026-10-21)

Verified in the vendored libraries (read-only facts; cite them by file:line).

## A. Where the options panel sits
The addon's options panel is the AceGUI **"Frame" container**
(`Libs/AceGUI-3.0/widgets/AceGUIContainer-Frame.lua:182-196`):

```
frame:SetParent(UIParent)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:SetResizable(true)
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetFrameLevel(100)          -- "Lots of room to draw under it"
frame:SetToplevel(true)
```

The design mode's own frames sit BELOW it:
- the design layer + its dim veil: strata `BACKGROUND` (`designmode.lua:ensure_layer`),
- the snap guides frame: strata `DIALOG`, `EnableMouse(false)` (`ensure_guides`),
- every element overlay: a child of its target frame, so its strata is the TARGET's
  strata (`attach`, `designmode.lua:500`).

=> **Report #2 ("design starts behind it") is proven by the strata, not a guess.**
To render above the options panel the design visuals need strata
`FULLSCREEN_DIALOG` with a level > 100 (or `TOOLTIP`).
The AceConfigDialog validation popup is `TOOLTIP` / level 100
(`Libs/AceConfig-3.0/AceConfigDialog-3.0/AceConfigDialog-3.0.lua:554-555`).

## B. Why the options panel could feel stuck mid-drag
`AceGUIContainer-Frame.lua:40-43` and `:233-237`:

```lua
local function Title_OnMouseDown(frame)
    frame:GetParent():StartMoving()
    AceGUI:ClearFocus()
end
local function MoverSizer_OnMouseUp(mover)
    local frame = mover:GetParent()
    frame:StopMovingOrSizing()
    ...
```

The drag STARTS on the title's mouse-down and only ENDS in the **title's own**
mouse-up. Any mouse-enabled design frame that sits over the panel's title bar can
swallow that mouse-up, and the panel then stays in the moving state.
The design overlays are mouse-enabled Buttons parented to the element frames, so
their strata follows the element frame's strata: an element frame at or above
`FULLSCREEN_DIALOG` puts its overlay over the options panel.
=> **Report #1 ("i cant move the options frame") has a plausible mechanism here.**
The design mouse surface must never cover the options panel, and design mode must
never leave a frame in the moving state.

## C. Esc / UISpecialFrames — the mechanism behind report #3
- The AceGUI options panel is **not** registered in `UISpecialFrames`
  (`grep -rn UISpecialFrames Libs/AceGUI-3.0 Libs/AceConfig-3.0` -> no hits).
- The design layer **is**: `tinsert(UISpecialFrames, LAYER_NAME)` (`designmode.lua:254`).

So while the options panel is open, Esc hides the only special frame — the design
layer — whose `OnHide` calls `DM.stop(true)` (`designmode.lua:255-260`): design mode
ends and the options panel stays open.
=> **Report #3 ("can I close options and keep design mode") has a concrete cause.**
Required behaviour: Esc must not end design mode while an options dialog is open, and
closing the options panel must leave design mode active.
