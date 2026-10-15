-- hud.lua =============================================================================
-- Cooldown HUD: a row of ability icons under the bar, ported from the "[Retr] Spells"
-- group of Nullgodx's Paladin WeakAura (wago.io/CI7I0QRGO). Each icon shows the
-- ability's cooldown swipe and remaining time, desaturates while on cooldown, tints
-- blue without mana and red when the target is out of range, and glows when the
-- ability is the right call (only Exorcism and Avenging Wrath glow):
--   Crusader Strike   cooldown (the GCD shows as a swipe without text)
--   Judgement         cooldown; grey without a seal
--   Consecration      cooldown (GCD swipe)
--   Exorcism          cooldown; grey unless the target is Undead or Demon, glows then
--   Avenging Wrath    cooldown; glows in combat once it is ready
--   Trinket 1 / 2     the equipped trinket: on-use cooldown, else proc buff (swipe) and
--                     the internal cooldown after it (reversed swipe); hidden when empty
-- Every icon can be switched off, the row is sized, spaced and styled from the
-- settings, and design mode positions it. Ability cooldowns come from the same
-- practice-aware readers the Next Action Guide uses, so the HUD works in Practice Mode.
-- The WeakAura's "not in melee / not attacking" text is deliberately not ported.
--=======================================================================================
local addon_name, st = ...
local print = st.utils.print_msg
local ST = LibStub("AceAddon-3.0"):GetAddon("SwedgeTimer")
local SML = LibStub("LibSharedMedia-3.0")
local LCG = LibStub("LibCustomGlow-1.0")

st.hud = {}
local HUD = st.hud

local CS_SPELL_ID = 35395
local JUDGEMENT_SPELL_ID = 20271
local CONSECRATION_SPELL_ID = 26573
local EXORCISM_SPELL_ID = 27138
local WINGS_SPELL_ID = 31884
local CS_COOLDOWN, JUDGEMENT_COOLDOWN, CONSECRATION_COOLDOWN, EXORCISM_COOLDOWN = 6, 8, 8, 15
local WINGS_COOLDOWN = 180
local TRINKET_FALLBACK_ICON = { [13] = 133450, [14] = 133448 }   -- the WA's empty-slot icons
local TICK = 0.05
local WARN_SECONDS = 3            -- the WA turns the text red under 3 s
local GCD_TEXT_HIDE = 2           -- ... and hides it for cooldowns shorter than 2 s (the GCD)

-- Icon order and identity. `key` = settings suffix (hud_show_<key>).
HUD.slots = {
	{ key = "cs", title = "Crusader Strike", spell = CS_SPELL_ID },
	{ key = "judgement", title = "Judgement", spell = JUDGEMENT_SPELL_ID },
	{ key = "consecration", title = "Consecration", spell = CONSECRATION_SPELL_ID },
	{ key = "exorcism", title = "Exorcism", spell = EXORCISM_SPELL_ID },
	{ key = "trinket1", title = "Trinket 1", inv_slot = 13 },
	{ key = "trinket2", title = "Trinket 2", inv_slot = 14 },
	{ key = "wings", title = "Avenging Wrath", spell = WINGS_SPELL_ID },
}

HUD.frame = nil
HUD.icons = {}
HUD.update_counter = 0
HUD.trinkets = { [13] = {}, [14] = {} }   -- per slot: item, buff, icd, icd_expires, proc_expires, proc_duration

local COLOR_NO_MANA = { 0.50, 0.50, 1.00 }
local COLOR_OUT_OF_RANGE = { 1.00, 0.25, 0.25 }
local COLOR_WHITE = { 1, 1, 1 }

local outline_map = { _none = "", outline = "OUTLINE", thick_outline = "THICKOUTLINE" }

local function db() return ST.db.profile end

local function previewing()
	return st.editmode ~= nil and st.editmode.active ~= nil and st.editmode.active()
end

--=========================================================================================
-- Readers
--=========================================================================================

-- Remaining time and full duration of an ability's real cooldown, practice-aware
-- (Practice Mode simulates CS / Judgement / Consecration cooldowns in st.practice.sim).
local function ability_cooldown(slot)
	local remaining = 0
	if slot.spell == CS_SPELL_ID then
		remaining = st.nextaction.get_cs_remaining()
		if remaining >= 999 then remaining = 0 end  -- CS not known: nothing to count
		return remaining, CS_COOLDOWN
	elseif slot.spell == JUDGEMENT_SPELL_ID then
		return st.nextaction.get_judge_remaining(), JUDGEMENT_COOLDOWN
	elseif slot.spell == CONSECRATION_SPELL_ID then
		local r = st.nextaction.get_filler_remaining("consecration")
		return r or 0, CONSECRATION_COOLDOWN
	elseif slot.spell == EXORCISM_SPELL_ID then
		local r = st.nextaction.get_filler_remaining("exorcism")
		return r or 0, EXORCISM_COOLDOWN
	elseif slot.spell == WINGS_SPELL_ID then
		-- straight from the API, ignoring the GCD echo (a real cooldown is minutes long)
		if st.practice and st.practice.active then return 0, WINGS_COOLDOWN end
		local start, duration = GetSpellCooldown(WINGS_SPELL_ID)
		if start and duration and duration > 1.51 then
			local r = start + duration - GetTime()
			if r > 0 then return r, duration end
		end
		return 0, WINGS_COOLDOWN
	end
	return 0, 0
end

-- The running GCD (SwedgeTimer's own tracking, also fed by Practice Mode).
local function gcd_remaining()
	if st.player.gcd_lockout and (st.player.active_gcd_remaining or 0) > 0 then
		return st.player.active_gcd_remaining, st.player.spell_gcd_duration or 1.5
	end
	return 0, 0
end

local function spell_name(id)
	local name = GetSpellInfo(id)
	return name
end

-- WA "insufficientResources": IsUsableSpell's second return
local function no_mana(slot)
	if st.practice and st.practice.active then return false end
	local name = spell_name(slot.spell)
	if not name or not IsUsableSpell then return false end
	local usable, nomana = IsUsableSpell(name)
	return nomana and true or false
end

-- WA "spellInRange == 0": IsSpellInRange returns 0 out of range, 1 in range, nil n/a
local function out_of_range(slot)
	if st.practice and st.practice.active then return false end
	if not (UnitExists and UnitExists("target")) then return false end
	local name = spell_name(slot.spell)
	if not name or not IsSpellInRange then return false end
	return IsSpellInRange(name, "target") == 0
end

local function target_is_exorcisable()
	if st.practice and st.practice.active then return true end
	if not (UnitExists and UnitExists("target")) then return false end
	local ctype = UnitCreatureType and UnitCreatureType("target")
	local types = st.nextaction and st.nextaction.exorcism_target_types
	return ctype ~= nil and types ~= nil and types[ctype] == true
end

--=========================================================================================
-- Trinkets
--=========================================================================================
function HUD.read_trinket(inv_slot)
	local t = HUD.trinkets[inv_slot]
	local item = GetInventoryItemID and GetInventoryItemID("player", inv_slot) or nil
	if item ~= t.item then
		t.item = item
		t.buff = item and st.data.trinket_buffs[item] or nil
		t.icd = item and st.data.trinket_icd[item] or nil
		t.icd_expires = nil
		t.proc_expires, t.proc_duration = nil, nil
	end
end

function HUD.read_trinkets()
	HUD.read_trinket(13)
	HUD.read_trinket(14)
end

-- The proc buff's remaining time, from the player's buffs (by spell id).
local function scan_trinket_proc(t)
	t.proc_expires, t.proc_duration = nil, nil
	if not (t.buff and UnitBuff) then return end
	for i = 1, 40 do
		local name, _, _, _, duration, expires, _, _, _, spell_id = UnitBuff("player", i)
		if not name then break end
		if spell_id == t.buff then
			t.proc_expires, t.proc_duration = expires, duration
			return
		end
	end
end

-- CLEU: the proc landing starts the trinket's internal cooldown
function HUD.on_aura_applied(dest_guid, spell_id)
	local me = st.player.guid or (UnitGUID and UnitGUID("player"))
	if dest_guid ~= me then return end
	for _, inv_slot in ipairs({ 13, 14 }) do
		local t = HUD.trinkets[inv_slot]
		if t.buff and spell_id == t.buff and t.icd then
			t.icd_expires = GetTime() + t.icd
		end
	end
end

--=========================================================================================
-- Frame construction
--=========================================================================================
local function apply_font(fs)
	local p = db()
	local path = SML:Fetch("font", p.hud_font)
	local outline = outline_map[p.hud_text_outline] or "OUTLINE"
	local ok = path and fs:SetFont(path, p.hud_text_size or 16, outline)
	if ok == false or not fs:GetFont() then
		fs:SetFont(STANDARD_TEXT_FONT, p.hud_text_size or 16, outline)
	end
end

local function create_icon(parent, slot, index)
	local f = CreateFrame("Frame", addon_name .. "HudIcon" .. index, parent)
	f.slot = slot
	f.texture = f:CreateTexture(nil, "ARTWORK")
	f.texture:SetAllPoints()
	f.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	if slot.spell then
		f.texture:SetTexture(GetSpellTexture(slot.spell))
	end

	f.border_frame = CreateFrame("Frame", nil, f, "BackdropTemplate")
	f.border_frame:SetAllPoints()

	f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cooldown:SetAllPoints()
	f.cooldown:SetHideCountdownNumbers(true)
	f.cooldown:SetDrawEdge(false)
	f.cooldown:Hide()

	f.text_frame = CreateFrame("Frame", nil, f)
	f.text_frame:SetAllPoints()
	f.text_frame:SetFrameLevel(f.cooldown:GetFrameLevel() + 1)
	f.text = f.text_frame:CreateFontString(nil, "OVERLAY")
	f.text:SetPoint("CENTER", 0, 0)
	f.text:SetJustifyH("CENTER")
	f.text:SetShadowColor(0, 0, 0, 1)
	f.text:SetShadowOffset(0, 0)

	f.cd_key = nil          -- what the swipe currently shows, to call SetCooldown once
	f.glowing = false
	return f
end

function HUD.init()
	local p = db()
	local frame = CreateFrame("Frame", addon_name .. "HudFrame", UIParent)
	HUD.frame = frame
	frame:SetSize(36, 36)
	frame:SetPoint("CENTER", UIParent, "CENTER", p.hud_x or 0, p.hud_y or -236)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	for i, slot in ipairs(HUD.slots) do
		HUD.icons[i] = create_icon(frame, slot, i)
	end
	HUD.read_trinkets()

	HUD.event_frame = CreateFrame("Frame")
	HUD.event_frame:SetScript("OnEvent", function(_, event, ...)
		if event == "COMBAT_LOG_EVENT_UNFILTERED" then
			local _, sub, _, _, _, _, _, dest_guid, _, _, _, spell_id = CombatLogGetCurrentEventInfo()
			if sub == "SPELL_AURA_APPLIED" then HUD.on_aura_applied(dest_guid, spell_id) end
		else
			HUD.read_trinkets()
		end
	end)
	HUD.event_frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	HUD.event_frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	HUD.event_frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

	frame:Hide()
	HUD.apply_settings()
end

--=========================================================================================
-- Visibility
--=========================================================================================
function HUD.should_show()
	local p = db()
	if previewing() then return true end
	if not p.bar_enabled then return false end   -- the addon's master switch (footer / minimap)
	if not p.hud_enabled then return false end
	if st.practice and st.practice.active then return true end
	if p.ret_only and not st.utils.is_ret_spec then return false end
	if p.hud_visibility_key == "in_combat" then
		return st.core.in_combat
	elseif p.hud_visibility_key == "in_combat_or_target" then
		return st.core.in_combat or (UnitExists and UnitExists("target") and UnitCanAttack
			and UnitCanAttack("player", "target")) or false
	end
	return true
end

local function slot_shown(slot)
	local p = db()
	if not p["hud_show_" .. slot.key] then return false end
	if slot.inv_slot and not previewing() then
		return HUD.trinkets[slot.inv_slot].item ~= nil   -- the WA hides an empty slot
	end
	return true
end

--=========================================================================================
-- Layout and style (settings -> frames)
--=========================================================================================

-- Icon size that makes `n` icons with `spacing` between them exactly as wide as the
-- bar's visible outline.
function HUD.matched_icon_size(n, spacing)
	local p = db()
	local outline = (st.bar and st.bar.visible_outline and st.bar.visible_outline()) or 0
	local width = (p.bar_width or 345) + 2 * outline
	return math.max(8, (width - math.max(0, n - 1) * spacing) / n)
end

function HUD.apply_settings()
	local frame = HUD.frame
	if not frame then return end
	local p = db()
	local size = p.hud_icon_size or 36
	local spacing = p.hud_spacing or 2
	local vertical = p.hud_orientation == "vertical"
	local border = p.hud_border_size or 2
	local bc = p.hud_border_color or { 0, 0, 0, 1 }

	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", p.hud_x or 0, p.hud_y or -236)

	local n = 0
	for i, icon in ipairs(HUD.icons) do
		if slot_shown(icon.slot) then n = n + 1 end
	end
	-- match the bar: the row is exactly as wide as the bar AS DRAWN (outline included),
	-- the icons sized to fill it. Rows only - a column has no width to match.
	if p.hud_match_bar_width and not vertical and n > 0 then
		size = HUD.matched_icon_size(n, spacing)
	end
	HUD.current_icon_size = size
	local span = n * size + math.max(0, n - 1) * spacing
	if vertical then frame:SetSize(size, math.max(span, 1)) else frame:SetSize(math.max(span, 1), size) end

	local offset = 0
	for _, icon in ipairs(HUD.icons) do
		icon:SetSize(size, size)
		icon:ClearAllPoints()
		if slot_shown(icon.slot) then
			if vertical then
				icon:SetPoint("TOP", frame, "TOP", 0, -offset)
			else
				icon:SetPoint("LEFT", frame, "LEFT", offset, 0)
			end
			offset = offset + size + spacing
			icon:Show()
		else
			icon:Hide()
			if icon.glowing then LCG.ProcGlow_Stop(icon, "hud"); icon.glowing = false end
		end
		if border > 0 then
			icon.border_frame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = border })
			icon.border_frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
			icon.border_frame:Show()
		else
			icon.border_frame:Hide()
		end
		apply_font(icon.text)
		if icon.slot.spell then
			icon.texture:SetTexture(GetSpellTexture(icon.slot.spell))
		end
	end

	if HUD.should_show() then
		HUD.update_display()
	else
		frame:Hide()
	end
end

--=========================================================================================
-- Per-icon state -> visuals
--=========================================================================================
local function format_time(r)
	if r < WARN_SECONDS then return string.format("%.1f", r) end
	return string.format("%d", math.floor(r + 0.5))
end

-- state = { remaining, duration, start, reverse, text, desaturate, tint, glow, texture, hidden }
local function paint(icon, s)
	local p = db()
	if s.texture then icon.texture:SetTexture(s.texture) end

	-- swipe: one SetCooldown per distinct cooldown (start/duration pair)
	local key = s.duration and s.duration > 0 and (string.format("%.2f", s.start) .. "/" .. s.duration .. (s.reverse and "r" or "")) or nil
	if key ~= icon.cd_key then
		icon.cd_key = key
		if key then
			icon.cooldown:SetReverse(s.reverse and true or false)
			icon.cooldown:SetCooldown(s.start, s.duration)
			icon.cooldown:Show()
		else
			icon.cooldown:SetCooldown(0, 0)
			icon.cooldown:Hide()
		end
	end

	-- remaining time text
	if p.hud_show_text and s.text_remaining and s.text_remaining > 0 then
		icon.text:SetText(format_time(s.text_remaining))
		local c = (s.text_remaining < WARN_SECONDS) and (p.hud_text_warn_color or { 1, 0.4, 0.42, 1 })
			or (p.hud_text_color or { 0.98, 1, 0, 1 })
		icon.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
		icon.text:Show()
	else
		icon.text:Hide()
	end

	icon.texture:SetDesaturated(p.hud_desaturate and s.desaturate or false)
	local tint = s.tint or COLOR_WHITE
	icon.texture:SetVertexColor(tint[1], tint[2], tint[3], 1)

	local want_glow = p.hud_glow_enabled and s.glow and true or false
	if want_glow and not icon.glowing then
		icon.glowing = true
		LCG.ProcGlow_Start(icon, { key = "hud", startAnim = true })
	elseif not want_glow and icon.glowing then
		icon.glowing = false
		LCG.ProcGlow_Stop(icon, "hud")
	end
end

-- Ability icons (CS / Judgement / Consecration / Exorcism)
local function ability_state(slot, now)
	local p = db()
	local s = {}
	local remaining, full = ability_cooldown(slot)
	local on_cd = remaining > 0
	if on_cd then
		s.start, s.duration, s.remaining = now - (full - remaining), full, remaining
		s.text_remaining = remaining
	elseif slot.spell ~= JUDGEMENT_SPELL_ID and slot.spell ~= WINGS_SPELL_ID then
		-- the GCD shows as a swipe (WA "show GCD"), its text is hidden (< 2 s rule)
		local g, gd = gcd_remaining()
		if g > 0 then
			s.start, s.duration = now - (gd - g), gd
			on_cd = true
			if gd >= GCD_TEXT_HIDE then s.text_remaining = g end
		end
	end
	s.desaturate = on_cd
	if p.hud_mana_tint and no_mana(slot) then
		s.tint = COLOR_NO_MANA
	elseif p.hud_range_tint and out_of_range(slot) then
		s.tint = COLOR_OUT_OF_RANGE
	end
	if slot.spell == JUDGEMENT_SPELL_ID then
		local sealed = (st.player.n_active_seals or 0) > 0
		if not sealed then s.desaturate = true end
	elseif slot.spell == EXORCISM_SPELL_ID then
		local ok_target = target_is_exorcisable()
		if not ok_target then s.desaturate = true end
		s.glow = ok_target and remaining <= 0 and st.core.in_combat
	elseif slot.spell == WINGS_SPELL_ID then
		-- wings glow the moment they are ready (in combat), whatever else is going on
		s.glow = remaining <= 0 and st.core.in_combat
	end
	return s
end

-- Trinket icons: on-use cooldown > proc buff > internal cooldown > idle. An on-use
-- trinket (Bloodlust Brooch...) starts its cooldown the moment it is pressed, so that
-- is what its icon counts - its buff never shows as a "proc". A proc trinket (DST...)
-- has no use cooldown, so its buff shows while up, then its internal cooldown.
local function trinket_state(slot, now)
	local t = HUD.trinkets[slot.inv_slot]
	local s = {}
	s.texture = (GetInventoryItemTexture and GetInventoryItemTexture("player", slot.inv_slot))
		or TRINKET_FALLBACK_ICON[slot.inv_slot]
	scan_trinket_proc(t)
	local use_start, use_duration, use_enable = 0, 0, 1
	if GetInventoryItemCooldown then
		use_start, use_duration, use_enable = GetInventoryItemCooldown("player", slot.inv_slot)
	end
	local on_use_cd = use_enable == 1 and (use_duration or 0) > 1.5
		and use_start + use_duration > now
	if on_use_cd then
		s.start, s.duration = use_start, use_duration
		s.text_remaining = use_start + use_duration - now
		s.desaturate = true
	elseif t.proc_expires and t.proc_expires > now then
		s.start, s.duration = t.proc_expires - (t.proc_duration or 0), t.proc_duration or 0
		s.text_remaining = t.proc_expires - now
	elseif t.icd_expires and t.icd_expires > now then
		s.start, s.duration, s.reverse = t.icd_expires - t.icd, t.icd, true
		s.text_remaining = t.icd_expires - now
	else
		if t.icd_expires and t.icd_expires <= now then t.icd_expires = nil end
	end
	return s
end

-- Design mode sample: every enabled icon in a representative state, on looping
-- clocks so the swipes and numbers actually run:
--   CS         a full 6 s cooldown, then 1.5 s ready, on repeat
--   Judgement  ready             Conse      no mana (blue)
--   Exorcism   ready against a valid target (glow)    Wings   ready (glow)
--   Trinket 1  a 10 s proc followed by its 20 s internal cooldown (reversed)
--   Trinket 2  a 45 s on-use cooldown counting down (grey)
local function preview_state(slot, now, index)
	local s = {}
	if slot.inv_slot then
		s.texture = (GetInventoryItemTexture and GetInventoryItemTexture("player", slot.inv_slot))
			or TRINKET_FALLBACK_ICON[slot.inv_slot]
		if slot.inv_slot == 13 then
			local t = now % 30
			if t < 10 then
				s.start, s.duration, s.text_remaining = now - t, 10, 10 - t
			else
				s.start, s.duration, s.reverse, s.text_remaining = now - (t - 10), 20, true, 30 - t
			end
		else
			local t = now % 45
			s.start, s.duration, s.text_remaining, s.desaturate = now - t, 45, 45 - t, true
		end
	elseif slot.spell == CS_SPELL_ID then
		local t = now % 7.5
		if t < 6 then
			s.start, s.duration, s.text_remaining, s.desaturate = now - t, 6, 6 - t, true
		end
	elseif slot.spell == CONSECRATION_SPELL_ID then
		s.tint = COLOR_NO_MANA
	elseif slot.spell == EXORCISM_SPELL_ID then
		s.glow = true
	elseif slot.spell == WINGS_SPELL_ID then
		s.glow = true
	end
	return s
end

function HUD.update_display()
	local frame = HUD.frame
	if not frame then return end
	if not frame:IsShown() then frame:Show() end
	local now = GetTime()
	local preview = previewing() and not (st.practice and st.practice.active)
	frame:SetAlpha(preview and not db().hud_enabled and 0.35 or 1)
	for i, icon in ipairs(HUD.icons) do
		if icon:IsShown() then
			local s
			if preview then
				s = preview_state(icon.slot, now, i)
			elseif icon.slot.inv_slot then
				s = trinket_state(icon.slot, now)
			else
				s = ability_state(icon.slot, now)
			end
			paint(icon, s)
		end
	end
end

--=========================================================================================
-- Per-frame update, called from st.player.frame_on_update
--=========================================================================================
function HUD.on_update(elapsed)
	local frame = HUD.frame
	if not frame then return end
	HUD.update_counter = HUD.update_counter + (elapsed or 0.016)
	if HUD.update_counter < TICK then return end
	HUD.update_counter = 0
	if not HUD.should_show() then
		if frame:IsShown() then frame:Hide() end
		return
	end
	-- an empty trinket slot filled (or emptied) re-flows the row
	local layout_key = tostring(slot_shown(HUD.slots[5])) .. tostring(slot_shown(HUD.slots[6]))
	if layout_key ~= HUD.layout_key then
		HUD.layout_key = layout_key
		HUD.apply_settings()
		return
	end
	HUD.update_display()
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed hud.lua module correctly') end
