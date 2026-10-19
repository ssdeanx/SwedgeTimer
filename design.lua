--=========================================================================================
-- Design: the WoW-free geometry + registry core behind design mode (designmode.lua).
--
-- Ported from the archived build's global edit mode (docs/swedge/SwedgeTimer_Forever/
-- editmode.lua; reference line numbers below are that file). Everything here is pure:
-- explicit numbers and plain tables, no frames, no WoW API - so tests/design_state.lua
-- can pin the maths offline. designmode.lua turns frames into these numbers and calls
-- back into the elements' own save/lock seams.
--
--   * round_half / grid_centre / round_grid      - the archive's drop quantisation
--     (editmode.lua 274-297: align wins outright, else the low edge lands on the grid,
--     else a half-pixel)
--   * target_for / nearest                       - the abutting-border rule and the
--     closest-line magnet (editmode.lua 224-248)
--   * align                                      - per-axis alignment: the screen centre
--     attracts the element's centre only, every other element attracts its edges and
--     centre too (editmode.lua 253-267)
--   * box_lines / offer_lines / interval_gap     - the box's own left/right/centre and
--     bottom/top/centre lines, and the candidate lines another element offers within
--     the reach rule (editmode.lua 192-218)
--   * snap / centre_force / centred              - the dropped position, the held-
--     modifier exact-centre override, and the screen-centre test (editmode.lua 274-306)
--   * normalise_descriptor / new_registry        - the element descriptor contract
--     (editmode.lua 25-47 header, 311-539 registry)
--   * row_boxes / normalise_template             - stacked-layout cells (row/column
--     geometry shared by widgets and the C6 snap-to-row templates) and the template
--     descriptor contract
--
-- Domain: every x/y here is an offset from UIParent's centre in UIParent units
-- (designmode.lua's centre_offsets - the domain the elements' own db keys already use).
-- Line lists are dense arrays of { v, kind, border } where kind is "lo" (left/bottom
-- edge), "hi" (right/top edge) or "mid" (the centre). Designmode's drag tick reuses the
-- list slots across frames via the explicit counts (nx/ny): offer_lines fills slot
-- tables in place, creating one only the first time it is needed.
--=========================================================================================
local _, st = ...

st.design = st.design or {}
local D = st.design

local floor, abs, min, max = math.floor, math.abs, math.min, math.max

D.DEFAULT_MAGNET = 8    -- archive CENTER_MAGNET (editmode.lua:65)
D.DEFAULT_REACH = 120   -- archive ALIGN_REACH (editmode.lua:66)
D.MIN_GRID = 8          -- archive EM.grid_step(): steps below 8 are treated as off

--=========================================================================================
-- Numbers
--=========================================================================================
function D.is_number(v)
    return type(v) == "number"
end

-- The half-pixel the archive drops elements at when no grid (or no snap) is wanted
-- (editmode.lua:276). nil for a non-number.
function D.round_half(v)
    if not D.is_number(v) then return nil end
    return floor(v * 2 + 0.5) / 2
end

-- Quantise a centre so one of its edges lands on the grid (archive EM.snap 287 / 294):
-- the edge is moved to the nearest grid line and the centre follows by the same delta,
-- then the result is half-rounded. `step` nil / < MIN_GRID = no grid.
function D.grid_centre(centre, edge, step)
    if not (D.is_number(centre) and D.is_number(edge)) then return nil end
    if not D.is_number(step) or step < D.MIN_GRID then
        return D.round_half(centre)
    end
    return D.round_half(centre + (floor(edge / step + 0.5) * step - edge))
end

-- Nearest grid multiple to a value when there is no edge to hang the quantisation on
-- (a degenerate box); falls back to half-pixel rounding without a grid.
function D.round_grid(v, step)
    if not D.is_number(v) then return nil end
    if not D.is_number(step) or step < D.MIN_GRID then
        return D.round_half(v)
    end
    return floor(v / step + 0.5) * step
end

-- The gap between two intervals, zero when they overlap (archive alignment_lines 202-203:
-- `max(0, l - mr, ml - r)`). nil when any input is missing.
function D.interval_gap(a1, a2, b1, b2)
    if not (D.is_number(a1) and D.is_number(a2) and D.is_number(b1) and D.is_number(b2)) then
        return nil
    end
    return max(0, b1 - a2, a1 - b2)
end

--=========================================================================================
-- Lines and magnets
--=========================================================================================
-- Keep (or create) the slot `i` of a line list. The table is reused across calls, so a
-- hot caller never allocates once its slots exist.
local function put(list, i, v, kind, border)
    local ln = list[i]
    if ln then
        ln.v, ln.kind, ln.border = v, kind, border
    else
        list[i] = { v = v, kind = kind, border = border }
    end
    return i
end

-- The archive's abutting-border rule (editmode.lua:224-231): when my low edge meets
-- their high edge (or the reverse) the two drawn borders overlap by the thinner one, so
-- 2 px + 2 px reads as one 2 px line instead of a 4 px band. Same-kind lines and centres
-- meet exactly.
function D.target_for(mine, cand)
    local overlap = min(mine.border or 0, cand.border or 0)
    if overlap > 0 then
        if mine.kind == "lo" and cand.kind == "hi" then return cand.v - overlap end
        if mine.kind == "hi" and cand.kind == "lo" then return cand.v + overlap end
    end
    return cand.v
end

-- The closest alignment within the magnet for one axis (archive nearest 236-248): over
-- `n_mine` entries of `mine` and `n_lines` entries of `lines`. Returns the delta to apply
-- and the line value hit (nil, nil when nothing is close enough). Ties keep the first hit
-- (the archive's strict less-than), and the magnet is inclusive.
function D.nearest(mine, n_mine, lines, n_lines, magnet)
    magnet = magnet or D.DEFAULT_MAGNET
    n_mine = n_mine or #mine
    n_lines = n_lines or #lines
    local best_d, best_line
    for i = 1, n_mine do
        local m = mine[i]
        for j = 1, n_lines do
            local target = D.target_for(m, lines[j])
            local d = target - m.v
            if abs(d) <= magnet and (not best_d or abs(d) < abs(best_d)) then
                best_d, best_line = d, target
            end
        end
    end
    return best_d, best_line
end

-- The screen centre (offset 0) attracts the box's centre line only (archive EM.align
-- 260-263 calls nearest({mx[3]}, {xs[1]}) - the centre, never an edge).
function D.centre_magnet(mine, n_mine, magnet)
    magnet = magnet or D.DEFAULT_MAGNET
    n_mine = n_mine or #mine
    local best_d
    for i = 1, n_mine do
        local m = mine[i]
        if m.kind == "mid" then
            local d = -m.v
            if abs(d) <= magnet and (not best_d or abs(d) < abs(best_d)) then
                best_d = d
            end
        end
    end
    return best_d, best_d and 0 or nil
end

-- Fill (or create) the box's own line list: left/bottom low edges, right/top high edges
-- and the centre (archive EM.align 257-258). `mine_x`/`mine_y` are reusable scratch
-- tables for hot callers; both are returned, or nil when the box is not fully known.
function D.box_lines(l, r, t, b, border, mine_x, mine_y)
    if not (D.is_number(l) and D.is_number(r) and D.is_number(t) and D.is_number(b)) then
        return nil
    end
    border = border or 0
    mine_x = mine_x or {}
    mine_y = mine_y or {}
    put(mine_x, 1, l, "lo", border)
    put(mine_x, 2, r, "hi", border)
    put(mine_x, 3, (l + r) / 2, "mid", 0)
    put(mine_y, 1, b, "lo", border)
    put(mine_y, 2, t, "hi", border)
    put(mine_y, 3, (t + b) / 2, "mid", 0)
    return mine_x, mine_y
end

-- Offer another element's lines to the dragged box (archive alignment_lines 192-218):
-- its vertical lines are offered only when the boxes are within `reach` vertically
-- (ygap), its horizontal lines when within reach horizontally (xgap). Appends to
-- lines_x/lines_y starting after the `nx`/`ny` already there, in the archive's order
-- (lo, hi, mid), and returns the new counts. Slots are reused; a slot table is created
-- only the first time.
function D.offer_lines(lines_x, nx, lines_y, ny, l, r, t, b, border, mine_l, mine_r, mine_t, mine_b, reach)
    nx = nx or 0
    ny = ny or 0
    if not (D.is_number(l) and D.is_number(r) and D.is_number(t) and D.is_number(b)) then
        return nx, ny
    end
    reach = reach or D.DEFAULT_REACH
    border = border or 0
    local ygap = D.interval_gap(b, t, mine_b, mine_t)
    local xgap = D.interval_gap(l, r, mine_l, mine_r)
    if ygap and ygap <= reach then
        nx = put(lines_x, nx + 1, l, "lo", border)
        nx = put(lines_x, nx + 1, r, "hi", border)
        nx = put(lines_x, nx + 1, (l + r) / 2, "mid", 0)
    end
    if xgap and xgap <= reach then
        ny = put(lines_y, ny + 1, b, "lo", border)
        ny = put(lines_y, ny + 1, t, "hi", border)
        ny = put(lines_y, ny + 1, (t + b) / 2, "mid", 0)
    end
    return nx, ny
end

-- Per-axis alignment (archive EM.align 253-267): for each axis the screen centre is
-- checked against the box's centre line, then every element line against every box
-- line; the smaller absolute delta wins, with the centre winning ties. Returns dx, dy
-- (nil = free on that axis) and the guide lines that are active, gx, gy (the line value
-- hit, in the same offsets-from-centre domain).
function D.align(mine_x, mine_y, lines_x, nx, lines_y, ny, magnet)
    magnet = magnet or D.DEFAULT_MAGNET
    local dx, gx = D.centre_magnet(mine_x, #mine_x, magnet)
    local dx2, gx2 = D.nearest(mine_x, #mine_x, lines_x, nx, magnet)
    if dx2 and (not dx or abs(dx2) < abs(dx)) then dx, gx = dx2, gx2 end
    local dy, gy = D.centre_magnet(mine_y, #mine_y, magnet)
    local dy2, gy2 = D.nearest(mine_y, #mine_y, lines_y, ny, magnet)
    if dy2 and (not dy or abs(dy2) < abs(dy)) then dy, gy = dy2, gy2 end
    return dx, dy, gx, gy
end

-- Snap a dropped element (archive EM.snap 274-297). Priority per axis: an alignment
-- within the magnet wins outright; otherwise the box's low edge lands on the grid;
-- otherwise a half-pixel. A box with missing edges (a degenerate element) still
-- quantises its centre. `x`/`y` are the desired centre offsets; `l`/`r`/`t`/`b` the
-- box's edges at that centre. Returns sx, sy and the guide lines active at the snap
-- (gx/gy, nil when free on that axis - the grid and half-pixel cases report nothing).
function D.snap(x, y, l, r, t, b, lines_x, nx, lines_y, ny, magnet, grid, border, mine_x, mine_y)
    if not (D.is_number(x) and D.is_number(y)) then return nil end
    magnet = magnet or D.DEFAULT_MAGNET
    local dx, dy, gx, gy
    local box_ok = D.is_number(l) and D.is_number(r) and D.is_number(t) and D.is_number(b)
    if box_ok then
        mine_x, mine_y = D.box_lines(l, r, t, b, border, mine_x, mine_y)
        dx, dy, gx, gy = D.align(mine_x, mine_y, lines_x, nx, lines_y, ny, magnet)
    end
    local sx, sy
    if dx then
        sx = x + dx
    elseif box_ok then
        sx = D.grid_centre(x, l, grid)
    else
        sx = D.round_grid(x, grid)
    end
    if dy then
        sy = y + dy
    elseif box_ok then
        sy = D.grid_centre(y, t, grid)
    else
        sy = D.round_grid(y, grid)
    end
    return sx, sy, gx, gy
end

-- Centre-force: while the modifier is held the element lands exactly on the screen
-- centre on both axes (the archive's centre-magnet taken to its exact conclusion).
function D.centre_force(x, y, active)
    if not active then return x, y end
    return 0, 0
end

-- Whether the offsets count as centred on the screen within the magnet (archive
-- EM.centred 300-302); false for a non-number input.
function D.centred(x, y, magnet)
    if not (D.is_number(x) and D.is_number(y)) then return false, false end
    magnet = magnet or D.DEFAULT_MAGNET
    return abs(x) <= magnet, abs(y) <= magnet
end

--=========================================================================================
-- Stacked-layout cells (C6 snap-to-row templates)
--=========================================================================================
-- The rects of a row/column of cells (editmode.lua's element groups, reduced to the
-- geometry): cell i is centred on the first cell's centre, advanced by (size + gap)
-- along `axis` - "x" rightwards (the default), "y" downwards - in the same
-- offsets-from-centre domain as every other helper here. Each cell is { l, r, t, b }.
-- nil for degenerate input (non-number size/origin, count below 1, non-number gap).
-- Used both for widget geometry (the pips row) and for design-mode templates.
function D.row_boxes(count, size, gap, x, y, axis)
    if not (D.is_number(count) and D.is_number(size) and D.is_number(x) and D.is_number(y)) then
        return nil
    end
    count = floor(count)
    if count < 1 or size <= 0 then
        return nil
    end
    gap = gap or 0
    if not D.is_number(gap) then
        return nil
    end
    local step = size + gap
    local half = size / 2
    local cells = {}
    for i = 1, count do
        local d = (i - 1) * step
        if axis == "y" then
            cells[i] = { l = x - half, r = x + half, t = y - d + half, b = y - d - half }
        else
            cells[i] = { l = x + d - half, r = x + d + half, t = y + half, b = y - half }
        end
    end
    return cells
end

--=========================================================================================
-- Element descriptors
--=========================================================================================
-- The registry is fed by other modules at file load - before their frames exist - so a
-- descriptor's callbacks are only type-checked here, never called. A descriptor is:
--   key        non-empty string, unique in the registry
--   title      non-empty string (the overlay label)
--   get_frame  function() -> the live frame or nil while the module has not built it
--   save       optional function(x, y): store the desired centre offsets and re-apply
--              through the element's own positioning path
--   reset      optional function(): restore the element's default position
--   box        optional function() -> the frame whose rect the overlay hugs when it
--              differs from the dragged frame (default: the dragged frame)
--   available  optional function() -> false hides the element from design mode
--   border     optional number / function() -> the element's drawn edge thickness,
--              used for the abutting-border stack
--   lock       optional { get = function() -> locked?, set = function(locked) } - the
--              module's own lock seam, temporarily overridden while design mode runs
-- Extra fields are kept by the shallow copy. `normalise_descriptor` returns a copy (the
-- input is never mutated) or nil plus a clear error message.
function D.normalise_descriptor(desc)
    if type(desc) ~= "table" then
        return nil, "descriptor must be a table"
    end
    if type(desc.key) ~= "string" or desc.key == "" then
        return nil, "descriptor.key must be a non-empty string"
    end
    if type(desc.title) ~= "string" or desc.title == "" then
        return nil, "descriptor.title must be a non-empty string"
    end
    if type(desc.get_frame) ~= "function" then
        return nil, "descriptor.get_frame must be a function returning the element frame"
    end
    if desc.save ~= nil and type(desc.save) ~= "function" then
        return nil, "descriptor.save must be a function(x, y) or nil"
    end
    if desc.reset ~= nil and type(desc.reset) ~= "function" then
        return nil, "descriptor.reset must be a function() or nil"
    end
    if desc.box ~= nil and type(desc.box) ~= "function" and type(desc.box) ~= "table" then
        return nil, "descriptor.box must be a function returning the box frame or nil"
    end
    if desc.available ~= nil and type(desc.available) ~= "function" then
        return nil, "descriptor.available must be a function() or nil"
    end
    if desc.border ~= nil and type(desc.border) ~= "number" and type(desc.border) ~= "function" then
        return nil, "descriptor.border must be a number, a function() or nil"
    end
    if desc.lock ~= nil then
        if type(desc.lock) ~= "table" then
            return nil, "descriptor.lock must be a table { get = ..., set = ... } or nil"
        end
        if type(desc.lock.get) ~= "function" then
            return nil, "descriptor.lock.get must be a function returning locked?"
        end
        if type(desc.lock.set) ~= "function" then
            return nil, "descriptor.lock.set must be a function(locked)"
        end
    end
    local norm = {}
    for k, v in pairs(desc) do
        norm[k] = v
    end
    norm.key = desc.key
    norm.title = desc.title
    return norm
end

-- An ordered, validated registry. register() returns the normalised descriptor or
-- nil, error; keys must be unique. list/count are the ordered storage; each() walks it.
function D.new_registry()
    local reg = { list = {}, by_key = {}, count = 0 }
    function reg:register(desc)
        local norm, err = D.normalise_descriptor(desc)
        if not norm then
            return nil, err
        end
        if self.by_key[norm.key] then
            return nil, "duplicate element key '" .. norm.key .. "'"
        end
        self.count = self.count + 1
        self.list[self.count] = norm
        self.by_key[norm.key] = norm
        return norm
    end
    function reg:each()
        local i = 0
        local list = self.list
        local n = self.count
        return function()
            i = i + 1
            if i <= n then
                return list[i]
            end
        end
    end
    return reg
end

--=========================================================================================
-- Snap-template descriptors (C6)
--=========================================================================================
-- A template describes a stacked layout the drag magnets can offer: designmode.lua
-- registers these, validates them here, and reads the cells while a drag is active.
--   id         non-empty string, unique among registered templates
--   get_cells  function() -> array of { l, r, t, b } cell rects in the offsets-from-centre
--              domain, or nil while the layout is not readable (hidden frame)
--   border     optional number / function() -> the cells' drawn edge thickness (the
--              abutting-border rule)
-- Extra fields are kept by the shallow copy; the callbacks are never called here.
function D.normalise_template(t)
    if type(t) ~= "table" then
        return nil, "template must be a table"
    end
    if type(t.id) ~= "string" or t.id == "" then
        return nil, "template.id must be a non-empty string"
    end
    if type(t.get_cells) ~= "function" then
        return nil, "template.get_cells must be a function returning cell rects"
    end
    if t.border ~= nil and type(t.border) ~= "number" and type(t.border) ~= "function" then
        return nil, "template.border must be a number, a function() or nil"
    end
    local norm = {}
    for k, v in pairs(t) do
        norm[k] = v
    end
    return norm
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then st.utils.print_msg('-- Parsed design.lua module correctly') end
