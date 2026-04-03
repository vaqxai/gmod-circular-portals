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

	function gpi.RemovePortalCodeFromIndex(code)
		local numericCode = tonumber(code)
		if not numericCode then
			return false
		end

		if gpi.GLOBAL_PORTAL_INDEX[numericCode] then
			gpi.GLOBAL_PORTAL_INDEX[numericCode] = nil
			return true
		end

		return false
	end

	function gpi.HasPortalCode(code)
		local numericCode = tonumber(code)
		return numericCode ~= nil and gpi.GLOBAL_PORTAL_INDEX[numericCode] ~= nil
	end
end

if SERVER then
	util.AddNetworkString("HeliosGateway_SendLinkCommand")
	util.AddNetworkString("HeliosGateway_SendLinkCommand_Reply")

	net.Receive("HeliosGateway_SendLinkCommand", function(ln, ply)
		ent = net.ReadEntity()
		linkcode = tonumber(net.ReadString())

		if ply:GetEyeTraceNoCursor().Entity != ent then
			return
		end

		local other = gpi.GetPortalByCode(linkcode)

		net.Start("HeliosGateway_SendLinkCommand_Reply")
		net.WriteEntity(ent)
		net.WriteEntity(other)
		net.Send(ply)

		ent:Toggle(linkcode)

	end)

	util.AddNetworkString("HeliosGateway_SendUnlinkCommand")

	net.Receive("HeliosGateway_SendUnlinkCommand", function(ln, ply)
		ent = net.ReadEntity()

		if ply:GetEyeTraceNoCursor().Entity != ent then
			return
		end

		ent:Toggle(ent:GetOther():GetCode())

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

function ENT:Initialize()
	self:SetModel("models/helios/props/rep_portal.mdl")
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetCurrentState(STATE_CLOSED)
	self:SetAngles(self:GetAngles() + Angle(0,90,0))

	if SERVER then
		if table.Count(gpi.GLOBAL_PORTAL_INDEX) >= gpi.MAX_PORTAL_CODES then
			return
		end

		local newcode = gpi.GeneratePortalCode(self)

		self:SetCode(newcode)
	end

	local phys = self:GetPhysicsObject()
	if ( IsValid(phys) ) then
        phys:Wake()
        phys:SetMass(1000)
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

function ENT:CreatePairWith(other)
	local portal_self = ents.Create("helios_door")
	local portal_self2 = ents.Create("helios_door")
	local portal_other = ents.Create("helios_door")
	local portal_other2 = ents.Create("helios_door")

	portal_self:SetPos(self:LocalToWorld(GATE_POSITION))
	portal_self:Spawn()
	portal_self:SetAngles(self:LocalToWorldAngles(GATE_ANGLE))
	portal_self:SetNotSolid(true)
	portal_self:SetColour(Color(0,255,30))
	portal_self:SetParent(self)

	portal_self2:SetPos(self:LocalToWorld(GATE2_POSITION))
	portal_self2:Spawn()
	portal_self2:SetAngles(self:LocalToWorldAngles(GATE2_ANGLE))
	portal_self2:SetNotSolid(true)
	portal_self2:SetColour(Color(0,255,30))
	portal_self2:SetParent(self)

	portal_other:SetPos(other:LocalToWorld(GATE_POSITION))
	portal_other:Spawn()
	portal_other:SetAngles(other:LocalToWorldAngles(GATE_ANGLE))
	portal_other:SetNotSolid(true)
	portal_other:SetColour(Color(0,255,30))
	portal_other:SetParent(other)

	portal_other2:SetPos(other:LocalToWorld(GATE2_POSITION))
	portal_other2:Spawn()
	portal_other2:SetAngles(other:LocalToWorldAngles(GATE2_ANGLE))
	portal_other2:SetNotSolid(true)
	portal_other2:SetColour(Color(0,255,30))
	portal_other2:SetParent(other)

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
	local portal_other = self:GetPortalEnt()
	local portal_other2 = self:GetPortalEnt2()
	local portal_self = other:GetPortalEnt()
	local portal_self2 = other:GetPortalEnt2()

	portal_other:Disable()
	portal_self:Disable()

	portal_other2:Disable()
	portal_self2:Disable()

	portal_other:Remove()
	portal_self:Remove()

	portal_other2:Remove()
	portal_self2:Remove()
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
		self:RemovePairWith(other)
		other:Toggle(self:GetCode(), true)
		other:SetOther(nil)
		self:SetOther(nil)
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
		gpi.RemovePortalCodeFromIndex(self:GetCode())
	end
end
