AddCSLuaFile()

if SERVER then
	util.AddNetworkString("HLSPRTL_DBG_EXIT")
	util.AddNetworkString("HLSPRTL_FLASH")
end

DEFINE_BASECLASS("base_entity")

ENT.Type			= "anim"
ENT.PrintName		= "Portal Standalone"
ENT.Category		= "Helios Entities"
ENT.Spawnable		= false
ENT.AdminOnly		= true
ENT.Model			= Model("models/hunter/blocks/cube1x2x025.mdl")
ENT.RenderGroup 	= RENDERGROUP_BOTH

local debugPlayers = {}

hook.Add("PlayerSay", "HeliosPortalsDebugMode", function(ply, text)
	if not ply:IsSuperAdmin() then return end

	if text == "helios czemu to gowno nie dziala" then
		local steamID = ply:SteamID()
		local debugMode = "disabled"

		if not debugPlayers[steamID] then
			debugPlayers[steamID] = true
			debugMode = "enabled"
		else
			debugPlayers[steamID] = nil
		end

		ply:ChatPrint("DebugMode is now " .. debugMode)
		return false
	end
end)

local function debugPrint(...)
	local msg = "[HELIOS DEBUG]: "
	for i,v in ipairs({...}) do
		msg = msg .. tostring(v)
	end

	for steamid,debugMode in pairs(debugPlayers) do
		local ply = player.GetBySteamID(steamid)
		if not IsValid(ply) then
			debugPlayers[steamid] = nil
			continue
		end

		ply:ChatPrint(msg)
	end
end

function ENT:SetupDataTables()
	self:NetworkVar("Bool", 0, "Enabled")
	self:NetworkVar("Vector", 0, "TempColor")
	self:NetworkVar("Vector", 1, "RealColor")
	self:NetworkVar("Entity", 0, "Other")
	self:NetworkVar("Float", 0, "AnimStart")

	if (SERVER) then
		self:NetworkVarNotify("TempColor", function(ent, name, old, new)
			local color = HSVToColor(new.x, new.y, new.z)
			local r = (color.r * 2) / 255
			local g = (color.g * 2) / 255
			local b = (color.b * 2) / 255

			self:SetRealColor(Vector(r, g, b))
		end)
	end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

local function InFront(posA, posB, normal)
	local Vec1 = (posB - posA):GetNormalized()

	return (normal:Dot(Vec1) >= 0)
end

if (SERVER) then
	function ENT:SpawnFunction(player, trace, class)
		if (!trace.Hit) then return end
		local entity = ents.Create(class)

		entity:SetPos(trace.HitPos + trace.HitNormal * 1.5)
		entity:Spawn()
		local ang = entity:GetAngles()
		ang:RotateAroundAxis(entity:GetForward(), -90)
		entity:SetAngles(ang)

		return entity
	end

	function ENT:Initialize()
		self:SetModel(self.Model)
		self:SetSolid(SOLID_VPHYSICS)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMaterial("vgui/black")
		self:DrawShadow(false)
		self:SetTrigger(true)
		self:SetEnabled(false)
		self:SetUseType(SIMPLE_USE)
		self:SetCollisionGroup(COLLISION_GROUP_WORLD)
		self:SetCustomCollisionCheck(true)

		local phys = self:GetPhysicsObject()

		if (IsValid(phys)) then
			phys:Wake()
		end
	end

	function ENT:Enable()
		if (self:GetEnabled()) then return end
		self:SetEnabled(true)
		self:EmitSound("Witcher.PortalOpen")

		if (!self.ambient) then
			local filter = RecipientFilter()
			filter:AddAllPlayers()

			self.ambient = CreateSound(self, "portal/portal_ambient.wav", filter)
		end

		self.ambient:Play()

		self:SetAnimStart(CurTime())
	end

	function ENT:Disable()
		if (!self:GetEnabled()) then return end
		self:SetEnabled(false)
		self:EmitSound("Witcher.PortalClose")

		if (self.ambient) then
			self.ambient:Stop()
		end

		self:SetAnimStart(CurTime())
	end

	function ENT:SetColour(color)
		local h, s, v = ColorToHSV(color)

		self:SetTempColor(Vector(h, s, v))

		if (IsValid(self:GetOther())) then
			self:GetOther():SetTempColor(Vector(h, s, v))
		end
	end

	function ENT:OnRemove()
		if (self.ambient) then
			self.ambient:Stop()
		end
	end

	function ENT:AcceptInput(input, activator, caller, data)
		local other = self:GetOther()
		if (input == "TurnOn") then
			self:Enable()

			if (IsValid(other)) then
				other:Enable()
			end
		elseif (input == "TurnOff") then
			self:Disable()

			if (IsValid(other)) then
				other:Disable()
			end
		elseif (input == "Toggle") then
			if (self:GetEnabled()) then
				self:Disable()

				if (IsValid(other)) then
					other:Disable()
				end
			else
				self:Enable()

				if (IsValid(other)) then
					other:Enable()
				end
			end
		end
	end

	function ENT:KeyValue(key, value)
		if (key == "color") then
			local args = string.Explode(" ", value, false)
			self:SetColour(Color(args[1], args[2], args[3]))
		end
	end

	function ENT:TransformOffset(v, a1, a2)
		return (v:Dot(a1:Right()) * a2:Right() + v:Dot(a1:Up()) * (-a2:Up()) - v:Dot(a1:Forward()) * a2:Forward())
	end

	function ENT:GetFloorOffset(pos1, height)
		local offset = Vector(0, 0, 0)
		local pos = Vector(0, 0, 0)
		pos:Set(pos1) --stupid pointers...
		pos = self:GetOther():WorldToLocal(pos)
		pos.y = pos.y + height
		pos.z = pos.z + 10

		for i = 0, 30 do
			local openspace = util.IsInWorld(self:GetOther():LocalToWorld(pos - Vector(0, i, 0)))
			--debugoverlay.Box(self:GetOther():LocalToWorld(pos - Vector(0, i, 0)), Vector(-2, -2, 0), Vector(2, 2, 2), 5)

			if (openspace) then
				offset.z = i
				break
			end
		end

		return offset
	end

	function ENT:GetOffsets(portal, ent)
		local pos

		if (ent:IsPlayer()) then
			pos = ent:EyePos()
		else
			pos = ent:GetPos()
		end

		local offset = self:WorldToLocal(pos)
		offset.x = -offset.x
		offset.y = offset.y
		local output = portal:LocalToWorld(offset)

		if (ent:IsPlayer() and SERVER) then
			return output + self:GetFloorOffset(output, (ent:EyePos() - ent:GetPos()).z)
		else
			return output
		end
	end

	function ENT:GetPortalAngleOffsets(portal, ent)
		local angles = ent:GetAngles()
		local normal = self:GetAngles():Up()
		local forward = -angles:Forward()
		local up = angles:Up()
		-- reflect forward
		local dot = forward:Dot(normal)
		forward = forward + (-2 * dot) * normal
		-- reflect up
		dot = up:Dot(normal)
		up = up + (-2 * dot) * normal
		-- convert to angles
		angles = math.VectorAngles(forward, up)
		local LocalAngles = self:WorldToLocalAngles(angles)
		-- repair
		LocalAngles.x = -LocalAngles.x
		LocalAngles.y = -LocalAngles.y

		return portal:LocalToWorldAngles(LocalAngles)
	end

	function ENT:StartTouch(ent)

	end

	function ENT:GravGunPickupAllowed()
        return false
	end

	function ENT:Touch(ent)

		if not IsValid(ent) then debugPrint(self:EntIndex(), " E01 Cannot teleport ent because it is not valid.") return end

		if ent:GetClass() == "helios_gateway" then debugPrint(self:EntIndex(), " E02 Cannot teleport ent because it is a gateway.") return end
		if ent:GetClass() == "helios_door" then debugPrint(self:EntIndex(), " E03 Cannot teleport ent because it is a door.") return end

		debugPrint(
			self:EntIndex(),
			" TOUCH ent=", ent,
			" class=", ent:GetClass(),
			" isPlayer=", tostring(ent:IsPlayer()),
			" otherValid=", tostring(IsValid(self:GetOther())),
			" enabled=", tostring(self:GetEnabled())
		)

		if (IsValid(self:GetOther()) and self:GetEnabled()) then
			local faceNormal = self:GetAngles():Up()

			-- Signed distance from the entity to the portal plane.
			-- Positive = same side the normal points toward ("front"),
			-- Negative = opposite side ("behind").
			-- Use WorldSpaceCenter for players so feet-position doesn't
			-- skew the result on wall-mounted portals.
			local checkPos = ent:IsPlayer() and ent:WorldSpaceCenter() or ent:GetPos()
			local ok, planeDist = pcall(DistanceToPlane, checkPos, self:GetPos(), faceNormal)

			if not ok then
				debugPrint(self:EntIndex(), " E05A DistanceToPlane failed: ", tostring(planeDist))
				return
			end

			debugPrint(
				self:EntIndex(),
				" TRACE planeDist=", planeDist,
				" checkPos=", checkPos,
				" selfPos=", self:GetPos(),
				" normal=", faceNormal
			)

			if (planeDist < 0) then
				debugPrint(
					self:EntIndex(),
					" E05B Behind portal plane, planeDist: ",
					planeDist
				)
			return end

			if not ent.lastPort then ent.lastPort = 0 end

			if (ent:IsPlayer()) then
				if (CurTime() < (ent.lastPort + 0.4)) then
					debugPrint(self:EntIndex(), " E06 Cooldown not elapsed, left: ", ent.lastPort + 0.4 - CurTime())
				return end

				debugPrint(self:EntIndex(), " TRACE Player passed cooldown, proceeding with teleport")

				local color = self:GetRealColor()
				local vel = ent:GetVelocity()
				local other = self:GetOther()

				local normVel = vel:GetNormalized()
				local dir = faceNormal:Dot(normVel)

				-- If they aren't approaching the portal or they aren't moving fast enough, don't teleport.
				-- Edit: buggy as fu
				-- if (dir > 0 or (self:GetUp().z <= 0.5 and vel:Length() < 1)) then return end

				local newPos = self:GetOffsets(other, ent)
				local newVel = self:TransformOffset(vel, self:GetAngles(), other:GetAngles())
				local newAngles = self:GetPortalAngleOffsets(other, ent)
				newAngles.z = 0

				-- Correct for if player is crouched
				newPos.z = newPos.z - (ent:EyePos() - ent:GetPos()).z

				-- Derive the outward normal from the angles, then ensure it points
				-- away from the portal plane toward newPos. The two paired helios_door
				-- entities have opposite rolls (Angle(0,0,-90) vs Angle(0,0,90)), so
				-- their Up vectors point in opposite directions. Using DistanceToPlane
				-- to check which side newPos is on lets us self-correct without caring
				-- which of the two doors "other" is.
				local otherNormal = other:GetAngles():Up()
				local checkDist = DistanceToPlane(newPos, other:GetPos(), otherNormal)
				if checkDist < 0 then
					otherNormal = -otherNormal
				end

				-- If the portal is slanted (non-floor/ceiling), push newPos out along
				-- the now-corrected outward normal so it clears the wall geometry.
				debugPrint(self:EntIndex(), " TRACE otherNormal=", otherNormal, " otherAngles.z=", other:GetAngles().z)
				if (other:GetAngles().z > -60) then
					newPos = newPos + otherNormal * 50
					debugPrint(self:EntIndex(), " TRACE Slanted portal, pushed newPos by 50")
				end

				local offset = Vector()

				-- Correcting for eye height usually ends up getting us stuck in slanted portals. Find open space for us
				for i = 0, 20 do
					local openspace = util.IsInWorld(newPos + Vector(0, 0, i))

					if (openspace) then
						offset.z = i
						break
					end
				end

				-- Nudge newPos away from the portal face along the outward normal,
				-- then ensure it is at least 16 units clear of the plane.
				newPos = newPos + offset + otherNormal * 3

				local exitPlaneDist = DistanceToPlane(newPos, other:GetPos(), otherNormal)
				if (exitPlaneDist <= 16) then
					newPos = newPos + otherNormal * (16 - exitPlaneDist)
				end

				debugPrint(self:EntIndex(), " TRACE newPos=", newPos, " exitPlaneDist=", exitPlaneDist)

				-- This trace allows 100% less getting stuck in things. It traces from the portal to the desired position using the player's hull.
				-- If it hits, it'll set you somewhere safe-ish most of the time.
				-- Use a fixed 32-unit offset along the portal normal for the trace
				-- start so it always clears the wall regardless of portal orientation.
				local up = otherNormal
				local nearestPoint = other:NearestPoint(newPos)
				local nearNormal = (newPos - nearestPoint):GetNormalized()
				local foundSpot = false
				local trace

				for i = 0, 30 do
					trace = util.TraceEntity({
						start = nearestPoint + up * 32 + nearNormal * 5 + other:GetRight() * i,
						endpos = newPos + up + other:GetRight() * i,
						filter = function(traceEnt) if (traceEnt == other or (IsValid(other:GetParent()) and traceEnt == other:GetParent())) then return false else return true end end
					}, ent)

					if (!trace.AllSolid) then
						foundSpot = true
						break
					end
				end
				-- Send debug data to all superadmins with debug mode enabled
				local finalPos = trace.HitPos + up * 2
				for steamid, _ in pairs(debugPlayers) do
					local dbgPly = player.GetBySteamID(steamid)
					if IsValid(dbgPly) then
						net.Start("HLSPRTL_DBG_EXIT")
						net.WriteEntity(other)       -- destination portal entity
						net.WriteVector(newPos)      -- computed target (red)
						net.WriteVector(trace.StartPos) -- trace start (black)
						net.WriteVector(trace.HitPos)   -- trace hit (green, pre-nudge)
						net.WriteVector(finalPos)    -- actual SetPos destination (white)
						net.WriteVector(up)          -- portal face normal for box orientation
						net.Send(dbgPly)
					end
				end

				debugPrint(self:EntIndex(), " TRACE foundSpot=", tostring(foundSpot), " traceAllSolid=", tostring(trace.AllSolid), " traceHitPos=", trace.HitPos)

				if (!foundSpot) then
					debugPrint(self:EntIndex(), " E07 Cannot teleport because safe spot not found.")
				return end

				local finalTeleportPos = trace.HitPos + up * 2
				debugPrint(self:EntIndex(), " TRACE TELEPORTING player to ", finalTeleportPos)

				ent:SetPos(finalTeleportPos)
				ent:SetLocalVelocity(newVel)
				ent:SetEyeAngles(newAngles)
				ent.lastPort = CurTime()

				sound.Play("portal/portal_teleport.wav", self:WorldSpaceCenter())
				sound.Play("portal/portal_teleport.wav", other:WorldSpaceCenter())

				ent:ScreenFade(SCREENFADE.IN, color_black, 0.2, 0.03)
			else
				if (CurTime() < (ent.lastPort or 0) + 0.4) then
					debugPrint(self:EntIndex(), " E08 Cannot teleport because cooldown not elapsed, left: ", (ent.lastPort or 0) + 0.4 - CurTime())
				return end

				if (ent:GetClass():find("door") or ent:GetClass():find("func_")) then
					debugPrint(self:EntIndex(), " E09 Cannot teleport because entity is a door or a func_")
				return end

				if (!IsValid(ent:GetPhysicsObject())) then
					debugPrint(self:EntIndex(), " E10 Cannot teleport because entity has no phys obj")
				return end

				if (IsValid(self:GetParent())) then
					for k, v in pairs(constraint.GetAllConstrainedEntities(self:GetParent())) do
						if (v == ent) then
							debugPrint(self:EntIndex(), " E10 Cannot teleport because entity is parent of self or constrained to self")
							return
						end
					end
				end

				-- If the entity is being held by a physgun, gravgun, or +use pickup,
				-- force-drop it before teleporting so the beam doesn't stretch across the map.
				ent:ForcePlayerDrop()

				local vel = ent:GetVelocity()
				local other = self:GetOther()

				local newPos = self:GetOffsets(other, ent)
				local newVel = self:TransformOffset(vel, self:GetAngles(), other:GetAngles())
				local newAngles = self:GetPortalAngleOffsets(other, ent)

				-- Derive the outward normal from the exit portal, ensuring it
				-- points away from the portal plane toward newPos (same logic
				-- as the player branch).
				local otherNormal = other:GetAngles():Up()
				local checkDist = DistanceToPlane(newPos, other:GetPos(), otherNormal)
				if checkDist < 0 then
					otherNormal = -otherNormal
				end

				-- If the portal is slanted, push newPos out along the outward
				-- normal so the prop clears wall geometry.
				if (other:GetAngles().z > -60) then
					newPos = newPos + otherNormal * 50
				end

				-- Find open space (same scan as players but without eye-height)
				local offset = Vector()
				for i = 0, 20 do
					local openspace = util.IsInWorld(newPos + Vector(0, 0, i))
					if (openspace) then
						offset.z = i
						break
					end
				end

				-- Nudge away from the portal face and ensure minimum clearance
				newPos = newPos + offset + otherNormal * 3

				local planeDist = DistanceToPlane(newPos, other:GetPos(), otherNormal)
				if (planeDist <= 16) then
					newPos = newPos + otherNormal * (16 - planeDist)
				end

				-- Trace from the portal to the desired position using the
				-- entity's hull to avoid getting stuck in geometry.
				local up = otherNormal
				local nearestPoint = other:NearestPoint(newPos)
				local nearNormal = (newPos - nearestPoint):GetNormalized()
				local foundSpot = false
				local trace

				for i = 0, 30 do
					trace = util.TraceEntity({
						start = nearestPoint + up * 32 + nearNormal * 5 + other:GetRight() * i,
						endpos = newPos + up + other:GetRight() * i,
						filter = function(traceEnt) if (traceEnt == other or (IsValid(other:GetParent()) and traceEnt == other:GetParent())) then return false else return true end end
					}, ent)

					if (!trace.AllSolid) then
						foundSpot = true
						break
					end
				end

				if (!foundSpot) then
					debugPrint(self:EntIndex(), " E11 Cannot teleport prop because safe spot not found.")
				return end

				local finalPos = trace.HitPos + up * 2

				-- Notify all clients to play the flash effect on this entity.
				-- Half-duration is 0.25s: white -> transparent over first half,
				-- then the teleport fires, then transparent -> normal over second half.
				local FLASH_HALF = 0.1
				net.Start("HLSPRTL_FLASH")
				net.WriteEntity(ent)
				net.WriteFloat(FLASH_HALF)
				net.Broadcast()

				-- Delay the actual teleport by one half-duration so the fade-out
				-- completes before the entity snaps to its new position.
				local entRef = ent
				timer.Simple(FLASH_HALF, function()
					if not IsValid(entRef) then return end

					entRef:SetPos(finalPos)

					if (IsValid(entRef:GetPhysicsObject())) then
						entRef:GetPhysicsObject():SetVelocity(newVel)
					end

					entRef:SetAngles(newAngles)
				end)

				ent.lastPort = CurTime()

				local selfRef  = self
				local otherRef = other
				timer.Simple(FLASH_HALF, function()
					if not IsValid(selfRef) then return end
					sound.Play("portal/portal_teleport.wav", selfRef:WorldSpaceCenter())
					if IsValid(otherRef) then
						sound.Play("portal/portal_teleport.wav", otherRef:WorldSpaceCenter())
					end
				end)
			end
		else
			debugPrint(self:EntIndex(), " E04 Cannot teleport ent because self does not have Other or self not Enabled, Other: ", self:GetOther(), ", Enabled: ", self:GetEnabled())
		end
	end

elseif (CLIENT) then

	local function DefineClipBuffer(ref)
		render.ClearStencil()
		render.SetStencilEnable(true)
		render.SetStencilCompareFunction(STENCIL_ALWAYS)
		render.SetStencilPassOperation(STENCIL_REPLACE)
		render.SetStencilFailOperation(STENCIL_KEEP)
		render.SetStencilZFailOperation(STENCIL_KEEP)
		render.SetStencilWriteMask(254)
		render.SetStencilTestMask(254)
		render.SetStencilReferenceValue(ref or 43)
	end

	local function DrawToBuffer()
		render.SetStencilCompareFunction(STENCIL_EQUAL)
	end

	local function EndClipBuffer()
		render.SetStencilEnable(false)
		render.ClearStencil()
	end

	function ENT:Initialize()
		self.PixVis = util.GetPixelVisibleHandle()
		self._matrix = Matrix()
		self._matrix:Scale(Vector(1, 1, 0.01))
		self._offset = 1.8

		local effectData = EffectData()
		effectData:SetEntity(self)
		effectData:SetOrigin(self:GetPos())
		util.Effect("portal_inhale", effectData)

		self:SetSolid(SOLID_VPHYSICS)

		self.hole = ClientsideModel("models/helios/effects/portal_top_inside.mdl", RENDERGROUP_BOTH)
		self.hole:SetPos(self:GetPos() - self:GetUp() * (0 + self._offset))
		self.hole:SetAngles(self:GetAngles())
		self.hole:SetParent(self)
		self.hole:SetNoDraw(true)
		self.hole:EnableMatrix("RenderMultiply", self._matrix)

		self.top = ClientsideModel("models/helios/effects/portal_side_inside.mdl", RENDERGROUP_BOTH)
		self.top:SetMaterial("portal/border3")
		self.top:SetPos(self:GetPos() + self:GetRight() * -0 - self:GetUp() * (0 + self._offset))
		self.top:SetParent(self)
		self.top:SetLocalAngles(Angle(0, 0, 0))
		self.top:SetNoDraw(true)
		-- self.top:EnableMatrix("RenderMultiply", self._matrix)

		self.back = ClientsideModel("models/hunter/plates/plate3x3.mdl", RENDERGROUP_BOTH)
		self.back:SetMaterial("vgui/black")
		self.back:SetPos(self:GetPos() - self:GetUp() * 42)
		self.back:SetParent(self)
		self.back:SetLocalAngles(angle_zero)
		self.back:SetNoDraw(true)

		self.h, self.s, self.l = 0, 1, 1

	end

	function ENT:OnRemove()
		self.top:Remove()
		self.hole:Remove()
		self.back:Remove()
	end

	function ENT:Draw()

	end

	function ENT:Think()
		if (self:GetEnabled()) then
			local light = DynamicLight(self:EntIndex())

			if (light) then
				local vecCol = self:GetRealColor()
				light.pos = self:WorldSpaceCenter() + self:GetUp() * 15
				light.Size = 300
				light.style = 5
				light.Decay = 600
				light.brightness = 1
				light.r = (vecCol.x / 2) * 255
				light.g = (vecCol.y / 2) * 255
				light.b = (vecCol.z / 2) * 255
				light.DieTime = CurTime() + 0.1
			end
		end

		if (!IsValid(self.hole)) then
			self.hole = ClientsideModel("models/hunter/plates/plate1x2.mdl", RENDERGROUP_BOTH)
			self.hole:SetPos(self:GetPos() - self:GetUp() * (1 + self._offset))
			self.hole:SetAngles(self:GetAngles())
			self.hole:SetParent(self)
			self.hole:SetNoDraw(true)
			self.hole:EnableMatrix("RenderMultiply", self._matrix)
		end

		if (!IsValid(self.top)) then
			self.top = ClientsideModel("models/hunter/plates/plate075x1.mdl", RENDERGROUP_BOTH)
			self.top:SetMaterial("portal/border3")
			self.top:SetPos(self:GetPos() + self:GetRight() * 44.5 - self:GetUp() * (12.5 + self._offset))
			self.top:SetParent(self)
			self.top:SetLocalAngles(Angle(-75, -90, 0))
			self.top:SetNoDraw(true)
			self.top:EnableMatrix("RenderMultiply", self._matrix)
		end


		if (!IsValid(self.back)) then
			self.back = ClientsideModel("models/hunter/plates/plate3x3.mdl", RENDERGROUP_BOTH)
			self.back:SetMaterial("vgui/black")
			self.back:SetPos(self:GetPos() - self:GetUp() * 42)
			self.back:SetParent(self)
			self.back:SetLocalAngles(angle_zero)
			self.back:SetNoDraw(true)
		end

		self.top:SetParent(self)
		self.hole:SetParent(self)
		self.back:SetParent(self)
	end

	local mat = CreateMaterial("witcherGlow", "UnlitGeneric", {
		["$basetexture"] = "sprites/light_glow02",
		["$basetexturetransform"] = "center 0 0 scale 1 1 rotate 0 translate 0 0",
		["$additive"] = 1,
		["$translucent"] = 1,
		["$vertexcolor"] = 1,
		["$vertexalpha"] = 1,
		["$ignorez"] = 1
	})

	local tempcolor = Color(0,0,0,0)
	local unit_vector = Vector(1,1,0.01)
	local green = Color(0,255,0,1)

	-- Prop teleport flash effect
	-- Keyed by entity index. Each entry: { startTime, halfDuration, origColor, origRenderMode }
	local flashEntities = {}

	local whiteMat = CreateMaterial("HLSPRTL_WhiteFlash", "UnlitGeneric", {
		["$basetexture"] = "color/white",
		["$model"]       = 1,
	})

	hook.Add("PostDrawOpaqueRenderables", "HLSPRTL_WhiteOverlay", function()
		local now = CurTime()
		for entIdx, frame in pairs(flashEntities) do
			local ent = Entity(entIdx)
			if not IsValid(ent) then continue end

			local elapsed = now - frame.startTime
			local half    = frame.halfDuration

			if elapsed >= half * 2 then continue end

			-- White intensity mirrors the alpha curve:
			-- first half: 1 -> 0, second half: 0 -> 1
			-- So the overlay is brightest when the entity is most opaque,
			-- and gone at the midpoint when the entity is invisible anyway.
			local intensity
			if elapsed < half then
				intensity = 1 - (elapsed / half)
			else
				intensity = (elapsed - half) / half
			end

			render.SetColorModulation(intensity, intensity, intensity)
			render.MaterialOverride(whiteMat)
			ent:DrawModel()
			render.MaterialOverride(nil)
			render.SetColorModulation(1, 1, 1)
		end
	end)

	hook.Add("Think", "HLSPRTL_FlashThink", function()
		local now = CurTime()
		for entIdx, frame in pairs(flashEntities) do
			local ent = Entity(entIdx)
			if not IsValid(ent) then
				flashEntities[entIdx] = nil
				continue
			end

			local elapsed = now - frame.startTime
			local total   = frame.halfDuration * 2
			local half    = frame.halfDuration

			if elapsed >= total then
				-- Restore original color and render mode
				ent:SetColor(frame.origColor)
				ent:SetRenderMode(frame.origRenderMode)
				flashEntities[entIdx] = nil
				continue
			end

			-- First half:  alpha 255 -> 0  (fade to transparent before teleport)
			-- Second half: alpha 0 -> 255  (fade back in after teleport)
			local alpha
			if elapsed < half then
				alpha = 255 * (1 - (elapsed / half))
			else
				alpha = 255 * ((elapsed - half) / half)
			end

			ent:SetColor(Color(255, 255, 255, alpha))
		end
	end)

	net.Receive("HLSPRTL_FLASH", function()
		local ent     = net.ReadEntity()
		local halfDur = net.ReadFloat()

		if not IsValid(ent) then return end

		local entIdx = ent:EntIndex()

		-- If already flashing, restore before overwriting so render mode
		-- doesn't get permanently stuck on a previous frame's state.
		local prev = flashEntities[entIdx]
		if prev then
			ent:SetColor(prev.origColor)
			ent:SetRenderMode(prev.origRenderMode)
		end

		flashEntities[entIdx] = {
			startTime      = CurTime(),
			halfDuration   = halfDur,
			origColor      = ent:GetColor(),
			origRenderMode = ent:GetRenderMode(),
		}

		-- RENDERMODE_TRANSCOLOR makes SetColor's RGB tint AND alpha both take effect.
		-- RENDERMODE_TRANSALPHA is a legacy Goldsource mode that does not support transparency in Source.
		ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
		ent:SetColor(Color(255, 255, 255, 255))
	end)

	-- Debug exit position visualization
	-- Keyed by destination portal entity index. Each entry:
	--   { newPos, traceStart, traceHit, finalPos, up, expiry }
	local exitDebugFrames = {}

	local HULL_MIN = Vector(-16, -16, 0)
	local HULL_MAX = Vector( 16,  16, 72)
	local DBG_DURATION = 3  -- seconds each frame stays visible

	net.Receive("HLSPRTL_DBG_EXIT", function()
		local portalEnt  = net.ReadEntity()
		local newPos     = net.ReadVector()
		local traceStart = net.ReadVector()
		local traceHit   = net.ReadVector()
		local finalPos   = net.ReadVector()
		local up         = net.ReadVector()

		if not IsValid(portalEnt) then return end

		exitDebugFrames[portalEnt:EntIndex()] = {
			newPos     = newPos,
			traceStart = traceStart,
			traceHit   = traceHit,
			finalPos   = finalPos,
			up         = up,
			expiry     = CurTime() + DBG_DURATION,
		}
	end)

	function ENT:DrawTranslucent()

		debugoverlay.BoxAngles(self:GetPos(), unit_vector * -60, unit_vector * 60, self:GetAngles(), 0.1, green)
		debugoverlay.Axis(self:GetPos(), self:GetAngles(), 10, 0.1, true)

		-- Draw exit position debug boxes when this entity is the destination portal
		local frame = exitDebugFrames[self:EntIndex()]
		if frame and CurTime() < frame.expiry then
			local remaining = frame.expiry - CurTime()
			-- Red   = computed newPos (target before trace)
			debugoverlay.Box(frame.newPos,     HULL_MIN, HULL_MAX, remaining, Color(255, 0,   0,   40))
			-- Black = trace start point
			debugoverlay.Box(frame.traceStart, HULL_MIN, HULL_MAX, remaining, Color(20,  20,  20,  40))
			-- Green = trace hit point (pre-nudge)
			debugoverlay.Box(frame.traceHit,   HULL_MIN, HULL_MAX, remaining, Color(0,   255, 0,   40))
			-- White = final SetPos destination (trace.HitPos + up * 2)
			debugoverlay.Box(frame.finalPos,   HULL_MIN, HULL_MAX, remaining, Color(255, 255, 255, 80))
			-- Line from portal face to final destination
			debugoverlay.Line(self:GetPos(), frame.finalPos, remaining, Color(255, 255, 0, 255), true)
		elseif frame then
			exitDebugFrames[self:EntIndex()] = nil
		end

		if (InFront(LocalPlayer():EyePos(), self:GetPos() - self:GetUp() * 1.8, self:GetUp())) then return end

		local bEnabled = self:GetEnabled()
		local color = self:GetRealColor()
		local elapsed = CurTime() - self:GetAnimStart()
		local frac = math.Clamp(elapsed / (bEnabled and 0.5 or 0.1), 0, 1)

		if (frac <= 1) then
			tempcolor:SetUnpacked((color.x / 2) * 255, (color.y / 2) * 255, (color.z / 2) * 255, 255)
			self.h, self.s, self.l = ColorToHSL(tempcolor)
			self.l = Lerp(frac, self.l or 1, bEnabled and 0 or 1)
			self.col = HSLToColor(self.h, self.s, self.l)
		end

		if (bEnabled) then
			self.lerpr = Lerp(frac, self.lerpr or 255, self.col.r)
			self.lerpg = Lerp(frac, self.lerpg or 255, self.col.g)
			self.lerpb = Lerp(frac, self.lerpb or 255, self.col.b)
		else
			self.lerpr = Lerp(frac, self.lerpr or 0, self.col.r)
			self.lerpg = Lerp(frac, self.lerpg or 0, self.col.g)
			self.lerpb = Lerp(frac, self.lerpb or 0, self.col.b)
		end

		self.top:SetNoDraw(true)

		DefineClipBuffer()

		if ((bEnabled and frac > 0) or (!bEnabled and frac < 1)) then
			self.hole:DrawModel()
		end

		DrawToBuffer()

		render.ClearBuffersObeyStencil(self.lerpr, self.lerpg, self.lerpb, 0, bEnabled)

		if (bEnabled and frac >= 0.1) then
			if (frac >= 1) then
				self.back:DrawModel()
			end
			render.SetColorModulation(color.x * 3, color.y * 3, color.z * 3)
			self.top:DrawModel()
			render.SetColorModulation(1, 1, 1)
		end

		EndClipBuffer()

		if (!bEnabled) then return end

		local norm = self:GetUp()
		local viewNorm = (self:GetPos() - EyePos()):GetNormalized()
		local dot = viewNorm:Dot(norm * -1)

		if (dot >= 0) then
			render.SetColorModulation(1, 1, 1)
			local visible = util.PixelVisible(self:GetPos() + self:GetUp() * 3, 20, self.PixVis)

			if (!visible) then return end

			local alpha = math.Clamp((EyePos():Distance(self:GetPos()) / 10) * dot * visible, 0, 30)
			tempcolor:SetUnpacked(color.x, color.y, color.z, alpha)

			render.SetMaterial(mat)
			render.DrawSprite(self:GetPos() + self:GetUp() * 2, 600, 600, tempcolor, visible * dot)
		end
	end
end
