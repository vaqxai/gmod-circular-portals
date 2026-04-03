AddCSLuaFile()

TOOL.Category = "Construction"
TOOL.Name = "Helios' Circular Gate"
TOOL.ClientConVar["key"] = ""
TOOL.ClientConVar["r"] = "167"
TOOL.ClientConVar["g"] = "100"
TOOL.ClientConVar["b"] = "30"
TOOL.ClientConVar["spawnenabled"] = "1"
TOOL.Information = {
	{name = "left", stage = 0},
	{name = "left_next", stage = 1, icon = "gui/lmb.png"}
}

cleanup.Register("hel_portalpairs")

if (SERVER) then
	if (!ConVarExists("sbox_maxhel_portalpairs")) then
		CreateConVar("sbox_maxhel_portalpairs", 50, {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Maximum number of portal pairs which can be created by users.")
	end
end

/*
	Gate placing
*/

function TOOL:LeftClick(trace)
	if (IsValid(trace.Entity) and trace.Entity:IsPlayer()) then return false end
	if (CLIENT) then return true end
	if (!self:GetOwner():CheckLimit("hel_portalpairs")) then return false end

	-- If we haven't selected a first point...
	if (self:GetStage() == 0) then
		-- Retrieve the physics object of any hit entity. Made useless by previous code, but /something/ needs to go into SetObject...
		-- As well, retrieve a modified version of the surface normal. This normal is always horizontal and only rotates around the Y axis. Yay straight ladders.
		local physObj = trace.Entity:GetPhysicsObjectNum(trace.PhysicsBone)

		-- Clear out any junk that could possibly be left over, and store our data.
		self:ClearObjects()
		self:SetObject(1, trace.Entity, trace.HitPos, physObj, trace.PhysicsBone, trace.HitNormal)

		if (trace.HitNormal.z == 1) then
			self.y1 = self:GetOwner():EyeAngles().y
		end

		-- Move to the next stage.
		self:SetStage(1)
	else
		-- Same as before, but create some nice variables for us to use.
		local physObj = trace.Entity:GetPhysicsObjectNum(trace.PhysicsBone)
		local color = Color(self:GetClientInfo("r"), self:GetClientInfo("g"), self:GetClientInfo("b"))
		local key = self:GetClientInfo("key")

		-- Store the data of our second click.
		self:SetObject(2, trace.Entity, trace.HitPos, physObj, trace.PhysicsBone, trace.HitNormal)

		local portal1 = ents.Create("helios_door")
		local portal2 = ents.Create("helios_door")

		local norm1 = self:GetNormal(1)
		local ang = norm1:Angle()

		if (self.y1) then
			ang.y = self.y1 + 180
		end

		ang:RotateAroundAxis(ang:Right(), -90)
		ang:RotateAroundAxis(ang:Up(), -90)
		portal1:SetPos(self:GetPos(1) + norm1 * 3)
		portal1:Spawn()
		portal1:SetAngles(ang)
		portal1:SetNotSolid(true)
		portal1:SetColour(color)
		portal1:SetOther(portal2)
		portal1.ToggleButton = numpad.OnDown(self:GetOwner(), tonumber(key), "PortalToggle", portal1)

		if (IsValid(self:GetEnt(1)) and self:GetEnt(1):GetClass() == "prop_physics") then
			portal1:SetParent(self:GetEnt(1))
		else
			portal1:PhysicsDestroy()
		end

		local ang2 = self:GetNormal(2):Angle()

		if (trace.HitNormal.z == 1) then
			ang2.y = self:GetOwner():EyeAngles().y + 180
		end

		ang2:RotateAroundAxis(ang2:Right(), -90)
		ang2:RotateAroundAxis(ang2:Up(), -90)
		portal2:SetPos(self:GetPos(2) + self:GetNormal(2) * 3)
		portal2:Spawn()
		portal2:SetAngles(ang2)
		portal2:SetNotSolid(true)
		portal2:SetColour(color)
		portal2:SetOther(portal1)
		portal2.ToggleButton = numpad.OnDown(self:GetOwner(), tonumber(key), "PortalToggle", portal2)

		if (tobool(self:GetClientInfo("spawnenabled"))) then
			portal1:Enable()
			portal2:Enable()
		end

		if (IsValid(self:GetEnt(2)) and self:GetEnt(2):GetClass() == "prop_physics") then
			portal2:SetParent(self:GetEnt(2))
		else
			portal2:PhysicsDestroy()
		end

		undo.Create("Helios Portal Pair")
			undo.AddEntity(portal1)
			undo.AddEntity(portal2)
			undo.SetPlayer(self:GetOwner())
			undo.SetCustomUndoText("Undone Helios Portal Pair")
		undo.Finish()

		-- We've finished making our portals, so go back to stage 0, clear any objects, and add 1 to our cleanup count.
		self:SetStage(0)
		self:ClearObjects()

		self.y1 = nil

		self:GetOwner():AddCount("hel_portalpairs", portal1)
		self:GetOwner():AddCleanup("hel_portalpairs", portal1)
		self:GetOwner():AddCleanup("hel_portalpairs", portal2)
	end

	return true
end

function TOOL:RightClick(trace)
end

function TOOL:DrawHUD()
	local trace = self:GetOwner():GetEyeTrace()
	local ang = trace.HitNormal:Angle()
	local wallAng = trace.HitNormal:Angle()
	local isOnFloor = trace.HitNormal.z == 1
	local eyeAng = Angle(0, self:GetOwner():EyeAngles().y, 0)

	if (isOnFloor) then
		ang.y = self:GetOwner():EyeAngles().y + 180
	end

	ang:RotateAroundAxis(ang:Right(), -90)
	ang:RotateAroundAxis(ang:Up(), -90)
	cam.Start3D()
	cam.Start3D2D(trace.HitPos + trace.HitNormal * 2 - (isOnFloor and (eyeAng:Right() * -60) or (wallAng:Right() * 60)) - (isOnFloor and eyeAng:Forward() or wallAng:Up()) * 60, ang, 1)
		surface.SetDrawColor(0, 255, 0, 30)
--		draw.Circle( 60, 60, 60, 32 )
		surface.DrawCircle(60,60,60,255,0,191,125)
--		surface.DrawRect(0,0, 120, 120)
	cam.End3D2D()
	cam.End3D()
end

function TOOL:Think()
end

/*
	Holster
	Clear stored objects and reset state
*/

function TOOL:Holster()
	self:ClearObjects()
	self:SetStage(0)
end

/*
	Control Panel
*/

function TOOL.BuildCPanel(CPanel)
	CPanel:AddControl("Header", {
		Description = "#tool.heliosgate.desc"
	})

	CPanel:AddControl("Numpad", {
		Label = "#tool.heliosgate.key",
		Command = "heliosgate_key"
	})

	CPanel:AddControl("Color", {
		Label = "#tool.heliosgate.color",
		Red = "heliosgate_r",
		Green = "heliosgate_g",
		Blue = "heliosgate_b"
	})

	CPanel:AddControl("CheckBox", {
		Label = "#tool.heliosgate.spawnon",
		Command = "heliosgate_spawnenabled"
	})
end

/*
	Language strings
*/

if (CLIENT) then
	language.Add("tool.heliosgate.name", "Heliosowe Portale ( ͡° ͜ʖ ͡°)")
	language.Add("tool.heliosgate.left", "Select the spot for the first portal")
	language.Add("tool.heliosgate.left_next", "Select the spot for the second portal")
	language.Add("tool.heliosgate.desc", "Create linked pairs of portals to allow easy travel")
	language.Add("tool.heliosgate.key", "Key to toggle the pair")
	language.Add("tool.heliosgate.color", "Portal color")
	language.Add("tool.heliosgate.spawnon", "Start On")

	language.Add("Cleaned_portalpairs", "Cleaned up all Helios Portal Pairs")
	language.Add("Cleanup_portalpairs", "Helios Portal Pairs")
end