AddCSLuaFile()

print("Helios Door Utilities Loading...")

sound.Add({
	name = "Witcher.Teleport",
	channel = CHAN_STREAM,
	volume = 1,
	level = 75,
	pitch = {100, 110},
	sound = "portal/portal_teleport.wav"
})

sound.Add({
	name = "Witcher.PortalOpen",
	channel = CHAN_STREAM,
	volume = 1,
	level = 80,
	pitch = {95, 105},
	sound = "portal/portal_open.wav"
})

sound.Add({
	name = "Witcher.PortalClose",
	channel = CHAN_STREAM,
	volume = 1,
	level = 80,
	pitch = {95, 105},
	sound = "portal/portal_dissipate.wav"
})

local clamp = math.Clamp
local abs = math.abs
local min = math.min
local max = math.max

function HSLToColor(H, S, L)
	H = clamp(H, 0, 360)
	S = clamp(S, 0, 1)
	L = clamp(L, 0, 1)
	local C = (1 - abs(2 * L - 1)) * S
	local X = C * (1 - abs((H / 60) % 2 - 1))
	local m = L - C / 2
	local R1, G1, B1 = 0, 0, 0

	if H < 60 or H >= 360 then
		R1, G1, B1 = C, X, 0
	elseif H < 120 then
		R1, G1, B1 = X, C, 0
	elseif H < 180 then
		R1, G1, B1 = 0, C, X
	elseif H < 240 then
		R1, G1, B1 = 0, X, C
	elseif H < 300 then
		R1, G1, B1 = X, 0, C
	else
		R1, G1, B1 = C, 0, X -- H < 360
	end

	return Color((R1 + m) * 255, (G1 + m) * 255, (B1 + m) * 255)
end

function ColorToHSL(R, G, B)
	if type(R) == "table" then
		R, G, B = clamp(R.r, 0, 255) / 255, clamp(R.g, 0, 255) / 255, clamp(R.b, 0, 255) / 255
	else
		R, G, B = R / 255, G / 255, B / 255
	end

	local max, min = max(R, G, B), min(R, G, B)
	local del = max - min
	-- Hue
	local H = 0

	if del <= 0 then
		H = 0
	elseif max == R then
		H = 60 * (((G - B) / del) % 6)
	elseif max == G then
		H = 60 * (((B - R) / del + 2) % 6)
	else
		H = 60 * (((R - G) / del + 4) % 6)
	end

	-- Lightness
	local L = (max + min) / 2
	-- Saturation
	local S = 0

	if del ~= 0 then
		S = del / (1 - abs(2 * L - 1))
	end

	return H, S, L
end

function DistanceToPlane(object_pos, plane_pos, plane_forward)
	local vec = object_pos - plane_pos
	plane_forward:Normalize()

	return plane_forward:Dot(vec)
end

function math.VectorAngles(forward, up)
	local angles = Angle(0, 0, 0)
	local left = up:Cross(forward)
	left:Normalize()
	local xydist = math.sqrt(forward.x * forward.x + forward.y * forward.y)

	if (xydist > 0.001) then
		angles.y = math.deg(math.atan2(forward.y, forward.x))
		angles.p = math.deg(math.atan2(-forward.z, xydist))
		angles.r = math.deg(math.atan2(left.z, (left.y * forward.x) - (left.x * forward.y)))
	else
		angles.y = math.deg(math.atan2(-left.x, left.y))
		angles.p = math.deg(math.atan2(-forward.z, xydist))
		angles.r = 0
	end

	return angles
end

if (SERVER) then

	hook.Add("ShouldCollide", "helios_RPGFix", function(a, b)
		local aClass = a:GetClass()
		local bClass = b:GetClass()

		if (aClass == "rpg_missile" and (bClass == "helios_door" or bClass == "helios_gateway")) then
			return false
		elseif (bClass == "rpg_missile" and (aClass == "helios_door" or aClass == "helios_gateway")) then
			return false
		end
	end)
end



print("Helios Door Utilities Loaded!")
