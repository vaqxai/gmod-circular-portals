AddCSLuaFile()

AddCSLuaFile("imgui.lua")
local imgui = include("imgui.lua")

DEFINE_BASECLASS("base_gmodentity")
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Portal"
ENT.Category = "Helios Entities"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.AutomaticFrameAdvance = true

local USE_COOLDOWN = 0

local STATE_CLOSED = 0
local STATE_OPENING = 1
local STATE_OPEN = 2
local STATE_CLOSING = 3

local gpi = {}

if SERVER then
	gpi.GLOBAL_PORTAL_INDEX = {}
	gpi.MAX_PORTAL_CODES = 9 * 9 * 9

	function gpi.GetPortalByCode(code)
		local numericCode = tonumber(code)
		if not numericCode then return nil end

		local ent = gpi.GLOBAL_PORTAL_INDEX[numericCode]
		if IsValid(ent) then
			return ent
		end

		-- stale reference cleanup
		gpi.GLOBAL_PORTAL_INDEX[numericCode] = nil
		return nil
	end

	function gpi.GeneratePortalCode(ent)
		if not IsValid(ent) then
			return nil
		end

		if table.Count(gpi.GLOBAL_PORTAL_INDEX) >= gpi.MAX_PORTAL_CODES then
			return nil
		end

		for _ = 1, 128 do
			local code = tonumber(tostring(math.random(1, 9)) .. tostring(math.random(1, 9)) .. tostring(math.random(1, 9)))
			if not gpi.GLOBAL_PORTAL_INDEX[code] then
				gpi.GLOBAL_PORTAL_INDEX[code] = ent
				return code
			end
		end

		for i = 111, 999 do
			local code = tostring(i)
			if not string.find(code, "0", 1, true) then
				if not gpi.GLOBAL_PORTAL_INDEX[i] then
					gpi.GLOBAL_PORTAL_INDEX[i] = ent
					return i
				end
			end
		end

		return nil
	end

end

if SERVER then
	util.AddNetworkString("HeliosGateway_SendLinkCommand")
	util.AddNetworkString("HeliosGateway_SendLinkCommand_Reply")

	local MAX_USE_DISTANCE_SQR = 200 * 200

	-- Eye traces desync between client and server, so validate by distance instead.
	local function canUseGateway(ply, ent)
		if not IsValid(ply) or not IsValid(ent) then return false end
		if ent:GetClass() ~= "helios_gateway" then return false end
		if ply:GetPos():DistToSqr(ent:GetPos()) > MAX_USE_DISTANCE_SQR then return false end

		return true
	end

	net.Receive("HeliosGateway_SendLinkCommand", function(ln, ply)
		local ent = net.ReadEntity()
		local linkcode = tonumber(net.ReadString())

		if not canUseGateway(ply, ent) then return end
		if not linkcode then return end

		local other = gpi.GetPortalByCode(linkcode)

		net.Start("HeliosGateway_SendLinkCommand_Reply")
		net.WriteEntity(ent)
		net.WriteEntity(other)
		net.Send(ply)

		ent:Toggle(linkcode)

	end)

	util.AddNetworkString("HeliosGateway_SendUnlinkCommand")

	net.Receive("HeliosGateway_SendUnlinkCommand", function(ln, ply)
		local ent = net.ReadEntity()

		if not canUseGateway(ply, ent) then return end

		local other = ent:GetOther()
		if not IsValid(other) then return end

		ent:Toggle(other:GetCode())

	end)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "CurrentState")
	self:NetworkVar("Float", 0, "LastUsed")
	self:NetworkVar("Entity", 0, "PortalEnt")
	self:NetworkVar("Entity", 1, "PortalEnt2")
	self:NetworkVar("Entity", 2, "Other")
	self:NetworkVar("Int", 1, "Code")
end

function ENT:GravGunPickupAllowed()
    return false
end

if SERVER then
	-- Spawn-menu only; duplicator/PermaProps restores bypass this and keep saved angles.
	function ENT:SpawnFunction(ply, tr, class)
		if not tr.Hit then return end

		local ent = ents.Create(class)
		if not IsValid(ent) then return end

		ent:SetPos(tr.HitPos)
		ent:SetAngles(Angle(0, ply:EyeAngles().yaw + 90, 0)) -- +90 = model orientation offset
		ent:Spawn()
		ent:Activate()

		return ent
	end

	-- Runs on first Think, after duplicator/PermaProps restored DT vars
	-- (which happens AFTER Initialize). Syncs the code index with the final
	-- code value and resets stale restored state.
	function ENT:ReconcileCode()
		if self:GetCurrentState() ~= STATE_CLOSED and not IsValid(self:GetOther()) then
			self:SetCurrentState(STATE_CLOSED)
			self:SetPortalEnt(NULL)
			self:SetPortalEnt2(NULL)
		end

		local code = self:GetCode()

		if code and code > 0 and gpi.GLOBAL_PORTAL_INDEX[code] == self then return end

		for c, e in pairs(gpi.GLOBAL_PORTAL_INDEX) do
			if e == self then
				gpi.GLOBAL_PORTAL_INDEX[c] = nil
			end
		end

		local owner = code and code > 0 and gpi.GLOBAL_PORTAL_INDEX[code] or nil
		if code and code > 0 and not IsValid(owner) then
			gpi.GLOBAL_PORTAL_INDEX[code] = self
		else
			self:SetCode(gpi.GeneratePortalCode(self) or 0)
		end
	end
end

function ENT:Initialize()
	self:SetModel("models/helios/props/rep_portal.mdl")
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetCurrentState(STATE_CLOSED)

	if SERVER then
		-- Provisional; ReconcileCode() finalizes it on first Think.
		self:SetCode(gpi.GeneratePortalCode(self) or 0)
	end

	local phys = self:GetPhysicsObject()
	if ( IsValid(phys) ) then
        phys:SetMass(1000)
        phys:Sleep()
    end

	if CLIENT then
		-- TODO: network all of this perhaps?
		self.KPSound = CreateSound(self, "buttons/button17.wav")
		self.XSound = CreateSound(self, "buttons/button8.wav")
		self.ERSound = CreateSound(self, "buttons/button10.wav")
		self.OKSound = CreateSound(self, "buttons/button3.wav")
		self.DestCode = ""
		self.KPLastType = CurTime()
		self.ErrState = CurTime()
	end
end

local GATE_POSITION = Vector(0,2,39)
local GATE2_POSITION = Vector(0,-2,39)
local GATE_ANGLE = Angle(0,0,-90)
local GATE2_ANGLE = Angle(0,0,90)

local DOOR_COLOR = Color(0, 255, 30)

local function createGatewayDoor(gateway, localPos, localAng)
	local door = ents.Create("helios_door")
	if not IsValid(door) then return NULL end

	door:SetPos(gateway:LocalToWorld(localPos))
	door:Spawn()
	door:SetAngles(gateway:LocalToWorldAngles(localAng))
	door:SetNotSolid(true)
	door:SetColour(DOOR_COLOR)

	-- Active physics on a parented entity fights the parent transform (jitter).
	-- Keep the phys object itself: trigger touch detection needs the collision model.
	local phys = door:GetPhysicsObject()
	if IsValid(phys) then
		phys:EnableMotion(false)
		phys:Sleep()
	end
	door:SetMoveType(MOVETYPE_NONE)
	door:SetParent(gateway)

	return door
end

function ENT:CreatePairWith(other)
	local portal_self = createGatewayDoor(self, GATE_POSITION, GATE_ANGLE)
	local portal_self2 = createGatewayDoor(self, GATE2_POSITION, GATE2_ANGLE)
	local portal_other = createGatewayDoor(other, GATE_POSITION, GATE_ANGLE)
	local portal_other2 = createGatewayDoor(other, GATE2_POSITION, GATE2_ANGLE)

	portal_self:SetOther(portal_other)
	portal_other:SetOther(portal_self)

	portal_self2:SetOther(portal_other2)
	portal_other2:SetOther(portal_self2)

	self:SetOther(other)
	other:SetOther(self)

	self:SetPortalEnt(portal_self)
	self:SetPortalEnt2(portal_self2)
	other:SetPortalEnt(portal_other)
	other:SetPortalEnt2(portal_other2)
end

function ENT:RemovePairWith(other)
	local doors = {
		self:GetPortalEnt(),
		self:GetPortalEnt2(),
		other:GetPortalEnt(),
		other:GetPortalEnt2(),
	}

	for _, door in ipairs(doors) do
		if IsValid(door) then
			door:Disable()
			door:Remove()
		end
	end
end

function ENT:Toggle(linkcode, remote_open)
	if remote_open == nil then remote_open = false end
	local curState = self:GetCurrentState()
	if curState ~= STATE_CLOSED and curState ~= STATE_OPEN then return end
	local other = gpi.GetPortalByCode(linkcode)

	if not remote_open and curState == STATE_CLOSED then
		if not IsValid(other) then return end
		if IsValid(other) and IsValid(other:GetOther()) then return end
		if IsValid(other) and other == self then return end
		self:CreatePairWith(other)
		other:Toggle(self:GetCode(), true)
	elseif not remote_open and curState == STATE_OPEN then
		if not IsValid(other) then
			-- Partner gone; close just this side.
			self:RemovePairWith(self)
			self:SetOther(nil)
		else
			self:RemovePairWith(other)
			other:Toggle(self:GetCode(), true)
			other:SetOther(nil)
			self:SetOther(nil)
		end
	end

	if self:GetCurrentState() == STATE_CLOSED then
		self:SetCurrentState(STATE_OPENING)
		self:SetLastUsed(CurTime())
		self:ResetSequence(self:LookupSequence("opening"))
		self:SetPlaybackRate(1)

		self:EmitSound("mvm/mvm_deploy_giant.wav")

		timer.Simple(1.9, function()
			if self:GetCurrentState() ~= STATE_OPENING then return end
			self:EmitSound("mvm/mvm_deploy_giant.wav")
		end)

		timer.Simple(3.2, function()
			if self:GetCurrentState() ~= STATE_OPENING then return end
			util.ScreenShake(self:GetPos(), 5, 1, 3, 700)
			self:EmitSound("mvm/mvm_revive.wav")
			self:SetCurrentState(STATE_OPEN)
			self:GetPortalEnt():Enable()
			self:GetPortalEnt2():Enable()
		end)

	else
		local closing_sqid = self:LookupSequence("closing")
		self:SetCurrentState(STATE_CLOSING)
		self:SetLastUsed(CurTime())
		self:ResetSequence(closing_sqid)
		self:SetPlaybackRate(1)
		timer.Simple(self:SequenceDuration(closing_sqid), function()
			if not IsValid(self) then return end
			self:SetCurrentState(STATE_CLOSED)
		end)
	end
end

function ENT:Think()
	if SERVER and not self._codeReconciled then
		self._codeReconciled = true
		self:ReconcileCode()
	end

    self:FrameAdvance()
    self:NextThink(CurTime())
    return true
end

local DIS_POSITION = Vector(-2.5,-50,49)
local DIS_ANGLES = Angle(0,0,45)
local COLOR_1 = Color(44,44,44,200)
local COLOR_2 = Color(26,255,0,200)
local COLOR_3 = Color(114,114,114,200)
local COLOR_4 = Color(255,255,255,200)
local COLOR_5 = Color(164,255,154,200)
local COLOR_6 = Color(255,0,0,200)
local COLOR_7 = Color(255,156,156,200)

net.Receive("HeliosGateway_SendLinkCommand_Reply", function(ln)
	local self_ent = net.ReadEntity()
	local other_ent = net.ReadEntity()

	if not IsValid(other_ent) or other_ent:GetCode() == self_ent:GetCode() or (IsValid(other_ent) and IsValid(other_ent:GetOther())) then
		self_ent.ERSound:Stop()
		self_ent.ERSound:Play()
		self_ent.DestCode = ""
		self_ent.ErrState = CurTime()
	else
		self_ent.OKSound:Stop()
		self_ent.OKSound:Play()
	end
end)

function ENT:Draw()

    debugoverlay.Axis(self:GetPos(), self:LocalToWorldAngles(GATE2_ANGLE), 10, 0.1, true)

	local COLOR_BG = COLOR_1
	local COLOR_EDGE = COLOR_2
	local COLOR_HOVER = COLOR_5
	local COLOR_CLICK = COLOR_4
	local COLOR_RED = COLOR_6
	local COLOR_REDHOVER = COLOR_7

	if CurTime() - self.ErrState < 0.5 then
		COLOR_BG = COLOR_1
		COLOR_EDGE = COLOR_6
		COLOR_HOVER = COLOR_6
		COLOR_CLICK = COLOR_6
		COLOR_RED = COLOR_6
		COLOR_REDHOVER = COLOR_6
	end

	self:DrawModel()
	if imgui.Entity3D2D(self, DIS_POSITION, DIS_ANGLES, 0.03) then
		surface.SetDrawColor(COLOR_BG)
		surface.DrawRect(3,3,144,222, 3)
		surface.SetDrawColor(COLOR_EDGE)
		surface.DrawOutlinedRect(0,0,150,225, 3)
		if not IsValid(self:GetOther()) and self.DestCode != "" then
			draw.SimpleText(self:GetCode() .. " ∞ " .. self.DestCode, "DermaLarge", 10, 5, COLOR_CLICK)
		elseif IsValid(self:GetOther()) and self.DestCode == "" then
			draw.SimpleText(self:GetCode() .. " ∞ " .. self:GetOther():GetCode(), "DermaLarge", 10, 5, COLOR_2)
		else
			draw.SimpleText(self:GetCode() .. " ∞ " .. self.DestCode, "DermaLarge", 10, 5, COLOR_CLICK)
		end

		local kp_start_y = 40

		-- Enter Code
		for row = 0, 2 do
			for col = 0, 2 do
				local num = row * 3 + col + 1
				if num <= 9 then
					if imgui.xTextButton(tostring(num), "DermaLarge", 10 + (45 * col), kp_start_y + (45 * row), 40, 40, 3, COLOR_EDGE, COLOR_HOVER, COLOR_CLICK) then
						self.KPSound:Stop()
						self.KPSound:PlayEx(1, 50 + ((9 - num) * 15))
						self.KPLastType = CurTime()
						if #self.DestCode > 2 then
							self.DestCode = ""
						end
						self.DestCode = self.DestCode .. tostring(num)
					end
				end
			end
		end

		-- Clear Entry if idle for 5s
		if CurTime() - self.KPLastType > 5 and self.DestCode != "" then
			self.DestCode = ""
		end

		if imgui.xTextButton("< >", "DermaLarge", 10, 175, 85, 40, 3, COLOR_EDGE, COLOR_HOVER, COLOR_CLICK) and self.DestCode != "" then
			net.Start("HeliosGateway_SendLinkCommand")

			net.WriteEntity(self)
			net.WriteString(tostring(self.DestCode))
			net.SendToServer()
		end
		if imgui.xTextButton("X", "DermaLarge", 100, 175, 40, 40, 3, COLOR_RED, COLOR_REDHOVER, COLOR_CLICK) then

			if self.DestCode == "" and IsValid(self:GetOther()) then
				net.Start("HeliosGateway_SendUnlinkCommand")
				net.WriteEntity(self)
				net.SendToServer()
			end

			self.XSound:Stop()
			self.XSound:Play()
			self.DestCode = ""
		end


		imgui.End3D2D()
	end
end

function ENT:OnRemove()
	if SERVER then
		-- Purge by entity reference so mismatched entries can't linger.
		for c, e in pairs(gpi.GLOBAL_PORTAL_INDEX) do
			if e == self or not IsValid(e) then
				gpi.GLOBAL_PORTAL_INDEX[c] = nil
			end
		end
	end
end
