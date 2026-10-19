-- tests/design_state.lua: offline tests for the design-mode core (design.lua).
--
-- design.lua is pure (no WoW API), so it is loaded directly and exercised as plain Lua.
-- This suite pins:
--   * the archive's drop quantisation: half-pixel rounding, grid quantisation of the
--     box's low edge, and the degenerate no-edge fallbacks,
--   * the alignment maths ported from the archived editmode.lua: the abutting-border
--     rule, the closest-line magnet and its boundaries, the screen-centre magnet (the
--     centre alone, never the edges), axis independence and guide-line reporting,
--   * the line lists: box_lines edges/centres, the reach-filtered candidate builder and
--     its slot reuse (no steady-state allocation),
--   * snap priority (alignment > grid > half-pixel), centre-force, centred(),
--   * descriptor validation/normalisation and the registry contract,
--   * degenerate inputs: nil boxes, zero-size boxes, nil numbers,
--   * static wiring: TOCs, config defaults, the options section and main.lua's arg.
-- Run from the repo root: lua5.1 tests/design_state.lua  (any cwd works).

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("FAIL  " .. label)
    end
end
local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

--=========================================================================================
-- Load design.lua (pure module: no sandbox beyond the chunk arguments)
--=========================================================================================
local st = { debug = false }
local chunk = assert(loadfile(ROOT .. "design.lua"))
local ok, err = pcall(chunk, "SwedgeTimer", st)
if not ok then
    print("FAIL  design.lua does not load: " .. tostring(err))
    os.exit(1)
end
local D = st.design
check(type(D) == "table", "design.lua defines st.design")

local entry_points = {
    "round_half", "grid_centre", "round_grid", "interval_gap", "target_for", "nearest",
    "centre_magnet", "box_lines", "offer_lines", "align", "snap", "centre_force",
    "centred", "normalise_descriptor", "new_registry", "row_boxes", "normalise_template",
}
for i = 1, #entry_points do
    check(type(D[entry_points[i]]) == "function", "design.lua exposes " .. entry_points[i])
end
eq(D.DEFAULT_MAGNET, 8, "DEFAULT_MAGNET is the archive's 8 px")
eq(D.DEFAULT_REACH, 120, "DEFAULT_REACH is the archive's 120 px")
eq(D.MIN_GRID, 8, "MIN_GRID is the archive's 8 px floor")

--=========================================================================================
-- 1) Half-pixel rounding (archive editmode.lua:276)
--=========================================================================================
eq(D.round_half(10), 10, "round_half: integer unchanged")
eq(D.round_half(10.26), 10.5, "round_half: rounds up to the half")
eq(D.round_half(10.24), 10, "round_half: rounds down to the integer")
eq(D.round_half(-10.26), -10.5, "round_half: negative rounds away correctly")
eq(D.round_half(0.25), 0.5, "round_half: the .25 boundary goes up")
eq(D.round_half(nil), nil, "round_half: nil input -> nil")

--=========================================================================================
-- 2) Grid quantisation (archive EM.snap 287/294, EM.grid_step 135-138)
--=========================================================================================
eq(D.grid_centre(100, 80, 24), 92, "grid: edge 80 quantises to 72, centre follows (-8)")
eq(D.grid_centre(101, 81, 24), 92, "grid: the low edge, not the centre, decides the line")
eq(D.grid_centre(0, 12, 24), 12, "grid: edge exactly between lines takes the upper one")
eq(D.grid_centre(100, 80, 8), 100, "grid: edge already on a line -> centre unchanged")
eq(D.grid_centre(100, 80, 0), 100, "grid: step 0 = no grid -> half-pixel path")
eq(D.grid_centre(100, 80, 7), 100, "grid: step below MIN_GRID treated as off")
eq(D.grid_centre(100, 80, nil), 100, "grid: nil step treated as off")
eq(D.grid_centre(100.2, 80, 0), 100, "grid: off still half-rounds the centre")
eq(D.round_grid(100, 24), 96, "round_grid: nearest 24 px multiple (96)")
eq(D.round_grid(112, 24), 120, "round_grid: 112 is nearer 120 than 96")
eq(D.round_grid(100, 0), 100, "round_grid: step 0 = half-pixel only")
eq(D.round_grid(100.3, nil), 100.5, "round_grid: nil step half-rounds")
eq(D.round_grid(nil, 24), nil, "round_grid: nil value -> nil")

--=========================================================================================
-- 3) Interval gaps (archive alignment_lines 202-203)
--=========================================================================================
eq(D.interval_gap(0, 10, -5, 5), 0, "gap: overlapping intervals -> 0")
eq(D.interval_gap(0, 10, 10, 20), 0, "gap: touching intervals -> 0")
eq(D.interval_gap(0, 10, 30, 40), 20, "gap: separated intervals -> the gap")
eq(D.interval_gap(30, 40, 0, 10), 20, "gap: order independent")
eq(D.interval_gap(0, 10, nil, 40), nil, "gap: nil input -> nil")

--=========================================================================================
-- 4) The abutting-border rule and the closest-line magnet (archive 224-248)
--=========================================================================================
eq(D.target_for({ v = 100, kind = "lo", border = 2 }, { v = 98, kind = "hi", border = 2 }), 96,
    "target_for: my low edge against their high edge overlaps by the thinner border")
eq(D.target_for({ v = 100, kind = "hi", border = 2 }, { v = 98, kind = "lo", border = 2 }), 100,
    "target_for: my high edge against their low edge is the reverse case")
eq(D.target_for({ v = 100, kind = "lo", border = 4 }, { v = 98, kind = "lo", border = 4 }), 98,
    "target_for: same-kind edges meet exactly")
eq(D.target_for({ v = 100, kind = "lo" }, { v = 98, kind = "hi" }), 98,
    "target_for: no borders -> the candidate line itself")
eq(D.target_for({ v = 100, kind = "lo", border = 1 }, { v = 98, kind = "hi", border = 3 }), 97,
    "target_for: overlap is the thinner of the two borders")

local nearest_mine = { { v = 100, kind = "lo", border = 0 } }
local d1, l1 = D.nearest(nearest_mine, 1, { { v = 104, kind = "mid", border = 0 } }, 1, 8)
eq(d1, 4, "nearest: delta to the candidate line")
eq(l1, 104, "nearest: reports the line value hit")
local d2 = D.nearest(nearest_mine, 1, { { v = 108, kind = "mid", border = 0 } }, 1, 8)
eq(d2, 8, "nearest: the magnet is inclusive at exactly the threshold")
eq(D.nearest(nearest_mine, 1, { { v = 108.5, kind = "mid", border = 0 } }, 1, 8), nil,
    "nearest: just outside the magnet -> no hit")
local d3, l3 = D.nearest(nearest_mine, 1, { { v = 110, kind = "mid" }, { v = 103, kind = "mid" } }, 2, 8)
eq(d3, 3, "nearest: the closest candidate wins")
eq(l3, 103, "nearest: ...and reports that line")
local d4, l4 = D.nearest(nearest_mine, 1, { { v = 96, kind = "mid" }, { v = 104, kind = "mid" } }, 2, 8)
eq(d4, -4, "nearest: equal distances keep the first hit")
eq(l4, 96, "nearest: ...the first line")
local d5, l5 = D.nearest({ { v = 100, kind = "lo", border = 2 } }, 1,
    { { v = 98, kind = "hi", border = 2 } }, 1, 8)
eq(d5, -4, "nearest: the abutting-border overlap shifts the target")
eq(l5, 96, "nearest: ...and the reported line is the shifted target")
local counted_mine = { { v = 100, kind = "lo", border = 0 }, { v = 50, kind = "mid", border = 0 } }
eq(D.nearest(counted_mine, 1, { { v = 55, kind = "mid" } }, 1, 8), nil,
    "nearest: n_mine restricts the scanned prefix")
eq(D.nearest(counted_mine, 2, { { v = 55, kind = "mid" } }, 1, 8), 5,
    "nearest: the second entry is scanned when counted")

--=========================================================================================
-- 5) The screen-centre magnet and align (archive EM.align 253-267)
--=========================================================================================
local cd, cg = D.centre_magnet({ { v = 4, kind = "mid", border = 0 } }, 1, 8)
eq(cd, -4, "centre magnet: delta back to 0")
eq(cg, 0, "centre magnet: reports the screen-centre line (0)")
eq(D.centre_magnet({ { v = 8, kind = "mid" } }, 1, 8), -8, "centre magnet: inclusive at the threshold")
eq(D.centre_magnet({ { v = -8.5, kind = "mid" } }, 1, 8), nil, "centre magnet: outside -> no hit")
eq(D.centre_magnet({ { v = 5, kind = "lo" }, { v = 15, kind = "hi" }, { v = 10, kind = "mid" } }, 3, 8), nil,
    "centre magnet: edges never attract the screen centre, only the centre line")

local mx, my = D.box_lines(-15, 25, -10, 30, 0)     -- centre (5, 10)
local adx, ady, agx, agy = D.align(mx, my, {}, 0, {}, 0, 8)
eq(adx, -5, "align: the box centre snaps to the screen centre")
eq(agx, 0, "align: the active guide is the centre line")
eq(ady, nil, "align: the other axis reports free (10 > magnet)")
eq(agy, nil, "align: ...with no guide")

local mx2 = D.box_lines(-14, 26, -10, 30, 0)        -- centre (6, 10)
local bdx, bdy, bgx, bgy = D.align(mx2, my, { { v = 5, kind = "mid" } }, 1, {}, 0, 8)
eq(bdx, -1, "align: an element centre closer than the screen centre wins")
eq(bgx, 5, "align: ...with its line as the guide")
eq(bdy, nil, "align: the untouched axis stays free (1)")
eq(bgy, nil, "align: the untouched axis reports no guide (1)")

local mx3 = D.box_lines(-16, 24, -10, 30, 0)        -- centre (4, 10)
local cdx, cdy, cgx, cgy = D.align(mx3, my, { { v = 8, kind = "mid" } }, 1, {}, 0, 8)
eq(cdx, -4, "align: a tie between centre and element keeps the screen centre")
eq(cgx, 0, "align: ...reporting the centre line")
eq(cdy, nil, "align: the untouched axis stays free (2)")
eq(cgy, nil, "align: the untouched axis reports no guide (2)")

local mx4 = D.box_lines(10, 50, -10, 30, 0)         -- centre (30, 10)
local ddx, ddy, dgx, dgy = D.align(mx4, my, { { v = 12, kind = "lo" } }, 1, {}, 0, 8)
eq(ddx, 2, "align: the box's low edge aligns to the element's low edge")
eq(dgx, 12, "align: ...reporting that edge")
eq(ddy, nil, "align: the untouched axis stays free (3)")
eq(dgy, nil, "align: the untouched axis reports no guide (3)")

local mx5 = D.box_lines(100, 140, -10, 30, 2)
local edx, edy, egx, egy = D.align(mx5, my, { { v = 98, kind = "hi", border = 2 } }, 1, {}, 0, 8)
eq(edx, -4, "align: abutting borders overlap by the thinner one")
eq(egx, 96, "align: ...the guide sits on the overlapped target")
eq(edy, nil, "align: the untouched axis stays free (4)")
eq(egy, nil, "align: the untouched axis reports no guide (4)")

local boxx_x = D.box_lines(-100, -40, -10, 30, 0)           -- centre (-70, 10)
local _, boxy_y = D.box_lines(-15, 25, -60, 0, 0)           -- centre (5, -30)
local f1dx, f1dy, f1gx, f1gy = D.align(boxx_x, boxy_y, { { v = -98, kind = "lo" } }, 1, {}, 0, 8)
eq(f1dx, 2, "align: a vertical candidate moves x only")
eq(f1gx, -98, "align: ...with the vertical guide")
eq(f1dy, nil, "align: ...and leaves y free")
eq(f1gy, nil, "align: ...without a y guide")
local f2dx, f2dy, f2gx, f2gy = D.align(boxx_x, boxy_y, {}, 0, { { v = -58, kind = "lo" } }, 1, 8)
eq(f2dy, 2, "align: a horizontal candidate moves y only")
eq(f2gy, -58, "align: ...with the horizontal guide")
eq(f2dx, nil, "align: ...and leaves x free")
eq(f2gx, nil, "align: ...without an x guide")
local f3dx, f3dy, f3gx, f3gy = D.align(boxx_x, boxy_y, { { v = -98, kind = "lo" } }, 1, { { v = -58, kind = "lo" } }, 1, 8)
eq(f3dx, 2, "align: with candidates on both axes x aligns")
eq(f3gx, -98, "align: ...to its own guide")
eq(f3dy, 2, "align: ...and y aligns independently")
eq(f3gy, -58, "align: ...to its own guide")

--=========================================================================================
-- 6) box_lines (archive EM.align 257-258)
--=========================================================================================
local blx, bly = D.box_lines(-50, 50, 20, -20, 3)
eq(blx[1].v, -50, "box_lines: left edge value")
eq(blx[1].kind, "lo", "box_lines: left edge kind")
eq(blx[1].border, 3, "box_lines: the border is carried on the edges")
eq(blx[2].v, 50, "box_lines: right edge value")
eq(blx[2].kind, "hi", "box_lines: right edge kind")
eq(blx[3].v, 0, "box_lines: centre value")
eq(blx[3].kind, "mid", "box_lines: centre kind")
eq(blx[3].border, 0, "box_lines: the centre carries no border")
eq(bly[1].v, -20, "box_lines: bottom edge value")
eq(bly[1].kind, "lo", "box_lines: bottom edge kind")
eq(bly[2].v, 20, "box_lines: top edge value")
eq(bly[2].kind, "hi", "box_lines: top edge kind")
eq(bly[3].v, 0, "box_lines: vertical centre")

local scratch_x, scratch_y = {}, {}
local got_x, got_y = D.box_lines(1, 5, 9, 3, nil, scratch_x, scratch_y)
check(got_x == scratch_x and got_y == scratch_y, "box_lines: reuses the caller's scratch tables")
eq(scratch_x[1].border, 0, "box_lines: nil border reads as 0")

local zsx = D.box_lines(10, 10, 20, 20, 0)
eq(zsx[1].v, 10, "box_lines: a zero-size box keeps valid edge values")
eq(zsx[3].v, 10, "box_lines: a zero-size box has centre == edge")
eq(D.box_lines(nil, 5, 5, 5, 0), nil, "box_lines: a nil edge -> nil (degenerate input)")

--=========================================================================================
-- 7) offer_lines: reach rule and slot reuse (archive alignment_lines 192-218)
--=========================================================================================
local ox, oy = {}, {}
local nx, ny = D.offer_lines(ox, 0, oy, 0, -50, 50, 60, 40, 0, -50, 50, 20, -20, 120)
eq(nx, 3, "offer_lines: overlapping box above -> 3 vertical lines")
eq(ny, 3, "offer_lines: ...and 3 horizontal lines")
eq(ox[1].v, -50, "offer_lines: first vertical line is the other's left edge")
eq(ox[1].kind, "lo", "offer_lines: left edge kind")
eq(ox[2].v, 50, "offer_lines: second is the right edge")
eq(ox[2].kind, "hi", "offer_lines: right edge kind")
eq(ox[3].v, 0, "offer_lines: third is the centre")
eq(ox[3].kind, "mid", "offer_lines: centre kind")
eq(oy[1].v, 40, "offer_lines: first horizontal line is the other's bottom edge")
eq(oy[2].v, 60, "offer_lines: second is the top edge")
eq(oy[3].v, 50, "offer_lines: third is the horizontal centre")

local nx1, ny1 = D.offer_lines({}, 0, {}, 0, 500, 600, 60, 40, 0, -50, 50, 20, -20, 120)
eq(nx1, 3, "offer_lines: a horizontally-far box still offers vertical lines when vertically close")
eq(ny1, 0, "offer_lines: ...but never horizontal ones")
local nx2, ny2 = D.offer_lines({}, 0, {}, 0, 40, 60, -400, -500, 0, -50, 50, 20, -20, 120)
eq(nx2, 0, "offer_lines: a vertically-far box offers no vertical lines")
eq(ny2, 3, "offer_lines: ...but offers horizontal ones when horizontally close")
local nx3, ny3 = D.offer_lines({}, 0, {}, 0, 500, 600, -400, -500, 0, -50, 50, 20, -20, 120)
eq(nx3, 0, "offer_lines: a far box offers nothing vertically")
eq(ny3, 0, "offer_lines: ...nor horizontally")
local nx4 = D.offer_lines({}, 0, {}, 0, -50, 50, 160, 140, 0, -50, 50, 20, -20, 120)
eq(nx4, 3, "offer_lines: exactly at the reach boundary the lines are offered")
local nx5 = D.offer_lines({}, 0, {}, 0, -50, 50, 161, 141, 0, -50, 50, 20, -20, 120)
eq(nx5, 0, "offer_lines: one pixel past the boundary -> no lines")

local reuse_x, reuse_y = {}, {}
local rn1 = D.offer_lines(reuse_x, 0, reuse_y, 0, -50, 50, 60, 40, 0, -50, 50, 20, -20, 120)
local slot1 = reuse_x[1]
local rn2 = D.offer_lines(reuse_x, 0, reuse_y, 0, -50, 50, 62, 42, 2, -50, 50, 20, -20, 120)
check(reuse_x[1] == slot1, "offer_lines: the slot table is reused on the next tick (no allocation)")
eq(rn2, rn1, "offer_lines: the counts are stable across ticks")
eq(slot1.v, -50, "offer_lines: the reused slot holds the new value")
eq(slot1.border, 2, "offer_lines: the reused slot holds the new border")
local bn_x, bn_y = {}, {}
D.offer_lines(bn_x, 0, bn_y, 0, -50, 50, 60, 40, 2, -50, 50, 20, -20, 120)
eq(bn_x[2].border, 2, "offer_lines: the border is carried on every edge line")
eq(bn_x[3].border, 0, "offer_lines: centre lines carry no border")
eq(bn_y[1].border, 2, "offer_lines: ...on the horizontal edges too")
local enx, eny = D.offer_lines({}, 0, {}, 0, nil, 5, 5, 5, 0, -50, 50, 20, -20, 120)
eq(enx, 0, "offer_lines: a degenerate box adds nothing")
eq(eny, 0, "offer_lines: ...on either axis")

--=========================================================================================
-- 8) snap: alignment > grid > half-pixel (archive EM.snap 274-297)
--=========================================================================================
-- box centred (100, 100): 40x60 -> l=80 r=120 t=130 b=70
local sx1, sy1, sgx1, sgy1 = D.snap(100, 100, 80, 120, 130, 70, { { v = 82, kind = "lo" } }, 1, {}, 0, 8, 24, 0)
eq(sx1, 102, "snap: a line hit wins over the grid")
eq(sgx1, 82, "snap: ...reporting the guide")
eq(sy1, 90, "snap: the other axis falls to the grid (edge 130 -> 120, centre 100 -> 90)")
eq(sgy1, nil, "snap: ...with no guide")

local sx2, sy2, sgx2, sgy2 = D.snap(100, 45, 80, 120, 65, 25, {}, 0, {}, 0, 8, 24, 0)
eq(sx2, 92, "snap: no lines -> the low edge lands on the grid (80 -> 72)")
eq(sy2, 52, "snap: ...using the top edge for y (65 -> 72)")
eq(sgx2, nil, "snap: grid placement reports no x guide")
eq(sgy2, nil, "snap: grid placement reports no y guide")

local sx3, sy3 = D.snap(100.3, 45.7, 80, 120, 65, 25, {}, 0, {}, 0, 8, 0, 0)
eq(sx3, 100.5, "snap: grid off -> half-pixel, not grid")
eq(sy3, 45.5, "snap: ...on both axes")

local sx4, sy4, sgx4, sgy4 = D.snap(5, 0, -15, 25, 30, -30, {}, 0, {}, 0, 8, 24, 0)
eq(sx4, 0, "snap: the screen centre wins within the magnet")
eq(sgx4, 0, "snap: ...reporting the centre guide")
eq(sy4, 0, "snap: a centre exactly on 0 snaps to itself")
eq(sgy4, 0, "snap: ...with the centre guide active")

local sx5, sy5, sgx5, sgy5 = D.snap(100, -30, 80, 120, 0, -60, {}, 0, { { v = -58, kind = "lo" } }, 1, 8, 24, 0)
eq(sx5, 92, "snap: an axis with no candidates still grids")
eq(sgx5, nil, "snap: ...without a guide")
eq(sy5, -28, "snap: the y axis uses its candidate line")
eq(sgy5, -58, "snap: ...and reports it")

local dx1, dy1, dgx1, dgy1 = D.snap(100, 200, nil, nil, nil, nil, {}, 0, {}, 0, 8, 24, 0)
eq(dx1, 96, "snap: a degenerate box quantises its centre (x)")
eq(dy1, 192, "snap: a degenerate box quantises its centre (y)")
eq(dgx1, nil, "snap: a degenerate box reports no guide (x)")
eq(dgy1, nil, "snap: a degenerate box reports no guide (y)")
local dx2 = D.snap(100, 200, nil, nil, nil, nil, { { v = 100, kind = "mid" } }, 1, {}, 0, 8, 24, 0)
eq(dx2, 96, "snap: candidates are ignored without a box")

local zx, zy = D.snap(100, 200, 100, 100, 200, 200, {}, 0, {}, 0, 8, 24, 0)
eq(zx, 96, "snap: a zero-size box still snaps (x)")
eq(zy, 192, "snap: a zero-size box still snaps (y)")
eq(D.snap(nil, 10, 0, 1, 1, 0), nil, "snap: nil x -> nil (degenerate)")
eq(D.snap(10, nil, 0, 1, 1, 0), nil, "snap: nil y -> nil (degenerate)")

--=========================================================================================
-- 9) centre_force and centred (archive EM.centred 300-302)
--=========================================================================================
local fx, fy = D.centre_force(123.5, -45, true)
eq(fx, 0, "centre_force: held modifier -> exact centre (x)")
eq(fy, 0, "centre_force: held modifier -> exact centre (y)")
local px, py = D.centre_force(123.5, -45, false)
eq(px, 123.5, "centre_force: released -> passthrough (x)")
eq(py, -45, "centre_force: released -> passthrough (y)")
local qx = D.centre_force(10, 20, nil)
eq(qx, 10, "centre_force: nil modifier -> passthrough")

local hx1, hy1 = D.centred(0, 0, 8)
eq(hx1, true, "centred: 0,0 is centred (x)")
eq(hy1, true, "centred: 0,0 is centred (y)")
local hx2, hy2 = D.centred(8, -8, 8)
eq(hx2, true, "centred: the boundary is inclusive (x)")
eq(hy2, true, "centred: the boundary is inclusive (y)")
eq(select(1, D.centred(8.5, 0, 8)), false, "centred: just outside -> not centred (x)")
eq(select(2, D.centred(0, 8.5, 8)), false, "centred: just outside -> not centred (y)")
local hx3, hy3 = D.centred(nil, 0)
eq(hx3, false, "centred: nil input -> false (x)")
eq(hy3, false, "centred: nil input -> false (y)")

--=========================================================================================
-- 10) Descriptor validation / normalisation
--=========================================================================================
local base_desc = { key = "k", title = "T", get_frame = function() return nil end }
local norm = D.normalise_descriptor(base_desc)
check(norm ~= nil, "normalise: a minimal descriptor is valid")
eq(norm.key, "k", "normalise: key carried")
eq(norm.title, "T", "normalise: title carried")
check(norm.get_frame == base_desc.get_frame, "normalise: get_frame carried")
check(norm ~= base_desc, "normalise: returns a copy, not the input table")

local called = false
local fn_desc = { key = "k", title = "T", get_frame = function() called = true; error("not during load") end }
local ok_fn, fn_norm = pcall(D.normalise_descriptor, fn_desc)
check(ok_fn and fn_norm ~= nil, "normalise: does not call get_frame (registry is fed before frames exist)")
eq(called, false, "normalise: ...verified by the counter")

local extra_desc = { key = "k", title = "T", get_frame = function() end, custom = 5 }
eq(D.normalise_descriptor(extra_desc).custom, 5, "normalise: extra fields survive the copy")

local bad, msg = D.normalise_descriptor(nil)
eq(bad, nil, "normalise: nil -> invalid")
check(type(msg) == "string" and msg:find("table") ~= nil, "normalise: nil error names the type")
eq(D.normalise_descriptor(5), nil, "normalise: a number -> invalid")
local _, key_err = D.normalise_descriptor({ title = "T", get_frame = function() end })
check(key_err and key_err:find("key") ~= nil, "normalise: missing key error names the field")
local _, key_err2 = D.normalise_descriptor({ key = "", title = "T", get_frame = function() end })
check(key_err2 and key_err2:find("key") ~= nil, "normalise: empty key is rejected")
local _, key_err3 = D.normalise_descriptor({ key = 5, title = "T", get_frame = function() end })
check(key_err3 and key_err3:find("key") ~= nil, "normalise: non-string key is rejected")
local _, title_err = D.normalise_descriptor({ key = "k", get_frame = function() end })
check(title_err and title_err:find("title") ~= nil, "normalise: missing title error names the field")
local _, gf_err = D.normalise_descriptor({ key = "k", title = "T" })
check(gf_err and gf_err:find("get_frame") ~= nil, "normalise: missing get_frame error names the field")
local _, gf_err2 = D.normalise_descriptor({ key = "k", title = "T", get_frame = "frame" })
check(gf_err2 and gf_err2:find("get_frame") ~= nil, "normalise: non-function get_frame is rejected")
local _, save_err = D.normalise_descriptor({ key = "k", title = "T", get_frame = function() end, save = 5 })
check(save_err and save_err:find("save") ~= nil, "normalise: non-function save is rejected")
local _, reset_err = D.normalise_descriptor({ key = "k", title = "T", get_frame = function() end, reset = "x" })
check(reset_err and reset_err:find("reset") ~= nil, "normalise: non-function reset is rejected")
local _, box_err = D.normalise_descriptor({ key = "k", title = "T", get_frame = function() end, box = 5 })
check(box_err and box_err:find("box") ~= nil, "normalise: non-callable box is rejected")
local _, avail_err = D.normalise_descriptor({ key = "k", title = "T", get_frame = function() end, available = 5 })
check(avail_err and avail_err:find("available") ~= nil, "normalise: non-function available is rejected")
local _, border_err = D.normalise_descriptor({ key = "k", title = "T", get_frame = function() end, border = "3" })
check(border_err and border_err:find("border") ~= nil, "normalise: a string border is rejected")

local lock_fn = function() end
check(D.normalise_descriptor({ key = "k", title = "T", get_frame = lock_fn,
    lock = { get = lock_fn, set = lock_fn } }) ~= nil, "normalise: a valid lock table passes")
local _, lock_err = D.normalise_descriptor({ key = "k", title = "T", get_frame = lock_fn, lock = 5 })
check(lock_err and lock_err:find("lock") ~= nil, "normalise: a non-table lock is rejected")
local _, lock_err2 = D.normalise_descriptor({ key = "k", title = "T", get_frame = lock_fn, lock = { set = lock_fn } })
check(lock_err2 and lock_err2:find("lock.get") ~= nil, "normalise: a lock without get is rejected")
local _, lock_err3 = D.normalise_descriptor({ key = "k", title = "T", get_frame = lock_fn, lock = { get = lock_fn } })
check(lock_err3 and lock_err3:find("lock.set") ~= nil, "normalise: a lock without set is rejected")

--=========================================================================================
-- 11) Registry
--=========================================================================================
local reg = D.new_registry()
local r1 = reg:register(base_desc)
check(r1 ~= nil, "registry: a valid descriptor registers")
eq(reg.count, 1, "registry: count tracks registrations")
check(reg.list[1] == r1, "registry: the normalised descriptor is stored in order")
local r1dup, dup_err = reg:register({ key = "k", title = "Other", get_frame = lock_fn })
eq(r1dup, nil, "registry: duplicate keys are rejected")
check(dup_err and dup_err:find("duplicate") ~= nil, "registry: ...with a duplicate-key error")
eq(reg.count, 1, "registry: a rejected duplicate does not change the count")
local r2 = reg:register({ key = "second", title = "Second", get_frame = lock_fn })
check(r2 ~= nil and reg.count == 2, "registry: a second key registers")
check(reg.list[2] == r2, "registry: order is registration order")
check(reg.by_key["second"] == r2, "registry: by_key lookup")
local invalid, invalid_err = reg:register({ key = "x" })
eq(invalid, nil, "registry: an invalid descriptor is rejected")
check(invalid_err and invalid_err:find("title") ~= nil, "registry: ...with the normaliser's error")
eq(reg.count, 2, "registry: a rejected invalid descriptor does not change the count")
local walked, n = {}, 0
for desc in reg:each() do
    n = n + 1
    walked[n] = desc.key
end
eq(n, 2, "registry: each() walks every entry")
eq(walked[1], "k", "registry: each() is in order (1)")
eq(walked[2], "second", "registry: each() is in order (2)")

--=========================================================================================
-- 12) Stacked-layout cells and snap templates (C6)
--=========================================================================================
do
local rb = D.row_boxes(3, 10, 2, 100, 50, "x")
check(type(rb) == "table" and #rb == 3, "row_boxes: three cells")
eq(rb[1].l, 95, "row_boxes: first cell left")
eq(rb[1].r, 105, "row_boxes: first cell right")
eq(rb[1].t, 55, "row_boxes: first cell top")
eq(rb[1].b, 45, "row_boxes: first cell bottom")
eq(rb[2].l, 107, "row_boxes: the step is size + gap (second cell left)")
eq(rb[3].r, 129, "row_boxes: third cell right")
eq(rb[3].t, 55, "row_boxes: cells share the cross-axis band")
eq(D.row_boxes(1, 10, 2, 0, 0)[1].l, -5, "row_boxes: a single cell is centred on the origin")
eq(D.row_boxes(2, 10, 0, 0, 0)[2].l, 5, "row_boxes: gap 0 steps by size")
local rb_y = D.row_boxes(2, 10, 4, 0, 100, "y")
eq(rb_y[1].t, 105, "row_boxes (y): first cell top")
eq(rb_y[2].b, 81, "row_boxes (y): the column steps downwards")
eq(rb_y[2].l, -5, "row_boxes (y): the cross axis stays centred on x")
eq(D.row_boxes(2, 10, 2, 0, 0, "z")[2].l, 7, "row_boxes: an unknown axis reads as horizontal")
eq(#D.row_boxes(2.7, 10, 2, 0, 0), 2, "row_boxes: a fractional count floors")
eq(D.row_boxes(0, 10, 2, 0, 0), nil, "row_boxes: count 0 -> nil")
eq(D.row_boxes(2, 0, 2, 0, 0), nil, "row_boxes: size 0 -> nil")
eq(D.row_boxes(2, -5, 2, 0, 0), nil, "row_boxes: a negative size -> nil")
eq(D.row_boxes(2, 10, "x", 0, 0), nil, "row_boxes: a non-number gap -> nil")
eq(D.row_boxes(2, 10, 2, nil, 0), nil, "row_boxes: a nil origin -> nil")
eq(D.row_boxes(nil, 10, 2, 0, 0), nil, "row_boxes: a nil count -> nil")
local rb_c = D.row_boxes(1, 10, 0, 3, 4)
rb_c[1].l = -999
eq(D.row_boxes(1, 10, 0, 3, 4)[1].l, -2, "row_boxes: returns fresh tables (no shared state)")

local base_tpl = { id = "t", get_cells = function() return nil end }
local tnorm = D.normalise_template(base_tpl)
check(tnorm ~= nil, "normalise_template: a minimal template is valid")
eq(tnorm.id, "t", "normalise_template: id carried")
check(tnorm.get_cells == base_tpl.get_cells, "normalise_template: get_cells carried")
check(tnorm ~= base_tpl, "normalise_template: returns a copy, not the input table")
local tpl_called = false
local tpl_fn = { id = "t", get_cells = function() tpl_called = true end }
local ok_tpl, tpl_norm = pcall(D.normalise_template, tpl_fn)
check(ok_tpl and tpl_norm ~= nil, "normalise_template: does not call get_cells (fed before frames exist)")
eq(tpl_called, false, "normalise_template: ...verified by the counter")
eq(D.normalise_template({ id = "t", get_cells = function() end, custom = 5 }).custom, 5,
    "normalise_template: extra fields survive the copy")
local tbad, tmsg = D.normalise_template(nil)
eq(tbad, nil, "normalise_template: nil -> invalid")
check(type(tmsg) == "string" and tmsg:find("table") ~= nil,
    "normalise_template: nil error names the type")
local _, tid_err = D.normalise_template({ get_cells = function() end })
check(tid_err and tid_err:find("id") ~= nil, "normalise_template: missing id error names the field")
local _, tid_err2 = D.normalise_template({ id = "", get_cells = function() end })
check(tid_err2 and tid_err2:find("id") ~= nil, "normalise_template: empty id is rejected")
local _, tcell_err = D.normalise_template({ id = "t" })
check(tcell_err and tcell_err:find("get_cells") ~= nil,
    "normalise_template: missing get_cells error names the field")
local _, tborder_err = D.normalise_template({ id = "t", get_cells = function() end, border = "3" })
check(tborder_err and tborder_err:find("border") ~= nil,
    "normalise_template: a string border is rejected")
check(D.normalise_template({ id = "t", get_cells = function() end,
    border = function() return 2 end }) ~= nil, "normalise_template: a function border passes")
end

--=========================================================================================
-- 13) Static wiring: TOCs, defaults, options, main.lua
--=========================================================================================
local function read(path)
    local f = assert(io.open(ROOT .. path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

do
    local tocs = { "SwedgeTimer.toc", "SwedgeTimer_Vanilla.toc", "SwedgeTimer_TBC.toc",
        "SwedgeTimer_Wrath.toc", "SwedgeTimer_Cata.toc", "SwedgeTimer_Mists.toc",
        "SwedgeTimer_Mainline.toc" }
    for i = 1, #tocs do
        local text = read(tocs[i])
        local design = text:find("\ndesign.lua", 1, true)
        local mode = text:find("\ndesignmode.lua", 1, true)
        local hud = text:find("\nhud.lua", 1, true)
        local rotation = text:find("\nrotationtext.lua", 1, true)
        local presets = text:find("\nconfig_presets.lua", 1, true)
        check(design and mode, tocs[i] .. ": lists design.lua and designmode.lua")
        check(design and mode and design < mode, tocs[i] .. ": design.lua loads before designmode.lua")
        check(hud and rotation and mode and presets and hud < mode and rotation < mode and mode < presets,
            tocs[i] .. ": designmode.lua loads after hud.lua/rotationtext.lua and before config_presets.lua")
    end
end

do
    local presets = read("config_presets.lua")
    local shared = presets:match("ST%.class_defaults%s*=%s*{(.-)\n}") or ""
    check(shared ~= "", "the class_defaults block is found in config_presets.lua")
    check(shared:find("%f[%a_]design_grid_enabled%s*=%s*true") ~= nil,
        "design_grid_enabled ships in the shared class defaults")
    check(shared:find("%f[%a_]design_grid%s*=%s*24") ~= nil,
        "design_grid ships as the archive's 24 px step")
    check(shared:find("%f[%a_]design_snap%s*=%s*true") ~= nil,
        "design_snap ships in the shared class defaults")
    check(shared:find("%f[%a_]design_snap_threshold%s*=%s*8") ~= nil,
        "design_snap_threshold ships as the archive's 8 px magnet")
    check(shared:find("%f[%a_]design_enabled%f[%A]") == nil,
        "design mode's enabled state is not persisted (no design_enabled key)")

    local options = read("option_tables.lua")
    check(options:find("Design Mode", 1, true) ~= nil, "option_tables.lua has a Design Mode section")
    local widget_types = {
        design_toggle = "execute",
        design_grid_enabled = "toggle",
        design_grid = "range",
        design_snap = "toggle",
        design_snap_threshold = "range",
    }
    for widget_key, widget_type in pairs(widget_types) do
        local widget = options:match("%f[%a_]" .. widget_key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"" .. widget_type .. "\"") ~= nil,
            widget_key .. " has a " .. widget_type .. " widget in the options")
    end
    check(options:find("st%.designmode%.toggle") ~= nil,
        "the Design Mode button routes through st.designmode.toggle")

    local main = read("main.lua")
    check(main:find('arg == "design"', 1, true) ~= nil, "main.lua handles the design argument")
    check(main:find("st%.designmode%.toggle") ~= nil, "main.lua routes /st design through st.designmode")
    check(main:find("st%.designmode%.on_combat_start") ~= nil,
        "main.lua closes design mode on combat start")

    local design_src = read("design.lua")
    local mode_src = read("designmode.lua")
    check(design_src:find("CreateFrame") == nil, "design.lua is WoW-free (no CreateFrame)")
    check(design_src:find("GetTime") == nil, "design.lua uses no clock")
    check(mode_src:find("GetTime") == nil, "designmode.lua uses no clock (cursor-driven drag)")
    check(mode_src:find("%f[%a_]is_mainline%f[%A]") == nil, "designmode.lua never gates on the client family")
    for _, needle in ipairs({ "bar_", "st.hud", "st.rotation_text", "st.nextaction_ui", "st.practice_ui",
        "practice_rotation", "practice_timeline" }) do
        check(mode_src:find(needle, 1, true) ~= nil, "designmode.lua registers the " .. needle .. " element")
    end

    -- C3 / C6 / D3 build-out wiring (this round): the zone service, the snap-template
    -- registry and the frozen pips contract must exist where the report says they do.
    local bars_src = read("bars.lua")
    check(bars_src:find("function ST:register_zone") ~= nil,
        "bars.lua exposes the C3 zone registration")
    check(bars_src:find("function ST:update_zones") ~= nil,
        "bars.lua exposes the C3 zone dispatch")
    check(bars_src:find("self:update_zones(hand)", 1, true) ~= nil,
        "bars.lua dispatches registered zones from onupdate_common")
    check(bars_src:find("function ST:new_pips") ~= nil,
        "bars.lua exposes the D3 pips factory")
    check(bars_src:find("frame.set = function", 1, true) ~= nil,
        "the pips frame exposes the frozen set contract")
    check(bars_src:find("frame.glow_full = function", 1, true) ~= nil,
        "the pips frame exposes the frozen glow_full contract")
    check(mode_src:find("function DM.register_template") ~= nil,
        "designmode.lua exposes the snap-template registration")
    check(mode_src:find("function DM.unregister_template") ~= nil,
        "designmode.lua exposes template removal")
    check(mode_src:find("design_mouse_anchor", 1, true) ~= nil,
        "designmode.lua reads the mouse-anchoring toggle")
end

if failures == 0 then
    print("PASS  design_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  design_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end
