-- bar.lua =============================================================================
local addon_name, st = ...
local print = st.utils.print_msg
local SML = LibStub("LibSharedMedia-3.0")
local ST = LibStub("AceAddon-3.0"):GetAddon("SwedgeTimer")
local LCG = LibStub("LibCustomGlow-1.0")

--=========================================================================================
-- BAR SETTINGS
--=========================================================================================
st.bar = {}

-- Sound file paths for twist window notification
local twist_sounds = {
    -- Original sounds
    ["pop"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\pop.ogg",
    ["bubble-pop"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\bubble-pop.ogg",
    ["swoosh"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\swoosh.ogg",
    ["whoopee"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\whoopee.ogg",
    -- Instruments
    ["AcousticGuitar"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\AcousticGuitar.ogg",
    ["Brass"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Brass.mp3",
    ["Drums"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Drums.ogg",
    ["Glass"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Glass.mp3",
    ["SynthChord"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\SynthChord.ogg",
    ["TempleBellHuge"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\TempleBellHuge.ogg",
    ["Xylophone"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Xylophone.ogg",
    -- Alerts & UI
    ["AirHorn"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\AirHorn.ogg",
    ["BikeHorn"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\BikeHorn.ogg",
    ["ErrorBeep"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\ErrorBeep.ogg",
    ["RingingPhone"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\RingingPhone.ogg",
    ["RobotBlip"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\RobotBlip.ogg",
    ["WarningSiren"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\WarningSiren.ogg",
    ["WaterDrop"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\WaterDrop.ogg",
    -- Animals
    ["Bleat"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Bleat.ogg",
    ["CatMeow2"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\CatMeow2.ogg",
    ["ChickenAlarm"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\ChickenAlarm.ogg",
    ["CowMooing"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\CowMooing.ogg",
    ["GoatBleating"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\GoatBleating.ogg",
    ["KittenMeow"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\KittenMeow.ogg",
    ["RoaringLion"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\RoaringLion.ogg",
    ["RoosterChickenCalls"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\RoosterChickenCalls.ogg",
    ["SheepBleat"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\SheepBleat.ogg",
    -- Combat & Action
    ["Bloodlust"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Bloodlust.ogg",
    ["BatmanPunch"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\BatmanPunch.ogg",
    ["Blast"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Blast.ogg",
    ["BoxingArenaSound"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\BoxingArenaSound.ogg",
    ["DoubleWhoosh"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\DoubleWhoosh.ogg",
    ["SharpPunch"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\SharpPunch.ogg",
    ["Shotgun"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Shotgun.ogg",
    -- Cartoon & Fun
    ["Applause"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Applause.ogg",
    ["BananaPeelSlip"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\BananaPeelSlip.ogg",
    ["CartoonVoiceBaritone"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\CartoonVoiceBaritone.ogg",
    ["CartoonWalking"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\CartoonWalking.ogg",
    ["HeartbeatSingle"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\HeartbeatSingle.ogg",
    ["SqueakyToyShort"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\SqueakyToyShort.ogg",
    ["SquishFart"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\SquishFart.ogg",
    ["TadaFanfare"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\TadaFanfare.ogg",
    -- Voice Callouts
    ["Adds"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Adds.ogg",
    ["Boss"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Boss.ogg",
    ["DontRelease"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\DontRelease.ogg",
    ["Empowered"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Empowered.ogg",
    ["Focus"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Focus.ogg",
    ["Idiot"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Idiot.ogg",
    ["OhNo"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\OhNo.ogg",
    ["Protected"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Protected.ogg",
    ["Release"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Release.ogg",
    ["RunAway"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\RunAway.ogg",
    ["Spread"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Spread.ogg",
    ["Stack"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Stack.ogg",
    ["Taunt"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Taunt.ogg",
    -- Shapes (Markers)
    ["Circle"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Circle.ogg",
    ["Cross"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Cross.ogg",
    ["Diamond"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Diamond.ogg",
    ["Left"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Left.ogg",
    ["Moon"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Moon.ogg",
    ["Right"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Right.ogg",
    ["Skull"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Skull.ogg",
    ["Square"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Square.ogg",
    ["Star"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Star.ogg",
    ["Triangle"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Triangle.ogg",
    -- Misc
    ["Next"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Next.ogg",
    ["Portal"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Portal.ogg",
    ["Switch"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Switch.ogg",
    ["Torch"] = "Interface\\AddOns\\SwedgeTimer\\Sounds\\Torch.ogg",
}
st.bar.twist_sounds = twist_sounds

-- the following should be flagged when the swing speed changes to
-- evaluate the new offsets for ticks
st.bar.recalculate_ticks = true
st.bar.twist_tick_offset = 0.1
st.bar.gcd1_tick_offset = 0.1
st.bar.gcd_bar_width = 0.0

-- Twist success feedback state
st.bar.twist_success_glow_active = false
st.bar.twist_success_glow_timer = 0

-- Custom animation state
st.bar.custom_anims = {}

-- Successful twist text state
st.bar.success_text_frame = nil
st.bar.success_text_visible = false
st.bar.success_text_timer = 0

--=========================================================================================
-- Drag and drop handlers
--=========================================================================================
st.bar.OnFrameDragStart = function()
    if not ST.db.profile.bar_locked then
        st.bar.frame:StartMoving()
    end
end

st.bar.OnFrameDragStop = function()
    local frame = st.bar.frame
    local db = ST.db.profile
    frame:StopMovingOrSizing()
    local point, _, rel_point, x_offset, y_offset = frame:GetPoint()
    db.bar_x_offset = st.utils.simple_round(x_offset, 0.1)
    db.bar_y_offset = st.utils.simple_round(y_offset, 0.1)
    db.bar_point = point
    db.bar_rel_point = rel_point
    st.set_bar_position()
    st.bar.set_bar_color()
end

--=========================================================================================
-- Icon frame drag and drop handlers
--=========================================================================================
st.bar.OnIconFrameDragStart = function()
    if not ST.db.profile.icon_locked and ST.db.profile.icon_detached then
        st.bar.icon_frame:StartMoving()
    end
end

st.bar.OnIconFrameDragStop = function()
    local frame = st.bar.icon_frame
    local db = ST.db.profile
    frame:StopMovingOrSizing()
    local point, _, rel_point, x_offset, y_offset = frame:GetPoint()
    db.icon_x_offset = st.utils.simple_round(x_offset, 0.1)
    db.icon_y_offset = st.utils.simple_round(y_offset, 0.1)
    db.icon_point = point
    db.icon_rel_point = rel_point
end

--=========================================================================================
-- Success text frame drag and drop handlers
--=========================================================================================
st.bar.OnSuccessTextDragStart = function()
    if not ST.db.profile.successful_twist_text_locked then
        st.bar.success_text_frame:StartMoving()
    end
end

st.bar.OnSuccessTextDragStop = function()
    local frame = st.bar.success_text_frame
    local db = ST.db.profile
    frame:StopMovingOrSizing()
    local point, _, rel_point, x_offset, y_offset = frame:GetPoint()
    db.successful_twist_text_x_offset = st.utils.simple_round(x_offset, 0.1)
    db.successful_twist_text_y_offset = st.utils.simple_round(y_offset, 0.1)
    db.successful_twist_text_point = point
    db.successful_twist_text_rel_point = rel_point
end

--=========================================================================================
-- Intialisation and setting change functionality
--=========================================================================================

-- this function is called once to initialise all the graphics of the bar
st.bar.init_bar_visuals = function()
    st.bar.frame = CreateFrame("Frame", addon_name .. "BarFrame", UIParent)   
    local frame = st.bar.frame

    local db = ST.db.profile

    -- Set initial frame properties
    frame:SetPoint("CENTER")
    frame:SetMovable(not db.bar_locked)
    frame:EnableMouse(not db.bar_locked)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", st.bar.OnFrameDragStart)
    frame:SetScript("OnDragStop", st.bar.OnFrameDragStop)
    frame:SetHeight(db.bar_height)
    frame:SetWidth(db.bar_width)
    frame:ClearAllPoints()
    frame:SetPoint(db.bar_point, UIParent, db.bar_rel_point, db.bar_x_offset, db.bar_y_offset)

    -- Create the backplane and border
    frame.backplane = CreateFrame("Frame", addon_name .. "BarBackdropFrame", frame, "BackdropTemplate")

    -- Adjust the frame draw levels so the backplane is below the frame
    frame:SetFrameLevel(db.draw_level+1)
    frame.backplane:SetFrameLevel(db.draw_level)
    -- Set to the requested frame strata
    frame:SetFrameStrata(db.frame_strata)
    frame.backplane:SetFrameStrata(db.frame_strata)

    -- Configure the backplane/outline
    st.configure_bar_outline()

    -- Create the swing timer bar
    frame.bar = frame:CreateTexture(nil,"ARTWORK")
    frame.bar:SetPoint("TOPLEFT", 0, 0)
    frame.bar:SetHeight(db.bar_height)
    frame.bar:SetTexture(SML:Fetch('statusbar', db.bar_texture_key))
    frame.bar:SetVertexColor(unpack(db.bar_color_default))

    -- Create the GCD timer bar
    frame.gcd_bar = frame:CreateTexture(nil, "ARTWORK")
    frame.gcd_bar:SetPoint("TOPLEFT", 0, 0)
    frame.gcd_bar:SetHeight(db.bar_height)
    frame.gcd_bar:SetTexture(SML:Fetch('statusbar', db.gcd_texture_key))
    frame.gcd_bar:SetVertexColor(unpack(db.bar_color_gcd))
    frame.gcd_bar:SetDrawLayer("ARTWORK", -2)

    -- Create the deadzone bar
    frame.deadzone = frame:CreateTexture(nil, "ARTWORK")
    frame.deadzone:SetPoint("TOPRIGHT", 0, 0)
    st.set_deadzone()
    frame.deadzone:SetHeight(db.bar_height)
    frame.deadzone:SetDrawLayer("ARTWORK", -1)
    if not db.enable_deadzone then
        frame.deadzone:Hide()
    end

    -- Create the attack speed/swing timer texts and init them
    frame.left_text = frame:CreateFontString(nil, "OVERLAY")
    frame.left_text:SetShadowColor(0.0,0.0,0.0,1.0)
    frame.left_text:SetShadowOffset(1,-1)
    frame.left_text:SetJustifyV("MIDDLE")  -- TBC Classic: use MIDDLE instead of CENTER
    frame.left_text:SetJustifyH("LEFT")

    frame.right_text = frame:CreateFontString(nil, "OVERLAY")
    frame.right_text:SetShadowColor(0.0,0.0,0.0,1.0)
    frame.right_text:SetShadowOffset(1,-1)
    frame.right_text:SetJustifyV("MIDDLE")  -- TBC Classic: use MIDDLE instead of CENTER
    frame.right_text:SetJustifyH("RIGHT")

    frame.center_text = frame:CreateFontString(nil, "OVERLAY")
    frame.center_text:SetShadowColor(0.0,0.0,0.0,1.0)
    frame.center_text:SetShadowOffset(1,-1)
    frame.center_text:SetJustifyV("MIDDLE")
    frame.center_text:SetJustifyH("CENTER")
    st.set_fonts()

    -- Create the line markers as textures (TBC Classic compatible)
    -- Twist window marker
    frame.twist_line = frame:CreateTexture(nil, "OVERLAY", nil, -1)
    frame.twist_line:SetWidth(db.marker_width)
    frame.twist_line:SetHeight(db.bar_height)

    -- GCD marker
    frame.gcd1_line = frame:CreateTexture(nil, "OVERLAY", nil, -1)
    frame.gcd1_line:SetWidth(db.marker_width)
    frame.gcd1_line:SetHeight(db.bar_height)

    -- Judgement cooldown marker
    frame.judgement_line = frame:CreateTexture(nil, "OVERLAY", nil, -1)
    frame.judgement_line:SetWidth(db.marker_width)
    frame.judgement_line:SetHeight(db.bar_height)

    st.set_markers()

	-- Initialize custom twist success animations
	st.bar.init_custom_animations()

	-- Initialize seal icons
	st.bar.init_seal_icon()

	-- Initialize successful twist text frame
	st.bar.init_success_text_frame()

	frame:Show()
    if st.debug then print('Successfully initialised all bar visuals.') end
end

--=========================================================================================
-- Custom Twist Success Animations
--=========================================================================================
st.bar.init_custom_animations = function()
	local anims = st.bar.custom_anims

	-- ==========================================
	-- Holy Nova Burst - Expanding golden rings
	-- Uses OnUpdate for TBC Classic compatibility
	-- ==========================================
	anims.holy_nova = CreateFrame("Frame", addon_name.."HolyNovaFrame", st.bar.frame)
	local nova = anims.holy_nova
	nova:SetFrameStrata("HIGH")
	nova:SetAllPoints(st.bar.frame)
	nova:Hide()

	-- Create primary ring texture
	nova.ring = nova:CreateTexture(nil, "OVERLAY")
	nova.ring:SetTexture("Interface\\Cooldown\\star4")
	nova.ring:SetBlendMode("ADD")
	nova.ring:SetPoint("CENTER", st.bar.frame, "CENTER", 0, 0)
	nova.base_size = 100

	-- Create secondary ring for more visual density (slightly delayed/larger)
	nova.ring2 = nova:CreateTexture(nil, "OVERLAY")
	nova.ring2:SetTexture("Interface\\Cooldown\\star4")
	nova.ring2:SetBlendMode("ADD")
	nova.ring2:SetPoint("CENTER", st.bar.frame, "CENTER", 0, 0)
	nova.base_size2 = 120

	-- Animation state
	nova.active = false
	nova.elapsed = 0
	nova.duration = 0.4
	nova.color = {1, 1, 1, 1}

	-- OnUpdate handler for ring expansion
	nova:SetScript("OnUpdate", function(self, elapsed)
		if not self.active then return end

		self.elapsed = self.elapsed + elapsed
		local progress = self.elapsed / self.duration

		if progress >= 1.0 then
			self.active = false
			self:Hide()
			return
		end

		-- Ease out function for smooth deceleration
		local eased = 1 - (1 - progress) * (1 - progress)

		-- Primary ring: Scale from 0.3 to 3.0
		local scale = 0.3 + eased * 2.7
		local size = self.base_size * scale
		self.ring:SetSize(size, size)

		-- Secondary ring: Slightly delayed and larger
		local progress2 = math.max(0, progress - 0.08)
		local eased2 = 1 - (1 - progress2) * (1 - progress2)
		local scale2 = 0.3 + eased2 * 2.7
		local size2 = self.base_size2 * scale2
		self.ring2:SetSize(size2, size2)

		-- Alpha curve: stay bright longer, then fade
		-- Hold at high alpha for first 40%, then fade out
		local alpha
		if progress < 0.4 then
			alpha = 1.0
		else
			local fade_progress = (progress - 0.4) / 0.6
			alpha = 1 - (fade_progress * fade_progress)  -- Quadratic fade
		end
		alpha = alpha * (self.color[4] or 1)
		self.ring:SetAlpha(alpha)

		-- Secondary ring slightly dimmer
		local alpha2
		if progress2 < 0.35 then
			alpha2 = 0.8
		else
			local fade_progress2 = (progress2 - 0.35) / 0.65
			alpha2 = 0.8 * (1 - (fade_progress2 * fade_progress2))
		end
		alpha2 = alpha2 * (self.color[4] or 1)
		self.ring2:SetAlpha(alpha2)
	end)

	-- ==========================================
	-- Seal Twist Spiral - Particles spiral inward then burst
	-- ==========================================
	anims.seal_spiral = CreateFrame("Frame", addon_name.."SealSpiralFrame", st.bar.frame)
	local spiral = anims.seal_spiral
	spiral:SetFrameStrata("HIGH")
	spiral:SetAllPoints(st.bar.frame)
	spiral:Hide()

	-- Create particles
	spiral.particles = {}
	spiral.num_particles = 10
	for i = 1, spiral.num_particles do
		local particle = spiral:CreateTexture(nil, "OVERLAY")
		particle:SetTexture("Interface\\Cooldown\\star4")
		particle:SetBlendMode("ADD")
		particle:SetSize(12, 12)
		particle:SetPoint("CENTER", st.bar.frame, "CENTER", 0, 0)
		spiral.particles[i] = particle
	end

	-- Central burst flash
	spiral.burst = spiral:CreateTexture(nil, "OVERLAY")
	spiral.burst:SetTexture("Interface\\Cooldown\\starburst")
	spiral.burst:SetBlendMode("ADD")
	spiral.burst:SetPoint("CENTER", st.bar.frame, "CENTER", 0, 0)
	spiral.burst:SetSize(50, 50)
	spiral.burst:SetAlpha(0)

	-- Animation state
	spiral.active = false
	spiral.elapsed = 0
	spiral.duration = 0.5
	spiral.particle_angles = {}
	for i = 1, spiral.num_particles do
		spiral.particle_angles[i] = (i - 1) * (2 * math.pi / spiral.num_particles)
	end

	-- OnUpdate handler for parametric animation
	spiral:SetScript("OnUpdate", function(self, elapsed)
		if not self.active then return end

		self.elapsed = self.elapsed + elapsed
		local progress = self.elapsed / self.duration

		if progress >= 1.0 then
			self.active = false
			self:Hide()
			return
		end

		local db = ST.db.profile
		local color = db.twist_success_glow_color
		local bar_width = db.bar_width / 2
		local bar_height = db.bar_height / 2
		local max_radius = math.max(bar_width, bar_height) * 1.5

		if progress < 0.5 then
			-- Phase 1: Spiral inward (0 to 0.5)
			local inward_progress = progress / 0.5
			for i, particle in ipairs(self.particles) do
				local base_angle = self.particle_angles[i]
				local theta = base_angle + inward_progress * math.pi * 3  -- 1.5 rotations
				local r = max_radius * (1 - inward_progress * 0.95)
				local x = math.cos(theta) * r
				local y = math.sin(theta) * r * 0.5  -- Flatten for bar shape

				particle:ClearAllPoints()
				particle:SetPoint("CENTER", st.bar.frame, "CENTER", x, y)
				particle:SetAlpha(0.8 + 0.2 * (1 - inward_progress))
				particle:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
			end
			self.burst:SetAlpha(0)
		elseif progress < 0.55 then
			-- Phase 2: Central burst (0.5 to 0.55)
			local burst_progress = (progress - 0.5) / 0.05
			self.burst:SetAlpha(burst_progress)
			self.burst:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
			for _, particle in ipairs(self.particles) do
				particle:SetAlpha(0.5)
			end
		else
			-- Phase 3: Burst outward (0.55 to 1.0)
			local outward_progress = (progress - 0.55) / 0.45
			self.burst:SetAlpha(1 - outward_progress)

			for i, particle in ipairs(self.particles) do
				local base_angle = self.particle_angles[i]
				local r = max_radius * outward_progress * 1.5
				local x = math.cos(base_angle) * r
				local y = math.sin(base_angle) * r * 0.5

				particle:ClearAllPoints()
				particle:SetPoint("CENTER", st.bar.frame, "CENTER", x, y)
				particle:SetAlpha((1 - outward_progress) * 0.8)
			end
		end
	end)

	if st.debug then print('Successfully initialised custom animations.') end
end

-- Play Holy Nova Burst animation
st.bar.play_holy_nova = function(color, duration)
	local nova = st.bar.custom_anims.holy_nova
	if not nova then return end

	-- Set color and duration
	nova.color = color
	nova.duration = duration
	nova.elapsed = 0
	nova.active = true

	-- Set initial state for primary ring
	nova.ring:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	nova.ring:SetSize(nova.base_size * 0.3, nova.base_size * 0.3)
	nova.ring:SetAlpha(color[4] or 1)

	-- Set initial state for secondary ring
	nova.ring2:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	nova.ring2:SetSize(nova.base_size2 * 0.3, nova.base_size2 * 0.3)
	nova.ring2:SetAlpha(0)

	nova:Show()
end

-- Play Seal Twist Spiral animation
st.bar.play_seal_spiral = function(color, duration)
	local spiral = st.bar.custom_anims.seal_spiral
	if not spiral then return end

	-- Reset state
	spiral.elapsed = 0
	spiral.duration = duration
	spiral.active = true

	-- Reset particle positions
	local db = ST.db.profile
	local bar_width = db.bar_width / 2
	local bar_height = db.bar_height / 2
	local max_radius = math.max(bar_width, bar_height) * 1.5

	for i, particle in ipairs(spiral.particles) do
		local angle = spiral.particle_angles[i]
		local x = math.cos(angle) * max_radius
		local y = math.sin(angle) * max_radius * 0.5
		particle:ClearAllPoints()
		particle:SetPoint("CENTER", st.bar.frame, "CENTER", x, y)
		particle:SetAlpha(1)
		particle:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	end

	spiral.burst:SetAlpha(0)
	spiral.burst:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	spiral:Show()
end

-- Stop all custom animations
st.bar.stop_custom_animations = function()
	local anims = st.bar.custom_anims

	if anims.holy_nova then
		anims.holy_nova.active = false
		anims.holy_nova:Hide()
	end

	if anims.seal_spiral then
		anims.seal_spiral.active = false
		anims.seal_spiral:Hide()
	end
end

-- Function called when a twist attempt is detected (2 seals active on swing)
-- This triggers regardless of whether Command actually procs
st.bar.on_twist_attempt = function()
	local db = ST.db.profile

	if st.debug then print('Twist attempt detected!') end

	-- Suppress sound in ret-only mode when not ret spec
	if db.ret_only and not st.utils.is_ret_spec then return end

	-- Play sound
	if db.twist_success_sound_enabled then
		local sound_choice = db.twist_success_sound_choice or "TadaFanfare"
		local sound_path = twist_sounds[sound_choice]
		if sound_path then
			PlaySoundFile(sound_path, db.sound_channel or "Master")
		end
	end

	-- Trigger animated glow effect using LibCustomGlow
	if db.twist_success_glow_enabled and st.bar.frame then
		local color = db.twist_success_glow_color
		local glowType = db.twist_success_glow_type or "Pixel"

		if glowType == "Pixel" then
			LCG.PixelGlow_Start(
				st.bar.frame,                            -- frame
				color,                                   -- color {r,g,b,a}
				db.twist_success_glow_lines or 8,        -- N (lines)
				db.twist_success_glow_frequency or 0.25, -- frequency
				nil,                                     -- length (auto)
				db.twist_success_glow_thickness or 2,    -- thickness
				0, 0,                                    -- xOffset, yOffset
				false,                                   -- border
				"TwistSuccess"                           -- key
			)
		elseif glowType == "AutoCast" then
			LCG.AutoCastGlow_Start(
				st.bar.frame,
				color,
				db.twist_success_glow_lines or 4,
				db.twist_success_glow_frequency or 0.125,
				db.twist_success_glow_scale or 1,        -- scale
				0, 0,                                    -- offsets
				"TwistSuccess"
			)
		elseif glowType == "Button" then
			LCG.ButtonGlow_Start(
				st.bar.frame,
				color,
				db.twist_success_glow_frequency or 0.125,
				-1  -- negative frameLevel puts glow behind the bar
			)
		-- Custom animations (not using LibCustomGlow)
		elseif glowType == "HolyNova" then
			st.bar.play_holy_nova(color, db.twist_success_glow_duration)
		elseif glowType == "SealSpiral" then
			st.bar.play_seal_spiral(color, db.twist_success_glow_duration)
		end

		-- Set timer to stop the glow after duration (for LibCustomGlow effects)
		-- Custom animations handle their own timing
		if glowType ~= "HolyNova" and glowType ~= "SealSpiral" then
			st.bar.twist_success_glow_active = true
			st.bar.twist_success_glow_timer = db.twist_success_glow_duration
		end
	end
end

-- Function called when a true successful twist is detected (Command proc during twist attempt)
st.bar.on_successful_twist = function()
	if st.debug then print('SUCCESSFUL TWIST! Command procced!') end

	local db = ST.db.profile
	if db.successful_twist_text_enabled then
		st.bar.show_success_text()
	end
end

--=========================================================================================
-- Bar labels (left / center / right)
--=========================================================================================

-- Writes the configured values into the three bar labels. Called every frame from the
-- bar update and directly from the options when a label setting changes.
st.bar.update_texts = function(speed, timer)
	local frame = st.bar.frame
	if not frame or not frame.left_text then return end
	local db = ST.db.profile
	speed = speed or st.player.current_weapon_speed or 0
	timer = timer or st.player.swing_timer or 0
	local lookup = {
		attack_speed = format("%.1f", st.utils.simple_round(speed, 0.1)),
		swing_timer = format("%.1f", st.utils.simple_round(timer, 0.1)),
	}
	frame.left_text:SetText(lookup[db.left_text] or "")
	frame.right_text:SetText(lookup[db.right_text] or "")
	if frame.center_text then
		frame.center_text:SetText(lookup[db.center_text] or "")
	end
end

--=========================================================================================
-- Successful Twist Text Frame (independent of bar)
--=========================================================================================

local success_outline_map = {
	_none = "",
	outline = "OUTLINE",
	thick_outline = "THICKOUTLINE",
}

-- Applies the configured font to the success text. If the chosen SharedMedia font cannot
-- be loaded (for example media registered by another addon that is no longer installed)
-- the font string would render nothing at all, so fall back to the standard font.
local function apply_success_font(fs, db)
	local SML = LibStub("LibSharedMedia-3.0")
	local font_path = SML:Fetch('font', db.successful_twist_text_font)
	local outline = success_outline_map[db.successful_twist_text_outline] or "OUTLINE"
	local ok = font_path and fs:SetFont(font_path, db.successful_twist_text_size, outline)
	if ok == false or not fs:GetFont() then
		fs:SetFont(STANDARD_TEXT_FONT, db.successful_twist_text_size, outline)
	end
	fs:SetTextColor(unpack(db.successful_twist_text_color))
end

st.bar.init_success_text_frame = function()
	local db = ST.db.profile

	-- Create frame parented to UIParent (NOT the bar frame)
	st.bar.success_text_frame = CreateFrame("Frame", addon_name.."SuccessTextFrame", UIParent)
	local frame = st.bar.success_text_frame

	frame:SetSize(300, 50)
	frame:SetPoint(db.successful_twist_text_point, UIParent,
	               db.successful_twist_text_rel_point,
	               db.successful_twist_text_x_offset,
	               db.successful_twist_text_y_offset)
	frame:SetMovable(true)
	frame:EnableMouse(not db.successful_twist_text_locked and db.successful_twist_text_enabled)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", st.bar.OnSuccessTextDragStart)
	frame:SetScript("OnDragStop", st.bar.OnSuccessTextDragStop)
	-- Sit above scrolling combat text addons and other HUD frames so nothing covers it
	frame:SetFrameStrata("DIALOG")
	frame:SetFrameLevel(100)

	frame.text = frame:CreateFontString(nil, "OVERLAY")
	frame.text:SetPoint("CENTER", 0, 0)
	frame.text:SetShadowColor(0.0, 0.0, 0.0, 1.0)
	frame.text:SetShadowOffset(2, -2)

	-- Set font before setting text (required by WoW API)
	apply_success_font(frame.text, db)
	frame.text:SetText("Successful TWIST!")

	-- Fade animation via OnUpdate (only fades when locked)
	frame:SetScript("OnUpdate", function(self, elapsed)
		local db = ST.db.profile
		-- Design mode: always visible (ghosted when the feature is off) - unless the
		-- twist simulation runs, then the text fades in and out like in real play
		if st.bar.previewing() then
			if not (db.successful_twist_text_enabled and st.bar.simulating()) then
				frame:SetAlpha(db.successful_twist_text_enabled and 1 or 0.35)
				return
			end
		elseif not db.successful_twist_text_locked and db.successful_twist_text_enabled then
			-- When unlocked AND enabled, always show at full alpha for positioning
			frame:SetAlpha(1)
			return
		end
		-- When locked, handle fade animation
		if st.bar.success_text_visible then
			st.bar.success_text_timer = st.bar.success_text_timer - elapsed
			if st.bar.success_text_timer <= 0 then
				st.bar.success_text_visible = false
				frame:SetAlpha(0)
			elseif st.bar.success_text_timer < 0.3 then
				frame:SetAlpha(st.bar.success_text_timer / 0.3)
			else
				frame:SetAlpha(1)  -- Maintain full alpha while showing
			end
		end
	end)

	-- Show if unlocked and enabled, hide if locked or disabled
	if db.successful_twist_text_locked or not db.successful_twist_text_enabled then
		frame:SetAlpha(0)
	else
		frame:SetAlpha(1)
	end
end

st.bar.update_success_text_properties = function()
	if not st.bar.success_text_frame then return end
	apply_success_font(st.bar.success_text_frame.text, ST.db.profile)
end

st.bar.set_success_text_position = function()
	if not st.bar.success_text_frame then return end
	local db = ST.db.profile
	local frame = st.bar.success_text_frame
	frame:ClearAllPoints()
	frame:SetPoint(db.successful_twist_text_point, UIParent,
	               db.successful_twist_text_rel_point,
	               db.successful_twist_text_x_offset,
	               db.successful_twist_text_y_offset)
	frame:EnableMouse(not db.successful_twist_text_locked and db.successful_twist_text_enabled)
	-- Show when unlocked for positioning, hide when locked or disabled
	if st.bar.previewing() and not (db.successful_twist_text_enabled and st.bar.simulating()) then
		frame:SetAlpha(db.successful_twist_text_enabled and 1 or 0.35)
	elseif db.successful_twist_text_locked or not db.successful_twist_text_enabled then
		st.bar.success_text_visible = false
		frame:SetAlpha(0)
	else
		frame:SetAlpha(1)
	end
end

-- Sends the text to a scrolling combat text addon instead of the own frame: Mik's
-- Scrolling Battle Text (notification area) when it is loaded, otherwise Blizzard's
-- floating combat text. Returns true when one of them accepted the message.
st.bar.show_success_text_sct = function()
	local db = ST.db.profile
	local c = db.successful_twist_text_color or { 0, 1, 0, 1 }
	local text = "Successful TWIST!"
	if MikSBT and MikSBT.DisplayMessage then
		local SML = LibStub("LibSharedMedia-3.0")
		local font_path = SML:Fetch('font', db.successful_twist_text_font)
		local outline_index = ({ _none = 1, outline = 2, thick_outline = 3 })[db.successful_twist_text_outline] or 2
		local ok = pcall(MikSBT.DisplayMessage, text, MikSBT.DISPLAYTYPE_NOTIFICATION or "Notification", false,
			c[1] * 255, c[2] * 255, c[3] * 255, db.successful_twist_text_size, font_path, outline_index)
		if ok then return true end
	end
	if CombatText_AddMessage then
		local ok = pcall(CombatText_AddMessage, text, CombatText_StandardScroll, c[1], c[2], c[3], "crit", false)
		if ok then return true end
	end
	return false
end

st.bar.show_success_text = function()
	local db = ST.db.profile
	if db.successful_twist_text_mode == "sct" and st.bar.show_success_text_sct() then
		return
	end
	if not st.bar.success_text_frame then return end
	st.bar.success_text_visible = true
	st.bar.success_text_timer = db.successful_twist_text_duration
	st.bar.success_text_frame:SetAlpha(1)
	if st.debug then print('Success text shown (frame)') end
end

--=========================================================================================
-- Seal Icon Functions
--=========================================================================================

-- How far the bar's visible outline (the backplane's solid border) reaches beyond the
-- bar frame on each side. 0 in "None" / "Texture" border modes.
st.bar.visible_outline = function()
	local db = ST.db.profile
	if db.border_mode_key == "Solid" then
		return db.backplane_outline_width or 0
	end
	return 0
end

-- The seal icon size: matching the bar means matching the bar AS DRAWN, outline
-- included, so the icons line up with the bar's visible edges.
st.bar.effective_icon_size = function()
	local db = ST.db.profile
	if db.icon_match_bar_height then
		return db.bar_height + 2 * st.bar.visible_outline()
	end
	return db.icon_size
end

st.bar.init_seal_icon = function()
	local db = ST.db.profile

	-- Create icon container frame as child of UIParent for independent positioning
	st.bar.icon_frame = CreateFrame("Frame", addon_name.."IconFrame", UIParent, "BackdropTemplate")
	local icon_frame = st.bar.icon_frame

	-- Determine icon size
	local size = st.bar.effective_icon_size()

	-- Size (width allows for 2 icons side-by-side during twist)
	icon_frame:SetWidth(size * 2 + 2)
	icon_frame:SetHeight(size)

	-- Set up drag handlers for free positioning
	icon_frame:RegisterForDrag("LeftButton")
	icon_frame:SetScript("OnDragStart", st.bar.OnIconFrameDragStart)
	icon_frame:SetScript("OnDragStop", st.bar.OnIconFrameDragStop)

	-- Set frame strata to match bar
	icon_frame:SetFrameStrata(db.frame_strata)
	icon_frame:SetFrameLevel(db.draw_level + 1)

	-- Create primary icon texture
	icon_frame.seal_icon = icon_frame:CreateTexture(nil, "ARTWORK")
	icon_frame.seal_icon:SetSize(size, size)
	icon_frame.seal_icon:SetPoint("TOPLEFT", 0, 0)
	icon_frame.seal_icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- Crop edges for cleaner look

	-- Create cooldown frame for primary icon (TBC Classic compatible)
	icon_frame.seal_cooldown_1 = CreateFrame("Cooldown", nil, icon_frame, "CooldownFrameTemplate")
	icon_frame.seal_cooldown_1:SetAllPoints(icon_frame.seal_icon)  -- Match icon exactly
	icon_frame.seal_cooldown_1:SetReverse(true)  -- Reversed: swipe fills up as seal duration counts down
	icon_frame.seal_cooldown_1:SetHideCountdownNumbers(true)  -- Hide built-in timer text

	-- Create timer text for primary icon (above cooldown layer)
	-- Must use separate frame with higher frame level to render above cooldown swipe
	icon_frame.seal_timer_frame_1 = CreateFrame("Frame", nil, icon_frame)
	icon_frame.seal_timer_frame_1:SetAllPoints(icon_frame.seal_icon)
	icon_frame.seal_timer_frame_1:SetFrameLevel(icon_frame.seal_cooldown_1:GetFrameLevel() + 1)
	icon_frame.seal_timer_text_1 = icon_frame.seal_timer_frame_1:CreateFontString(nil, "OVERLAY")
	icon_frame.seal_timer_text_1:SetPoint("CENTER", 0, 0)
	icon_frame.seal_timer_text_1:SetShadowColor(0.0, 0.0, 0.0, 1.0)
	icon_frame.seal_timer_text_1:SetShadowOffset(2, -2)
	icon_frame.seal_timer_text_1:SetJustifyV("MIDDLE")
	icon_frame.seal_timer_text_1:SetJustifyH("CENTER")

	-- Create secondary icon texture (for twisting - 2 seals active)
	icon_frame.seal_icon_2 = icon_frame:CreateTexture(nil, "ARTWORK")
	icon_frame.seal_icon_2:SetSize(size, size)
	icon_frame.seal_icon_2:SetPoint("TOPLEFT", size + 2, 0)
	icon_frame.seal_icon_2:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- Create cooldown frame for secondary icon (TBC Classic compatible)
	icon_frame.seal_cooldown_2 = CreateFrame("Cooldown", nil, icon_frame, "CooldownFrameTemplate")
	icon_frame.seal_cooldown_2:SetAllPoints(icon_frame.seal_icon_2)  -- Match icon exactly
	icon_frame.seal_cooldown_2:SetReverse(true)  -- Reversed: swipe fills up as seal duration counts down
	icon_frame.seal_cooldown_2:SetHideCountdownNumbers(true)  -- Hide built-in timer text

	-- Create timer text for secondary icon (above cooldown layer)
	-- Must use separate frame with higher frame level to render above cooldown swipe
	icon_frame.seal_timer_frame_2 = CreateFrame("Frame", nil, icon_frame)
	icon_frame.seal_timer_frame_2:SetAllPoints(icon_frame.seal_icon_2)
	icon_frame.seal_timer_frame_2:SetFrameLevel(icon_frame.seal_cooldown_2:GetFrameLevel() + 1)
	icon_frame.seal_timer_text_2 = icon_frame.seal_timer_frame_2:CreateFontString(nil, "OVERLAY")
	icon_frame.seal_timer_text_2:SetPoint("CENTER", 0, 0)
	icon_frame.seal_timer_text_2:SetShadowColor(0.0, 0.0, 0.0, 1.0)
	icon_frame.seal_timer_text_2:SetShadowOffset(2, -2)
	icon_frame.seal_timer_text_2:SetJustifyV("MIDDLE")
	icon_frame.seal_timer_text_2:SetJustifyH("CENTER")

	-- Initially hidden
	icon_frame.seal_icon:Hide()
	icon_frame.seal_icon_2:Hide()

	-- Initialize timer text properties
	st.bar.set_seal_timer_text_properties()

	-- Set initial position (attached or detached based on settings)
	st.bar.set_icon_position()

	if st.debug then print('Successfully initialised seal icon.') end
end

st.bar.get_seal_texture = function(seal_label)
	-- Maps seal label to spell ID and gets texture
	local spell_id = st.data.seal_texture_ids[seal_label]
	if not spell_id then return nil end

	local texture = GetSpellTexture(spell_id)
	return texture
end

st.bar.update_seal_icons = function()
	local db = ST.db.profile

	-- Design mode draws its own sample icons
	if st.bar.previewing() then
		st.bar.render_icon_preview()
		return
	end

	-- Check if icons are enabled and frame exists
	if not db.icon_enabled or not st.bar.icon_frame then
		if st.bar.icon_frame then
			st.bar.icon_frame.seal_icon:Hide()
			st.bar.icon_frame.seal_icon_2:Hide()
			st.bar.icon_frame.seal_cooldown_1:SetCooldown(0, 0)
			st.bar.icon_frame.seal_cooldown_2:SetCooldown(0, 0)
			st.bar.icon_frame.seal_timer_text_1:Hide()
			st.bar.icon_frame.seal_timer_text_2:Hide()
			-- Reset cooldown flags so overlay restarts when re-enabled
			st.player.seal_1_cooldown_set = false
			st.player.seal_2_cooldown_set = false
		end
		return
	end

	-- Check if bar is visible
	if not st.bar.should_show_bar() then
		st.bar.icon_frame.seal_icon:Hide()
		st.bar.icon_frame.seal_icon_2:Hide()
		st.bar.icon_frame.seal_cooldown_1:Hide()
		st.bar.icon_frame.seal_cooldown_2:Hide()
		st.bar.icon_frame.seal_timer_text_1:Hide()
		st.bar.icon_frame.seal_timer_text_2:Hide()
		return
	end

	-- Get number of active seals
	local n_seals = st.player.n_active_seals

	-- Reposition icons for centering if enabled (only when detached)
	local size = st.bar.effective_icon_size()
	local icon_frame = st.bar.icon_frame

	if db.icon_detached and db.icon_centered then
		-- Center mode: adjust icon positions based on seal count
		if n_seals == 1 then
			-- Single icon: offset to center within the 2-icon frame width
			local center_offset = (size + 2) / 2
			icon_frame.seal_icon:ClearAllPoints()
			icon_frame.seal_icon:SetPoint("TOPLEFT", center_offset, 0)
		else
			-- 0 or 2 icons: use default left-aligned position
			icon_frame.seal_icon:ClearAllPoints()
			icon_frame.seal_icon:SetPoint("TOPLEFT", 0, 0)
		end
	else
		-- Not centered: always use default left-aligned position
		icon_frame.seal_icon:ClearAllPoints()
		icon_frame.seal_icon:SetPoint("TOPLEFT", 0, 0)
	end

	if n_seals == 0 then
		-- No seals, hide both icons
		st.bar.icon_frame.seal_icon:Hide()
		st.bar.icon_frame.seal_icon_2:Hide()
		st.bar.icon_frame.seal_cooldown_1:Hide()
		st.bar.icon_frame.seal_cooldown_2:Hide()
		st.bar.icon_frame.seal_timer_text_1:Hide()
		st.bar.icon_frame.seal_timer_text_2:Hide()

	elseif n_seals == 1 then
		-- Single seal, show primary icon only
		local seal_label = next(st.player.active_seals)
		local texture = st.bar.get_seal_texture(seal_label)

		if texture then
			st.bar.icon_frame.seal_icon:SetTexture(texture)
			st.bar.icon_frame.seal_icon:Show()

			-- Start cooldown animation for primary icon (only once per seal activation)
			local start_time = tonumber(st.player.seal_1_start_time) or 0
			local duration = tonumber(st.player.seal_1_duration) or 30
			if db.icon_enabled and db.seal_cooldown_overlay_enabled and start_time > 0 then
				local current_time = GetTime()
				local elapsed = current_time - start_time

				if elapsed < duration then
					-- Only call SetCooldown if the animation hasn't been started yet
					if not st.player.seal_1_cooldown_set then
						-- Tell cooldown frame when it started and actual duration from LibClassicDurations
						st.bar.icon_frame.seal_cooldown_1:SetCooldown(start_time, duration)
						st.player.seal_1_cooldown_set = true
					end
					-- Otherwise: animation is already running smoothly, don't interfere
				else
					-- Seal expired, clear cooldown
					st.bar.icon_frame.seal_cooldown_1:SetCooldown(0, 0)
				end
			else
				-- Cooldown disabled or icon disabled, clear it
				st.bar.icon_frame.seal_cooldown_1:SetCooldown(0, 0)
			end
		else
			st.bar.icon_frame.seal_icon:Hide()
			st.bar.icon_frame.seal_cooldown_1:Hide()
		end
		st.bar.icon_frame.seal_icon_2:Hide()
		st.bar.icon_frame.seal_cooldown_2:Hide()

	elseif n_seals == 2 then
		-- Twisting - show both icons
		-- Prioritize twist seals (command/righteousness) as primary icon
		local seal1, seal2

		if st.player.active_seals["command"] then
			seal1 = "command"
			-- Get the other seal
			for seal_label, _ in pairs(st.player.active_seals) do
				if seal_label ~= "command" then
					seal2 = seal_label
					break
				end
			end
		elseif st.player.active_seals["righteousness"] then
			seal1 = "righteousness"
			-- Get the other seal
			for seal_label, _ in pairs(st.player.active_seals) do
				if seal_label ~= "righteousness" then
					seal2 = seal_label
					break
				end
			end
		else
			-- Get any two seals
			seal1 = next(st.player.active_seals)
			seal2 = next(st.player.active_seals, seal1)
		end

		-- Show primary icon
		if seal1 then
			local texture1 = st.bar.get_seal_texture(seal1)
			if texture1 then
				st.bar.icon_frame.seal_icon:SetTexture(texture1)
				st.bar.icon_frame.seal_icon:Show()

				-- Start cooldown animation for primary icon (only once per seal activation)
				local start_time1 = tonumber(st.player.seal_1_start_time) or 0
				local duration1 = tonumber(st.player.seal_1_duration) or 30
				if db.icon_enabled and db.seal_cooldown_overlay_enabled and start_time1 > 0 then
					local current_time = GetTime()
					local elapsed = current_time - start_time1
					if elapsed < duration1 then
						-- Only call SetCooldown if the animation hasn't been started yet
						if not st.player.seal_1_cooldown_set then
							st.bar.icon_frame.seal_cooldown_1:SetCooldown(start_time1, duration1)
							st.player.seal_1_cooldown_set = true
						end
					else
						st.bar.icon_frame.seal_cooldown_1:SetCooldown(0, 0)
					end
				else
					st.bar.icon_frame.seal_cooldown_1:SetCooldown(0, 0)
				end
			else
				st.bar.icon_frame.seal_icon:Hide()
				st.bar.icon_frame.seal_cooldown_1:Hide()
			end
		end

		-- Show secondary icon
		if seal2 then
			local texture2 = st.bar.get_seal_texture(seal2)
			if texture2 then
				st.bar.icon_frame.seal_icon_2:SetTexture(texture2)
				st.bar.icon_frame.seal_icon_2:Show()

				-- Start cooldown animation for secondary icon (only once per seal activation)
				local start_time2 = tonumber(st.player.seal_2_start_time) or 0
				local duration2 = tonumber(st.player.seal_2_duration) or 30
				if db.icon_enabled and db.seal_cooldown_overlay_enabled and start_time2 > 0 then
					local current_time = GetTime()
					local elapsed = current_time - start_time2
					if elapsed < duration2 then
						-- Only call SetCooldown if the animation hasn't been started yet
						if not st.player.seal_2_cooldown_set then
							st.bar.icon_frame.seal_cooldown_2:SetCooldown(start_time2, duration2)
							st.player.seal_2_cooldown_set = true
						end
					else
						st.bar.icon_frame.seal_cooldown_2:SetCooldown(0, 0)
					end
				else
					st.bar.icon_frame.seal_cooldown_2:SetCooldown(0, 0)
				end
			else
				st.bar.icon_frame.seal_icon_2:Hide()
				st.bar.icon_frame.seal_cooldown_2:Hide()
			end
		end
	end
end

st.bar.set_icon_size = function()
	if not st.bar.icon_frame then return end

	local db = ST.db.profile
	local size = st.bar.effective_icon_size()

	-- Update frame size
	st.bar.icon_frame:SetWidth(size * 2 + 2)
	st.bar.icon_frame:SetHeight(size)

	-- Update icon textures size
	st.bar.icon_frame.seal_icon:SetSize(size, size)
	st.bar.icon_frame.seal_icon_2:SetSize(size, size)

	-- Reposition secondary icon
	st.bar.icon_frame.seal_icon_2:ClearAllPoints()
	st.bar.icon_frame.seal_icon_2:SetPoint("TOPLEFT", size + 2, 0)

	-- Update position
	st.bar.set_icon_position()
end

st.bar.set_icon_position = function()
	if not st.bar.icon_frame then return end

	local db = ST.db.profile
	local icon_frame = st.bar.icon_frame

	icon_frame:ClearAllPoints()

	if db.icon_detached then
		-- Free positioning mode - position relative to UIParent
		icon_frame:SetPoint(db.icon_point, UIParent, db.icon_rel_point, db.icon_x_offset, db.icon_y_offset)
		icon_frame:SetMovable(not db.icon_locked)
		icon_frame:EnableMouse(not db.icon_locked)
	else
		-- Attached mode - position relative to bar frame
		-- the gap counts from the bar's visible outline, not the inner bar frame
		icon_frame:SetPoint("LEFT", st.bar.frame, "RIGHT", db.icon_spacing + st.bar.visible_outline(), 0)
		icon_frame:SetMovable(false)
		icon_frame:EnableMouse(false)
	end
end

st.bar.set_seal_timer_text_properties = function()
	if not st.bar.icon_frame then return end

	local db = ST.db.profile
	local icon_frame = st.bar.icon_frame

	-- Use a reliable font path for timer numbers (NumberFontNormal is standard WoW font)
	local font_path = "Fonts\\FRIZQT__.TTF"  -- Default WoW font, always available
	local font_size = db.seal_timer_size or 16

	-- Apply font size and color to both timer texts with thick outline for visibility
	icon_frame.seal_timer_text_1:SetFont(font_path, font_size, "THICKOUTLINE")
	icon_frame.seal_timer_text_1:SetTextColor(unpack(db.seal_timer_color or {1, 1, 1, 1}))

	icon_frame.seal_timer_text_2:SetFont(font_path, font_size, "THICKOUTLINE")
	icon_frame.seal_timer_text_2:SetTextColor(unpack(db.seal_timer_color or {1, 1, 1, 1}))
end

st.bar.update_seal_timer_text = function()
	if not st.bar.icon_frame then return end
	if st.bar.previewing() then return end  -- render_icon_preview owns the text

	local db = ST.db.profile
	local icon_frame = st.bar.icon_frame

	-- Hide timer text if bar shouldn't be shown or icon feature is disabled
	if not st.bar.should_show_bar() or not db.icon_enabled then
		icon_frame.seal_timer_text_1:Hide()
		icon_frame.seal_timer_text_2:Hide()
		return
	end

	local current_time = GetTime()

	-- Update timer text for primary seal icon
	local expires1 = tonumber(st.player.seal_1_expires) or 0
	if expires1 > 0 then
		local remaining = expires1 - current_time
		if remaining > 0 and db.seal_timer_enabled then
			icon_frame.seal_timer_text_1:SetText(string.format("%d", remaining))
			icon_frame.seal_timer_text_1:Show()
		else
			icon_frame.seal_timer_text_1:Hide()
		end
	else
		icon_frame.seal_timer_text_1:Hide()
	end

	-- Update timer text for secondary seal icon
	local expires2 = tonumber(st.player.seal_2_expires) or 0
	if expires2 > 0 then
		local remaining = expires2 - current_time
		if remaining > 0 and db.seal_timer_enabled then
			icon_frame.seal_timer_text_2:SetText(string.format("%d", remaining))
			icon_frame.seal_timer_text_2:Show()
		else
			icon_frame.seal_timer_text_2:Hide()
		end
	else
		icon_frame.seal_timer_text_2:Hide()
	end
end

--=========================================================================================
-- Rotation Helper Display Functions
--=========================================================================================

st.bar.rotation_frame = nil
st.bar.rotation_icons = {}           -- Array of icon frames (up to 5)
st.bar.rotation_max_icons = 5        -- Maximum icons in rotation

-- Initialize the rotation helper UI elements
st.bar.init_rotation_helper = function()
    local db = ST.db.profile

    -- Create container frame for rotation icons
    st.bar.rotation_frame = CreateFrame("Frame", addon_name.."RotationFrame", st.bar.frame)
    local rot_frame = st.bar.rotation_frame

    -- Set frame strata to match bar
    rot_frame:SetFrameStrata(db.frame_strata)
    rot_frame:SetFrameLevel(db.draw_level + 2)

    -- Create rotation name text (e.g., "1/2", "2/3")
    rot_frame.rotation_text = rot_frame:CreateFontString(nil, "OVERLAY")
    rot_frame.rotation_text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    rot_frame.rotation_text:SetTextColor(1, 0.82, 0)  -- Gold color
    rot_frame.rotation_text:SetShadowColor(0, 0, 0, 1)
    rot_frame.rotation_text:SetShadowOffset(1, -1)

    -- Create training mode text (e.g., "CS, Twist, Twist")
    rot_frame.training_text = rot_frame:CreateFontString(nil, "OVERLAY")
    rot_frame.training_text:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    rot_frame.training_text:SetTextColor(1, 1, 1, 0.9)
    rot_frame.training_text:SetShadowColor(0, 0, 0, 1)
    rot_frame.training_text:SetShadowOffset(1, -1)

    -- Create icon frames
    for i = 1, st.bar.rotation_max_icons do
        st.bar.rotation_icons[i] = st.bar.create_rotation_icon(i)
    end

    -- Position the frame
    st.bar.position_rotation_frame()

    -- Initial hide
    rot_frame:Hide()

    if st.debug then print('Successfully initialised rotation helper.') end
end

-- Create a single rotation icon frame
st.bar.create_rotation_icon = function(index)
    local db = ST.db.profile
    local size = db.rotation_icon_size

    local icon_frame = CreateFrame("Frame", addon_name.."RotationIcon"..index, st.bar.rotation_frame)
    icon_frame:SetSize(size, size)

    -- Main icon texture
    icon_frame.texture = icon_frame:CreateTexture(nil, "ARTWORK")
    icon_frame.texture:SetAllPoints()
    icon_frame.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- For twist icons: left half texture (Command)
    icon_frame.twist_left = icon_frame:CreateTexture(nil, "ARTWORK")
    icon_frame.twist_left:SetPoint("TOPLEFT", 0, 0)
    icon_frame.twist_left:SetPoint("BOTTOMLEFT", 0, 0)
    icon_frame.twist_left:SetWidth(size / 2)
    icon_frame.twist_left:SetTexCoord(0.07, 0.5, 0.07, 0.93)
    icon_frame.twist_left:Hide()

    -- For twist icons: right half texture (Blood)
    icon_frame.twist_right = icon_frame:CreateTexture(nil, "ARTWORK")
    icon_frame.twist_right:SetPoint("TOPRIGHT", 0, 0)
    icon_frame.twist_right:SetPoint("BOTTOMRIGHT", 0, 0)
    icon_frame.twist_right:SetWidth(size / 2)
    icon_frame.twist_right:SetTexCoord(0.5, 0.93, 0.07, 0.93)
    icon_frame.twist_right:Hide()

    -- Glow effect texture (UI-ActionButton-Border style)
    icon_frame.glow = icon_frame:CreateTexture(nil, "OVERLAY")
    icon_frame.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    icon_frame.glow:SetBlendMode("ADD")
    icon_frame.glow:SetPoint("CENTER", 0, 0)
    icon_frame.glow:SetSize(size * 1.4, size * 1.4)
    icon_frame.glow:SetVertexColor(1, 1, 0, 0.8)  -- Yellow glow by default
    icon_frame.glow:Hide()

    icon_frame:Hide()

    return icon_frame
end

-- Position the rotation frame relative to the main bar
st.bar.position_rotation_frame = function()
    if not st.bar.rotation_frame then return end

    local db = ST.db.profile
    local rot_frame = st.bar.rotation_frame

    -- Clear existing points
    rot_frame:ClearAllPoints()

    -- Position above the bar, centered
    rot_frame:SetPoint("BOTTOM", st.bar.frame, "TOP", db.rotation_offset_x, db.rotation_offset_y)

    -- Size the frame to fit the icons
    local num_icons = #st.bar.rotation_icons
    local total_width = (db.rotation_icon_size * num_icons) + (db.rotation_icon_spacing * (num_icons - 1))
    local total_height = db.rotation_icon_size + 20  -- Extra space for text

    rot_frame:SetSize(total_width, total_height)

    -- Position rotation name text above icons
    rot_frame.rotation_text:ClearAllPoints()
    rot_frame.rotation_text:SetPoint("BOTTOM", rot_frame, "TOP", 0, 2)

    -- Position training text below rotation text
    rot_frame.training_text:ClearAllPoints()
    rot_frame.training_text:SetPoint("TOP", rot_frame.rotation_text, "BOTTOM", 0, -2)
end

-- Update icon sizes when settings change
st.bar.set_rotation_icon_size = function()
    if not st.bar.rotation_frame then return end

    local db = ST.db.profile
    local size = db.rotation_icon_size
    local spacing = db.rotation_icon_spacing

    for i, icon_frame in ipairs(st.bar.rotation_icons) do
        icon_frame:SetSize(size, size)

        -- Update twist texture sizes
        icon_frame.twist_left:SetWidth(size / 2)
        icon_frame.twist_right:SetWidth(size / 2)

        -- Update glow size
        icon_frame.glow:SetSize(size * 1.4, size * 1.4)

        -- Reposition icon
        icon_frame:ClearAllPoints()
        local x_offset = (i - 1) * (size + spacing)
        icon_frame:SetPoint("LEFT", st.bar.rotation_frame, "LEFT", x_offset, 0)
    end

    -- Update frame position
    st.bar.position_rotation_frame()
end

-- Set icon texture based on action type
st.bar.set_rotation_icon_texture = function(icon_frame, action)
    if not icon_frame or not action then
        icon_frame.texture:Hide()
        icon_frame.twist_left:Hide()
        icon_frame.twist_right:Hide()
        return
    end

    if action == "twist" then
        -- Twist icon: split between Command (left) and Blood (right)
        local cmd_texture = GetSpellTexture(20375)   -- Seal of Command
        local blood_texture = GetSpellTexture(31892) -- Seal of Blood

        if cmd_texture and blood_texture then
            icon_frame.twist_left:SetTexture(cmd_texture)
            icon_frame.twist_right:SetTexture(blood_texture)
            icon_frame.twist_left:Show()
            icon_frame.twist_right:Show()
            icon_frame.texture:Hide()
        end
    else
        -- Regular single-spell icon
        local spell_id = nil

        if action == "cs" or action == "cs_late" then
            spell_id = 35395  -- Crusader Strike
        elseif action == "blood_auto" then
            spell_id = 31892  -- Seal of Blood
        elseif action == "cmd_auto" then
            spell_id = 20375  -- Seal of Command
        end

        if spell_id then
            local texture = GetSpellTexture(spell_id)
            if texture then
                icon_frame.texture:SetTexture(texture)
                icon_frame.texture:Show()
            end
        end

        icon_frame.twist_left:Hide()
        icon_frame.twist_right:Hide()
    end
end

-- Update the rotation display based on current state
st.bar.update_rotation_display = function()
    if not st.bar.rotation_frame then return end

    local db = ST.db.profile
    local rot_frame = st.bar.rotation_frame

    -- Check if should show
    if not st.rotation or not st.rotation.should_show or not st.rotation.should_show() then
        rot_frame:Hide()
        return
    end

    rot_frame:Show()

    -- Get current rotation data
    local rotation = st.rotation.current_rotation
    local sequence = st.rotation.sequence or {}
    local current_step = st.rotation.current_step or 1
    local cs_ready = st.rotation.is_cs_ready and st.rotation.is_cs_ready() or false

    -- Update rotation name text
    if db.rotation_text_enabled then
        local rot_name = st.rotation.get_rotation_text and st.rotation.get_rotation_text() or ""
        rot_frame.rotation_text:SetText(rot_name)
        rot_frame.rotation_text:Show()
    else
        rot_frame.rotation_text:Hide()
    end

    -- Update training mode text
    if db.rotation_training_text then
        local training = st.rotation.get_rotation_description and st.rotation.get_rotation_description() or ""
        rot_frame.training_text:SetText(training)
        rot_frame.training_text:Show()
    else
        rot_frame.training_text:Hide()
    end

    -- Calculate positioning
    local size = db.rotation_icon_size
    local spacing = db.rotation_icon_spacing
    local num_to_show = db.rotation_show_all_steps and #sequence or math.min(2, #sequence)

    -- Calculate total width and center offset
    local total_width = (size * num_to_show) + (spacing * math.max(0, num_to_show - 1))
    local start_x = -total_width / 2 + size / 2

    -- Update icons
    for i, icon_frame in ipairs(st.bar.rotation_icons) do
        local step_index
        if db.rotation_show_all_steps then
            step_index = i
        else
            -- Show current and next action only
            step_index = current_step + (i - 1)
            if step_index > #sequence then
                step_index = step_index - #sequence
            end
        end

        if step_index <= #sequence and i <= num_to_show then
            local action = sequence[step_index]

            -- Position icon
            icon_frame:ClearAllPoints()
            local x_pos = start_x + (i - 1) * (size + spacing)
            icon_frame:SetPoint("CENTER", rot_frame, "CENTER", x_pos, 0)

            -- Set texture
            st.bar.set_rotation_icon_texture(icon_frame, action)

            -- Handle glow/highlight for current step
            local is_current = (db.rotation_show_all_steps and step_index == current_step) or
                              (not db.rotation_show_all_steps and i == 1)

            if is_current and db.rotation_glow_enabled then
                icon_frame.glow:Show()

                -- Extra glow for CS when ready
                if (action == "cs" or action == "cs_late") and cs_ready and db.rotation_cs_glow_enabled then
                    icon_frame.glow:SetVertexColor(0, 1, 0, 0.9)  -- Green when CS ready
                else
                    icon_frame.glow:SetVertexColor(1, 1, 0, 0.8)  -- Yellow for current
                end
            else
                icon_frame.glow:Hide()
            end

            -- Dim non-current icons slightly
            if is_current then
                icon_frame.texture:SetVertexColor(1, 1, 1, 1)
                icon_frame.twist_left:SetVertexColor(1, 1, 1, 1)
                icon_frame.twist_right:SetVertexColor(1, 1, 1, 1)
            else
                icon_frame.texture:SetVertexColor(0.7, 0.7, 0.7, 1)
                icon_frame.twist_left:SetVertexColor(0.7, 0.7, 0.7, 1)
                icon_frame.twist_right:SetVertexColor(0.7, 0.7, 0.7, 1)
            end

            icon_frame:Show()
        else
            icon_frame:Hide()
        end
    end
end

-- Called from the main OnUpdate to refresh rotation display
st.bar.update_rotation_on_update = function()
    -- Only update rotation display if it exists and is enabled
    if not st.bar.rotation_frame then return end

    local db = ST.db.profile
    if not db.rotation_helper_enabled then
        st.bar.rotation_frame:Hide()
        return
    end

    -- Update rotation module state
    if st.rotation and st.rotation.on_update then
        st.rotation.on_update(0.016)  -- Approximate elapsed time
    end

    -- Update display
    st.bar.update_rotation_display()
end

--=========================================================================================
-- OnUpdate widget handlers and functions
--=========================================================================================

st.bar.update_visuals_on_update = function()
    -- This function will be called once every frame after the event-based code has run,
    -- but before the frame is drawn.
    -- Func is called by the player frame OnUpdate (maybe we should change this).
    -- As such it should be kept as minimal as possible to avoid wasting resources.

    st.bar.show_or_hide_bar()
    if not st.bar.should_show_bar() then return end

    -- Design mode: a looping sample sweep instead of the live swing (never in combat)
    if st.bar.previewing() and not st.core.in_combat then
        st.bar.render_preview()
        return
    end

    -- Update seal timer text each frame
    st.bar.update_seal_timer_text()

    local frame = st.bar.frame
    local speed = st.player.current_weapon_speed
    local timer = st.player.swing_timer
	-- Calculate progress: 0.0 (full swing timer) to 1.0 (swing complete)
	-- This makes the bar fill left-to-right as swing timer counts down
	local progress = math.max(0, math.min(1, 1 - (timer / speed)))
    local db = ST.db.profile

    -- Update the main bar's width
    local timer_width = db.bar_width * progress
    frame.bar:SetWidth(timer_width)
	frame.bar:SetTexCoord(0, progress, 0, 1)
	
    -- Update the deadzone's width
    frame.deadzone:SetWidth(st.bar.get_deadzone_width())

	-- Set texts
	st.bar.update_texts(speed, timer)

    -- If SoC/SoR, bar colour is time/context sensitive. Deal with that here.
    if st.player.is_twist_seal_active() then
        if st.player.n_active_seals == 1 then
            local twist_window_time = st.bar.get_twist_window_time_before_swing()
            local gcd1_time = st.bar.get_gcd_time_before_swing()
            -- Determine which twist seal color to use
            local twist_seal_color = db.bar_color_command
            if st.player.match_seal('righteousness') then
                twist_seal_color = db.bar_color_righteousness
            end

            -- Play twist window sound notification
            -- Add 200ms offset to account for audio file lead-in delay
            local sound_trigger_time = twist_window_time + 0.20
            if db.twist_sound_enabled and not st.player.twist_sound_played and not (db.ret_only and not st.utils.is_ret_spec) then
                if st.player.swing_timer <= sound_trigger_time and st.player.swing_timer > 0 then
                    local sound_choice = db.twist_sound_choice or "pop"
                    local sound_path = twist_sounds[sound_choice]
                    if sound_path then
                        PlaySoundFile(sound_path, db.sound_channel or "Master")
                    end
                    st.player.twist_sound_played = true
                end
            end

            if st.player.twist_impossible then
                st.bar.frame.bar:SetVertexColor(unpack(db.bar_color_cant_twist))
            elseif st.player.swing_timer < twist_window_time then
                st.bar.frame.bar:SetVertexColor(unpack(twist_seal_color))
            else
                if st.player.swing_timer > gcd1_time then
                    st.bar.frame.bar:SetVertexColor(unpack(twist_seal_color))
                else
                    st.bar.frame.bar:SetVertexColor(unpack(db.bar_color_warning))
                end
            end
        end
    end

    st.bar.tick_success_glow()
end

-- Twist success glow timer: stops the LibCustomGlow effect after its duration. Runs
-- from the per-frame update in live play and from the design-mode preview.
st.bar.tick_success_glow = function()
    if not st.bar.twist_success_glow_active then return end
    local db = ST.db.profile
    st.bar.twist_success_glow_timer = st.bar.twist_success_glow_timer - 0.016  -- approx elapsed (~60fps)
    if st.bar.twist_success_glow_timer <= 0 then
        -- Stop the LibCustomGlow effect
        local glowType = db.twist_success_glow_type or "Pixel"
        if glowType == "Pixel" then
            LCG.PixelGlow_Stop(st.bar.frame, "TwistSuccess")
        elseif glowType == "AutoCast" then
            LCG.AutoCastGlow_Stop(st.bar.frame, "TwistSuccess")
        elseif glowType == "Button" then
            LCG.ButtonGlow_Stop(st.bar.frame)
        elseif glowType == "HolyNova" or glowType == "SealSpiral" then
            -- Custom animations handle their own stop logic
            st.bar.stop_custom_animations()
        end
        st.bar.twist_success_glow_active = false
    end
end

--=========================================================================================
-- Funcs to trigger updates to the bar's conditions on certain events.
--=========================================================================================
st.bar.update_bar_on_combat = function()
    -- Function called to update bar when entering/leaving combat.
    st.bar.show_or_hide_bar()
end

st.bar.update_bar_on_timer_full = function()
    -- Function called when the bar fills up to change any bar visuals
    st.bar.set_gcd_bar_width()
    st.bar.frame.twist_line:Hide()
    st.bar.frame.gcd1_line:Hide()
end


st.bar.update_bar_on_swing_reset = function()
    -- Function called when the swing timer resets to change any bar visuals
    st.bar.show_or_hide_ticks()
    -- Recalculate the gcd bar width
    st.bar.set_gcd_bar_width()
    -- calc any judgements
    st.bar.calc_judgement()
end

st.bar.update_bar_on_new_gcd = function()
    st.bar.set_gcd_bar_width()
end

st.bar.update_bar_on_speed_change = function()
    -- A function to be run once upon the player's speed updating.
    -- This will recalculate all necessary frame element updates here
    -- to keep them out the main onupdate function
    -- print('Recalculating bar visuals on speed change...')
    st.bar.set_marker_offsets()
    st.bar.set_gcd_bar_width()
    st.bar.show_or_hide_ticks()
end

st.bar.set_marker_offsets = function()
    st.bar.set_twist_tick_offset()
    st.bar.set_gcd_marker_offsets()
end

st.bar.update_bar_on_aura_change = function()
    -- A function to be run once upon the player's auras changing.
    -- Aura changes determine if the twist line should be drawn or not.
    st.bar.set_bar_color()

    -- if the spell haste changes we need to update the tick offsets
    st.bar.set_marker_offsets()

    -- determine if we should now show or hide the ticks
    st.bar.show_or_hide_ticks()

    -- determine if the bar should be auto hidden
    st.bar.show_or_hide_bar()

    -- check for judgements if necessary
    st.bar.calc_judgement()

    -- update seal icons
    st.bar.update_seal_icons()
end

st.bar.update_bar_on_parry = function()
    -- called whenever the player parries an attack
    st.bar.set_gcd_bar_width()  
    st.bar.calc_judgement()
end


--=========================================================================================
-- Funcs to recalculate/show/hide etc bar elements
--=========================================================================================
st.bar.get_deadzone_width = function()
    local db = ST.db.profile
    local frac = (st.player.lag_world_ms / 1000) / st.player.current_weapon_speed
    return frac * db.bar_width * db.deadzone_scale_factor
end

st.bar.has_judgement_seal = function()
    -- returns true if the player has a seal they typically want to judge
    if st.player.match_seal('blood') then
        return true
    elseif st.player.match_seal('righteousness') then
        return true
    elseif st.player.match_seal('vengeance') then
        return true
    elseif st.player.match_seal('justice') then
        return true
    end
    return false
end

st.bar.calc_judgement = function()
    -- Function to check if we need to draw the judgement line
    -- and then to calulate its position. Called when the speed or timer changes.
    local db = ST.db.profile

    if not st.player.judgement_being_tracked or not db.judgement_marker_enabled then
        return
    end

    local line = st.bar.frame.judgement_line
    local remaining = st.player.judgement_cd_remaining
    local timer = st.player.swing_timer
    local elapsed = st.player.current_weapon_speed - timer


    -- local time_remaining_on_swing = st.player.current_weapon_speed - st.player.swing_timer
    -- print(time_remaining_on_swing)
    -- print('judgement time remaining  = ' .. tostring(remaining))
    -- print('swing timer remaining     = ' .. tostring(timer))
    
    if remaining < timer then
        -- print('judgement off cd this swing')
        if st.bar.has_judgement_seal() then
            local offset = ((remaining + elapsed) / st.player.current_weapon_speed) * db.bar_width
            -- print(offset)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", offset, 0)
            line:SetHeight(db.bar_height)
            line:Show()
        else
            line:Hide()
        end
    else
        line:Hide()
    end

end

st.bar.show_or_hide_bar = function()
    -- Function called to show or hide the bar
    local frame = st.bar.frame
    if st.bar.should_show_bar() then
        frame:Show()
    else
        frame:Hide()
    end
end

st.bar.should_show_bar = function()
    -- Logic for if the bar should be visible
    local db = ST.db.profile

    -- Design mode: everything is shown so it can be arranged
    if st.bar.previewing() then return true end

    -- Simple toggle: if bar disabled, hide
    if not db.bar_enabled then return false end

    -- Ret-only mode: hide if not ret spec
    if db.ret_only and not st.utils.is_ret_spec then return false end

    -- Check visibility mode
    if db.visibility_key == "always" then
        return true
    elseif db.visibility_key == "in_combat" then
        return st.core.in_combat
    elseif db.visibility_key == "active_seal" then
        return st.player.n_active_seals > 0
    elseif db.visibility_key == "in_combat_or_active_seal" then
        return st.core.in_combat or st.player.n_active_seals > 0
    end

    return false
end

st.bar.hide_gcd_bar = function()
    st.bar.gcd_bar_width = 0
    st.bar.frame.gcd_bar:SetWidth(0)
    st.bar.frame.gcd_bar:Hide()
end

st.bar.set_gcd_bar_width = function()

    if not st.player.gcd_lockout then
        st.bar.hide_gcd_bar()
        return
    end


    local attack_speed = st.player.current_weapon_speed
    -- local swing_timer = st.player.swing_timer
    -- print(attack_speed)
    -- print(swing_timer)
    -- print(st.player.active_gcd_remaining)
    local time_since_bar_start = st.player.current_weapon_speed - st.player.swing_timer
    local db = ST.db.profile


    local time_gcd_ends = time_since_bar_start + st.player.active_gcd_remaining
    -- print("Time relative to bar the GCD ends = " .. tostring(time_gcd_ends))

    if time_gcd_ends > attack_speed then
        time_gcd_ends = attack_speed
    end
    -- print("Modified time relative to bar the GCD ends = " .. tostring(time_gcd_ends))


    -- local gcd_bar_width = settings.width - (time_gcd_ends / attack_speed)

    local gcd_bar_width = (time_gcd_ends / attack_speed) * db.bar_width
    -- print('offset says ' .. tostring(offset))
        
    -- print(type(gcd_bar_width))
    -- print('gcd bar width says : ' .. tostring(gcd_bar_width))
    -- print('gcd bar width is   : ' .. tostring(st.bar.frame.gcd_bar:GetWidth()))
    st.bar.gcd_bar_width = gcd_bar_width
    st.bar.frame.gcd_bar:SetWidth(gcd_bar_width)
    -- print('gcd bar width after is   : ' .. tostring(st.bar.frame.gcd_bar:GetWidth()))

    st.bar.frame.gcd_bar:Show()
end

-- Func to figure out if the ticks should be
st.bar.show_or_hide_ticks = function()
    local frame = st.bar.frame

    -- always hide ticks at full swing timer
    if st.player.swing_timer == 0 then
        st.bar.frame.twist_line:Hide()
        st.bar.frame.gcd1_line:Hide()
        return
    end

    -- Twist line
    if st.bar.should_draw_twist_window() then
        frame.twist_line:Show()
    else
        frame.twist_line:Hide()
    end
    -- GCD line
    if st.bar.should_draw_gcd1_window() then
        frame.gcd1_line:Show()
    else
        frame.gcd1_line:Hide()
    end
end

-- Determine wether or not to draw the twist line
-- Hide if we are not in SoC or the swing bar is full
st.bar.should_draw_twist_window = function()
    if st.player.is_twist_seal_active() then
        return true
    end
    return false
end

-- determine wether or not to draw the gcd line
st.bar.should_draw_gcd1_window = function()
    local db = ST.db.profile
    if not db.gcd1_enabled then
        return false
    elseif math.abs(st.bar.gcd1_tick_offset) > db.bar_width then
        return false
    end
    return true
end

st.bar.get_twist_window_time_before_swing = function()
    local db = ST.db.profile
    local twist_s = 400 / 1000.0 -- 400ms standard
    local padding = 0.0
    if db.twist_padding_mode == "Dynamic" then
        padding = st.player.lag_calibrated_ms * 0.7 * 0.001 -- convert to seconds
    elseif db.twist_padding_mode == "Fixed" then
        padding = db.twist_window_padding_ms / 1000.0
    end
    return twist_s + padding
end

st.bar.set_twist_tick_offset = function()
-- Set the offset position of the twist window
    local db = ST.db.profile
    -- local twist_s = db.twist_window_ms / 1000.0
    local twist_s = st.bar.get_twist_window_time_before_swing()
    local bar_fraction = (twist_s / st.player.current_weapon_speed)
    -- Calculate how far from the left edge (twist window is near end of bar)
    local offset = (1 - bar_fraction) * db.bar_width
    -- print('twist tick time = ' .. time_value)
    st.bar.twist_tick_offset = offset
    st.bar.frame.twist_line:ClearAllPoints()
    st.bar.frame.twist_line:SetPoint("TOPLEFT", offset, 0)
    st.bar.frame.twist_line:SetHeight(db.bar_height)
end

st.bar.get_gcd_time_before_swing = function()
    -- Returns the time before the swing that the GCD marker should be,
    -- including padding, in seconds.
    local db = ST.db.profile
    local gcd_duration = st.player.spell_gcd_duration

    -- Determine the gcd padding mode.
    local padding = 0.0
    if db.gcd_padding_mode == "Dynamic" then
        padding = st.player.lag_calibrated_ms * 0.65 * 0.001 -- convert to seconds
    elseif db.gcd_padding_mode == "Fixed" then
        padding = db.gcd_static_padding_ms / 1000.0
    end
    return gcd_duration + padding
end

st.bar.set_gcd_marker_offsets = function()
    local db = ST.db.profile
    -- Get the time before the swing the GCD marker should be
    local gcd_before = st.bar.get_gcd_time_before_swing()

    -- GCD marker - Calculate position from left edge
    local bar_fraction = gcd_before / st.player.current_weapon_speed
    local offset = (1 - bar_fraction) * db.bar_width
    st.bar.gcd1_tick_offset = offset
    st.bar.frame.gcd1_line:ClearAllPoints()
    st.bar.frame.gcd1_line:SetPoint("TOPLEFT", offset, 0)
    st.bar.frame.gcd1_line:SetHeight(db.bar_height)
end

-- function to determine if any seal we are happy to run with is up
-- i.e blood justice or vengeance
st.bar.is_running_seal_active = function()
    if st.player.active_seals["blood"] ~= nil then
        return true
    elseif st.player.active_seals["justice"] ~= nil then
        return true
    elseif st.player.active_seals["vengeance"] ~= nil then
        return true
    end
    return false
end

-- This function sets the bar colour for all cases outside of command, which has
-- a time sensitive component and must be handled on-update.
st.bar.set_bar_color = function()

    local db = ST.db.profile

    -- if no seal return default color
    if st.player.n_active_seals == 0 then
        if st.debug then print('Bar color: Default (no seals active)') end
        st.bar.frame.bar:SetVertexColor(unpack(db.bar_color_default))
    -- if we're currently twisting return twist color
    elseif st.player.n_active_seals == 2 and db.bar_twist_color_enabled then
        if st.debug then print('Bar color: Twisting (2 seals active)') end
        st.bar.frame.bar:SetVertexColor(unpack(db.bar_color_twisting))

    -- if no special condition, match a seal color.
    elseif st.player.match_seal('command') then
        if st.debug then print('Bar color: Seal of Command') end
        st.bar.frame.bar:SetVertexColor(unpack(db.bar_color_command))
    elseif st.player.match_seal('righteousness') then
        if st.debug then print('Bar color: Seal of Righteousness') end
        st.bar.frame.bar:SetVertexColor(unpack(db.bar_color_righteousness))
    elseif st.player.match_seal('blood') then
        if st.debug then print('Bar color: Seal of Blood') end
        st.bar.frame.bar:SetVertexColor(unpack(db.bar_color_blood))
    elseif st.player.match_seal('vengeance') then
        if st.debug then print('Bar color: Seal of Vengeance') end
        st.bar.frame.bar:SetVertexColor(unpack(db.bar_color_vengeance))
    elseif st.player.match_seal('wisdom') then
        if st.debug then print('Bar color: Seal of Wisdom') end
        st.bar.frame.bar:SetVertexColor(unpack(db.bar_color_wisdom))
    elseif st.player.match_seal('light') then
        if st.debug then print('Bar color: Seal of Light') end
        st.bar.frame.bar:SetVertexColor(unpack(db.bar_color_light))
    elseif st.player.match_seal('justice') then
        if st.debug then print('Bar color: Seal of Justice') end
        st.bar.frame.bar:SetVertexColor(unpack(db.bar_color_justice))
    elseif st.player.match_seal('crusader') then
        if st.debug then print('Bar color: Seal of the Crusader') end
        st.bar.frame.bar:SetVertexColor(unpack(db.bar_color_crusader))
    else
        -- if we get to the end return the default color
        if st.debug then print('Bar color: Default (fallback)') end
        st.bar.frame.bar:SetVertexColor(unpack(db.bar_color_default))
    end
end

--=========================================================================================
-- Design mode preview (see editmode.lua). While design mode is on every element is
-- force-shown with sample content so it can be arranged; disabled elements render as
-- 35% ghosts. Nothing here touches the profile - end_preview() rebuilds the real state.
--=========================================================================================
local PREVIEW_GHOST_ALPHA = 0.35
local SOC_TEXTURE_ID, SOB_TEXTURE_ID = 20375, 31892

st.bar.previewing = function()
    return st.editmode ~= nil and st.editmode.active ~= nil and st.editmode.active()
end

-- True while design mode runs the twist simulation (see editmode.lua).
st.bar.simulating = function()
    return st.editmode ~= nil and st.editmode.simulating ~= nil and st.editmode.simulating()
end

-- The simulation's current phase, read by the icon preview and the next action guide:
-- "command" (Command swing, before the twist window), "twisting" (both seals up
-- inside the window) or "blood" (the Blood swing that follows). nil = no simulation.
st.bar.preview_phase = nil
local preview_effects_cycle, preview_sound_cycle

-- Bar sample. Static: a looping Command sweep. Simulation: the 1/2 rotation - a
-- Command swing that twists to Blood in its last 400 ms (firing the twist sounds, the
-- glow and the success text exactly as live play would), then a Blood auto swing.
-- Both show the GCD underlay, deadzone, twist / GCD markers, a judgement marker and
-- live-formatted labels.
st.bar.render_preview = function()
    local db = ST.db.profile
    local frame = st.bar.frame
    if not frame then return end
    local speed = st.player.current_weapon_speed or 0
    if speed <= 0 then speed = 3.3 end
    local now = GetTime()
    local progress, phase
    if st.bar.simulating() then
        local cycle_len = speed * 2
        local cycle = math.floor(now / cycle_len)
        local t = now - cycle * cycle_len
        local swing_t = t < speed and t or (t - speed)
        progress = math.min(1, swing_t / speed)
        if t < speed then
            local window = st.bar.get_twist_window_time_before_swing()
            local remaining = speed - swing_t
            phase = remaining <= window and "twisting" or "command"
            -- twist window sound, with the same 200 ms audio lead-in as live play
            if db.twist_sound_enabled and remaining <= window + 0.20 and preview_sound_cycle ~= cycle
                and not (db.ret_only and not st.utils.is_ret_spec) then
                preview_sound_cycle = cycle
                local sound_path = twist_sounds[db.twist_sound_choice or "pop"]
                if sound_path then PlaySoundFile(sound_path, db.sound_channel or "Master") end
            end
        else
            phase = "blood"
            -- the Command swing just landed with both seals up: a successful twist
            if preview_effects_cycle ~= cycle then
                preview_effects_cycle = cycle
                st.bar.on_twist_attempt()
                st.bar.on_successful_twist()
            end
        end
    else
        local t = now % (speed + 0.6)         -- short rest at "full" between sweeps
        progress = math.min(1, t / speed)
        phase = nil
    end
    st.bar.preview_phase = phase
    local width = db.bar_width

    frame:SetAlpha(db.bar_enabled and 1 or PREVIEW_GHOST_ALPHA)
    frame.bar:SetWidth(math.max(0.5, width * progress))
    frame.bar:SetTexCoord(0, math.max(0.001, progress), 0, 1)
    local color = db.bar_color_command
    if phase == "twisting" and db.bar_twist_color_enabled then
        color = db.bar_color_twisting
    elseif phase == "blood" then
        color = db.bar_color_blood
    end
    frame.bar:SetVertexColor(unpack(color))

    local gcd = st.player.spell_gcd_duration or 1.5
    if gcd <= 0 then gcd = 1.5 end
    frame.gcd_bar:SetWidth(width * math.min(1, gcd / speed))
    frame.gcd_bar:Show()

    local dz = 0
    if st.player.lag_world_ms and st.player.lag_world_ms > 0 then
        dz = ((st.player.lag_world_ms / 1000) / speed) * width * (db.deadzone_scale_factor or 1)
    end
    if dz < 2 then dz = width * 0.04 end
    frame.deadzone:SetWidth(dz)
    if db.enable_deadzone then frame.deadzone:Show() else frame.deadzone:Hide() end

    frame.twist_line:Show()
    if db.gcd1_enabled then frame.gcd1_line:Show() else frame.gcd1_line:Hide() end
    if db.judgement_marker_enabled then
        frame.judgement_line:ClearAllPoints()
        frame.judgement_line:SetPoint("TOPLEFT", width * 0.55, 0)
        frame.judgement_line:SetHeight(db.bar_height)
        frame.judgement_line:Show()
    else
        frame.judgement_line:Hide()
    end

    st.bar.update_texts(speed, speed * (1 - progress))
    st.bar.tick_success_glow()
    st.bar.render_icon_preview()
end

-- Seal icon sample. Static: Command + Blood side by side (the twist state, so the full
-- width of the element is visible). Simulation: whichever seals the phase has up,
-- centred the way live play centres them. Countdown text and swipes if enabled.
st.bar.render_icon_preview = function()
    local db = ST.db.profile
    local f = st.bar.icon_frame
    if not f then return end
    f:SetAlpha(db.icon_enabled and 1 or PREVIEW_GHOST_ALPHA)
    local phase = st.bar.preview_phase
    local first = (phase == "blood") and SOB_TEXTURE_ID or SOC_TEXTURE_ID
    local two = (phase == nil) or (phase == "twisting")
    local size = st.bar.effective_icon_size()
    f.seal_icon:ClearAllPoints()
    if not two and db.icon_detached and db.icon_centered then
        f.seal_icon:SetPoint("TOPLEFT", (size + 2) / 2, 0)
    else
        f.seal_icon:SetPoint("TOPLEFT", 0, 0)
    end
    f.seal_icon:SetTexture(GetSpellTexture(first))
    f.seal_icon:Show()
    f.seal_icon_2:SetTexture(GetSpellTexture(SOB_TEXTURE_ID))
    if two then f.seal_icon_2:Show() else f.seal_icon_2:Hide() end
    if db.seal_cooldown_overlay_enabled then
        if not f.preview_cooldown_set then
            f.preview_cooldown_set = true
            f.seal_cooldown_1:SetCooldown(GetTime() - 12, 30)
            f.seal_cooldown_2:SetCooldown(GetTime() - 6, 30)
        end
        f.seal_cooldown_1:Show()
        f.seal_cooldown_2:Show()
    else
        if f.preview_cooldown_set then
            f.preview_cooldown_set = false
            f.seal_cooldown_1:SetCooldown(0, 0)
            f.seal_cooldown_2:SetCooldown(0, 0)
        end
        f.seal_cooldown_1:Hide()
        f.seal_cooldown_2:Hide()
    end
    if db.seal_timer_enabled then
        f.seal_timer_text_1:SetText("18")
        f.seal_timer_text_2:SetText("24")
        f.seal_timer_text_1:Show()
        if two then f.seal_timer_text_2:Show() else f.seal_timer_text_2:Hide() end
    else
        f.seal_timer_text_1:Hide()
        f.seal_timer_text_2:Hide()
    end
end

-- Called when design mode starts: make sure marker offsets exist for the sample.
st.bar.begin_preview = function()
    if not st.bar.frame then return end
    if (st.player.current_weapon_speed or 0) > 0 then
        st.bar.set_marker_offsets()
    end
    st.bar.show_or_hide_bar()
    st.bar.set_success_text_position()
end

-- Called when design mode ends: rebuild every visual from the real player state.
st.bar.end_preview = function()
    local frame = st.bar.frame
    if not frame then return end
    local db = ST.db.profile
    st.bar.preview_phase = nil
    preview_effects_cycle, preview_sound_cycle = nil, nil
    -- a glow or success text mid-flight from the simulation stops now
    if st.bar.twist_success_glow_active then
        st.bar.twist_success_glow_timer = 0
        st.bar.tick_success_glow()
    end
    st.bar.success_text_visible = false
    frame:SetAlpha(1)
    frame.judgement_line:Hide()
    if not db.enable_deadzone then frame.deadzone:Hide() end
    if (st.player.current_weapon_speed or 0) > 0 then
        st.bar.set_marker_offsets()
    end
    st.bar.set_bar_color()
    st.bar.set_gcd_bar_width()
    st.bar.show_or_hide_ticks()
    st.bar.show_or_hide_bar()

    local f = st.bar.icon_frame
    if f then
        f:SetAlpha(1)
        f.preview_cooldown_set = false
        f.seal_cooldown_1:SetCooldown(0, 0)
        f.seal_cooldown_2:SetCooldown(0, 0)
        f.seal_icon:Hide()
        f.seal_icon_2:Hide()
        f.seal_timer_text_1:Hide()
        f.seal_timer_text_2:Hide()
        st.player.seal_1_cooldown_set = false
        st.player.seal_2_cooldown_set = false
        st.bar.update_seal_icons()
        st.bar.update_seal_timer_text()
    end
    st.bar.set_success_text_position()
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed bar.lua module correctly') end
