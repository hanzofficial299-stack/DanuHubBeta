local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Terrain = workspace:FindFirstChildOfClass("Terrain")
local Net = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net

-- Try to get FastCast module for hooking
local FastCastModule = nil
pcall(function()
    for _, module in pairs(ReplicatedStorage:GetDescendants()) do
        if module:IsA("ModuleScript") and module.Name:lower():find("fastcast") then
            FastCastModule = require(module)
            break
        end
    end
end)

-- Auto Catch Controller - instant catch when fish bites
local AutoCatchController = { Enabled = false, Connections = {} }

local AutoCatchCooldown = false -- Prevent spam

function AutoCatchController:InstantCatch()
    if not self.Enabled then return end
    if FishingActive then return end
    if AutoCatchCooldown then return end
    AutoCatchCooldown = true
    
    task.spawn(function()
        -- Wait minimum time then complete
        -- Note: This only works if fish already bit (detected by hook)
        task.wait(0.5) -- Short wait since bite already detected
        pcall(function() Net["RE/FishingCompleted"]:FireServer() end)
        task.wait(0.05)
        pcall(function() Net["RE/FishingCompleted"]:FireServer() end)
        Stats.FishCaught = Stats.FishCaught + 1
        task.wait(1.0) -- Cooldown to prevent spam
        AutoCatchCooldown = false
    end)
end

function AutoCatchController:Enable()
    if self.Enabled then return end
    self.Enabled = true
    
    -- Method 1: Hook RemoteEvents from server (bite notifications)
    pcall(function()
        for name, remote in pairs(Net) do
            if remote and typeof(remote) == "Instance" and remote:IsA("RemoteEvent") then
                local conn = remote.OnClientEvent:Connect(function(...)
                    if not self.Enabled then return end
                    local args = {...}
                    -- Detect bite-related events
                    pcall(function()
                        local argsStr = tostring(args[1] or "")
                        if argsStr:lower():find("bite") or argsStr:lower():find("hooked") or argsStr:lower():find("catch") then
                            self:InstantCatch()
                        end
                    end)
                end)
                table.insert(self.Connections, conn)
            end
        end
    end)
    
    -- Method 2: Monitor workspace for bite indicators
    local conn1 = workspace.DescendantAdded:Connect(function(obj)
        if not self.Enabled then return end
        pcall(function()
            local name = obj.Name:lower()
            if name:find("splash") or name:find("bobber") or name:find("bite") or 
               name:find("exclamation") or name:find("alert") or name:find("!") or
               name:find("hooked") or name:find("tension") then
                self:InstantCatch()
            end
        end)
    end)
    table.insert(self.Connections, conn1)
    
    -- Method 3: Monitor player's fishing state via attributes/values
    pcall(function()
        local char = Player.Character
        if char then
            for _, obj in pairs(char:GetDescendants()) do
                if obj:IsA("BoolValue") or obj:IsA("StringValue") then
                    local conn = obj.Changed:Connect(function(val)
                        if not self.Enabled then return end
                        local name = obj.Name:lower()
                        if name:find("fish") or name:find("bite") or name:find("hook") then
                            if val == true or tostring(val):lower():find("bite") then
                                self:InstantCatch()
                            end
                        end
                    end)
                    table.insert(self.Connections, conn)
                end
            end
        end
    end)
    
    -- Method 4: Monitor ReplicatedStorage for fishing signals
    pcall(function()
        local conn = ReplicatedStorage.DescendantAdded:Connect(function(obj)
            if not self.Enabled then return end
            if obj.Name:lower():find("bite") or obj.Name:lower():find("hooked") then
                self:InstantCatch()
            end
        end)
        table.insert(self.Connections, conn)
    end)
    
    -- Method 5: Hook PlayFishingEffect remote
    pcall(function()
        local effectRemote = Net["RE/PlayFishingEffect"]
        if effectRemote then
            local conn = effectRemote.OnClientEvent:Connect(function(...)
                if self.Enabled then
                    self:InstantCatch()
                end
            end)
            table.insert(self.Connections, conn)
        end
    end)
end

function AutoCatchController:Disable()
    if not self.Enabled then return end
    self.Enabled = false
    for _, conn in pairs(self.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    self.Connections = {}
end

local Config = {
    BlatantMode = false, NoAnimation = false, FlyEnabled = false, SpeedEnabled = false, NoclipEnabled = false,
    FlySpeed = 50, WalkSpeed = 50, 
    ReelDelay = 0.5,
    FishingDelay = 0.3,
    ChargeTime = 0.3,
    MultiCast = false, CastAmount = 3, CastPower = 0.55, CastAngleMin = -0.8, CastAngleMax = 0.8,
    InstantFish = false, AutoSell = false, AutoSellThreshold = 50,
    AutoBuyEventEnabled = false, SelectedEvent = "Wind", AutoBuyCheckInterval = 5,
    AntiAFKEnabled = true, AutoRejoinEnabled = false, AutoRejoinDelay = 5, AntiLagEnabled = false,
    AutoFavoriteEnabled = false, FavoriteRarity = "Legendary",
    PerformanceMode = false, AutoCatchEnabled = false
}

local EventList = { "Wind", "Cloudy", "Snow", "Storm", "Radiant", "Shark Hunt" }
local RarityList = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local Stats = { StartTime = 0, FishCaught = 0, TotalSold = 0, FavoriteCount = 0 }
local FishingActive = false

local AnimationController = { IsDisabled = false, Connection = nil }
local FlyController = { BodyVelocity = nil, BodyGyro = nil, Connection = nil }
local NoclipController = { Connection = nil }
local AutoBuyEventController = { Connection = nil, LastBuyTime = 0 }
local AntiAFKController = { Connection = nil, IdleConnection = nil }
local AutoRejoinController = { Connection = nil }
local AntiLagController = { Enabled = false, OriginalSettings = {} }
local AutoFavoriteController = { Connection = nil }
local PerformanceController = { Enabled = false, OriginalFunctions = {} }

function PerformanceController:Enable()
    if self.Enabled then return end
    self.Enabled = true
    pcall(function()
        for _, sound in pairs(workspace:GetDescendants()) do
            if sound:IsA("Sound") then
                sound.Volume = 0
            end
        end
        for _, effect in pairs(workspace:GetDescendants()) do
            if effect:IsA("ParticleEmitter") or effect:IsA("Trail") or effect:IsA("Beam") then
                effect.Enabled = false
            end
        end
        for _, billboard in pairs(workspace:GetDescendants()) do
            if billboard:IsA("BillboardGui") then
                billboard.Enabled = false
            end
        end
        -- Disable Lightning Effects
        for _, model in pairs(workspace:GetDescendants()) do
            if model:IsA("Model") and model.Name == "LightningBolt" then
                model:Destroy()
            end
        end
        -- Disable other visual effects
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("Sparkles") or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
                obj.Enabled = false
            end
        end
        -- Disable FastCast visualization objects
        local fastCastFolder = workspace.Terrain:FindFirstChild("FastCastVisualizationObjects")
        if fastCastFolder then
            fastCastFolder:ClearAllChildren()
        end
        -- Disable CosmeticFolder effects (fishing rod visuals)
        local cosmeticFolder = workspace:FindFirstChild("CosmeticFolder")
        if cosmeticFolder then
            for _, obj in pairs(cosmeticFolder:GetDescendants()) do
                if obj:IsA("BasePart") then
                    obj.Transparency = 1
                elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
                    obj.Enabled = false
                end
            end
        end
        -- Try to disable FastCast debug mode
        pcall(function()
            local FastCast = ReplicatedStorage:FindFirstChild("Packages")
            if FastCast then
                for _, module in pairs(FastCast:GetDescendants()) do
                    if module:IsA("ModuleScript") and module.Name:lower():find("fastcast") then
                        local fc = require(module)
                        if fc.VisualizeCasts ~= nil then
                            fc.VisualizeCasts = false
                        end
                        if fc.DebugLogging ~= nil then
                            fc.DebugLogging = false
                        end
                    end
                end
            end
        end)
    end)
    -- Auto cleanup new effects
    self.CleanupConnection = workspace.DescendantAdded:Connect(function(obj)
        if self.Enabled then
            pcall(function()
                if obj:IsA("Model") and obj.Name == "LightningBolt" then
                    obj:Destroy()
                elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
                    obj.Enabled = false
                elseif obj:IsA("Sound") then
                    obj.Volume = 0
                elseif obj:IsA("Sparkles") or obj:IsA("Fire") or obj:IsA("Smoke") then
                    obj.Enabled = false
                end
            end)
        end
    end)
    -- Cleanup FastCast visuals
    self.FastCastCleanup = workspace.Terrain.DescendantAdded:Connect(function(obj)
        if self.Enabled and obj.Parent and obj.Parent.Name == "FastCastVisualizationObjects" then
            pcall(function() obj:Destroy() end)
        end
    end)
end

function PerformanceController:Disable()
    if not self.Enabled then return end
    self.Enabled = false
    if self.CleanupConnection then
        self.CleanupConnection:Disconnect()
        self.CleanupConnection = nil
    end
    pcall(function()
        for _, sound in pairs(workspace:GetDescendants()) do
            if sound:IsA("Sound") then
                sound.Volume = 0.5
            end
        end
        for _, effect in pairs(workspace:GetDescendants()) do
            if effect:IsA("ParticleEmitter") or effect:IsA("Trail") or effect:IsA("Beam") then
                effect.Enabled = true
            end
        end
        for _, billboard in pairs(workspace:GetDescendants()) do
            if billboard:IsA("BillboardGui") then
                billboard.Enabled = true
            end
        end
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("Sparkles") or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
                obj.Enabled = true
            end
        end
    end)
end

function AntiLagController:Enable()
    if self.Enabled then return end
    self.OriginalSettings = { GlobalShadows = Lighting.GlobalShadows, FogEnd = Lighting.FogEnd }
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        settings().Rendering.QualityLevel = 1
        if Terrain then Terrain.Decoration = false end
        for _, v in pairs(workspace:GetDescendants()) do
            pcall(function()
                if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then v.Enabled = false
                elseif v:IsA("MeshPart") or v:IsA("Part") then v.Material = Enum.Material.Plastic v.CastShadow = false end
            end)
        end
    end)
    self.Enabled = true
end

function AntiLagController:Disable()
    if not self.Enabled then return end
    pcall(function()
        Lighting.GlobalShadows = self.OriginalSettings.GlobalShadows
        Lighting.FogEnd = self.OriginalSettings.FogEnd
        settings().Rendering.QualityLevel = 10
    end)
    self.Enabled = false
end

function AnimationController:Disable()
    if self.IsDisabled then return end
    pcall(function()
        local char = Player.Character if not char then return end
        local hum = char:FindFirstChild("Humanoid")
        if hum then for _, t in pairs(hum:GetPlayingAnimationTracks()) do t:Stop() end
            self.Connection = hum.AnimationPlayed:Connect(function(t) if Config.NoAnimation then t:Stop() end end) end
        local anim = char:FindFirstChild("Animate") if anim then anim.Enabled = false end
    end)
    self.IsDisabled = true
end

function AnimationController:Enable()
    if not self.IsDisabled then return end
    pcall(function()
        local char = Player.Character if not char then return end
        if self.Connection then self.Connection:Disconnect() self.Connection = nil end
        local anim = char:FindFirstChild("Animate") if anim then anim.Enabled = true end
    end)
    self.IsDisabled = false
end

function FlyController:Enable()
    if self.Connection then return end
    local function setup()
        local char = Player.Character if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart") if not root then return end
        if self.BodyVelocity then self.BodyVelocity:Destroy() end
        if self.BodyGyro then self.BodyGyro:Destroy() end
        self.BodyVelocity = Instance.new("BodyVelocity") self.BodyVelocity.Velocity = Vector3.zero self.BodyVelocity.MaxForce = Vector3.new(4e4,4e4,4e4) self.BodyVelocity.P = 1000 self.BodyVelocity.Parent = root
        self.BodyGyro = Instance.new("BodyGyro") self.BodyGyro.MaxTorque = Vector3.new(4e4,4e4,4e4) self.BodyGyro.P = 1000 self.BodyGyro.D = 50 self.BodyGyro.Parent = root
        self.Connection = RunService.Heartbeat:Connect(function()
            if not Config.FlyEnabled or not root then self:Disable() return end
            local cam = workspace.CurrentCamera if not cam then return end
            self.BodyGyro.CFrame = cam.CFrame
            local dir = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0,1,0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0,1,0) end
            self.BodyVelocity.Velocity = dir.Magnitude > 0 and dir.Unit * Config.FlySpeed or Vector3.zero
        end)
    end
    setup()
    Player.CharacterAdded:Connect(function() if Config.FlyEnabled then task.wait(1) setup() end end)
end

function FlyController:Disable()
    if self.BodyVelocity then self.BodyVelocity:Destroy() self.BodyVelocity = nil end
    if self.BodyGyro then self.BodyGyro:Destroy() self.BodyGyro = nil end
    if self.Connection then self.Connection:Disconnect() self.Connection = nil end
end

local function updateSpeed()
    local char = Player.Character if char and char:FindFirstChild("Humanoid") then char.Humanoid.WalkSpeed = Config.SpeedEnabled and Config.WalkSpeed or 16 end
end

function NoclipController:Enable()
    if self.Connection then return end
    self.Connection = RunService.Stepped:Connect(function()
        if not Config.NoclipEnabled then self:Disable() return end
        local char = Player.Character if char then for _, p in pairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = false end end end
    end)
end

function NoclipController:Disable()
    if self.Connection then self.Connection:Disconnect() self.Connection = nil end
    local char = Player.Character if char then for _, p in pairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = true end end end
end

local function SellAllFish() local s = pcall(function() Net["RF/SellAllItems"]:InvokeServer() end) if s then Stats.TotalSold = Stats.TotalSold + 1 end return s end

function AutoBuyEventController:PurchaseEvent(e)
    local s, r = pcall(function() return Net["RF/PurchaseWeatherEvent"]:InvokeServer(e) end)
    return s, r
end

function AutoBuyEventController:Enable()
    if self.Connection then return end
    self.Connection = task.spawn(function()
        while Config.AutoBuyEventEnabled do
            if os.clock() - self.LastBuyTime >= Config.AutoBuyCheckInterval then self:PurchaseEvent(Config.SelectedEvent) self.LastBuyTime = os.clock() end
            task.wait(1)
        end
    end)
end

function AutoBuyEventController:Disable() if self.Connection then task.cancel(self.Connection) self.Connection = nil end end

function AntiAFKController:Enable()
    if self.IdleConnection then return end
    self.IdleConnection = Player.Idled:Connect(function() if Config.AntiAFKEnabled then VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.zero) end end)
    self.Connection = task.spawn(function() while Config.AntiAFKEnabled do pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.zero) end) task.wait(60) end end)
end

function AntiAFKController:Disable()
    if self.IdleConnection then self.IdleConnection:Disconnect() self.IdleConnection = nil end
    if self.Connection then task.cancel(self.Connection) self.Connection = nil end
end

function AutoRejoinController:Enable()
    if self.Connection then return end
    pcall(function() self.Connection = game:GetService("CoreGui").RobloxPromptGui.promptOverlay.ChildAdded:Connect(function() if Config.AutoRejoinEnabled then task.wait(Config.AutoRejoinDelay) TeleportService:Teleport(game.PlaceId, Player) end end) end)
end

function AutoRejoinController:Disable() if self.Connection then self.Connection:Disconnect() self.Connection = nil end end

function AutoFavoriteController:Enable()
    if self.Connection then return end
    self.Connection = task.spawn(function()
        while Config.AutoFavoriteEnabled do
            pcall(function()
                local inventory = Player:FindFirstChild("Inventory") or Player:FindFirstChild("Backpack")
                if inventory then
                    for _, item in pairs(inventory:GetChildren()) do
                        local rarity = item:FindFirstChild("Rarity") or item:GetAttribute("Rarity")
                        if rarity then
                            local rarityValue = typeof(rarity) == "Instance" and rarity.Value or rarity
                            local rarityIndex = table.find(RarityList, Config.FavoriteRarity) or 5
                            local itemRarityIndex = table.find(RarityList, rarityValue) or 1
                            if itemRarityIndex >= rarityIndex then
                                pcall(function() Net["RF/FavoriteItem"]:InvokeServer(item.Name) end)
                                Stats.FavoriteCount = Stats.FavoriteCount + 1
                            end
                        end
                    end
                end
            end)
            task.wait(2)
        end
    end)
end

function AutoFavoriteController:Disable() if self.Connection then task.cancel(self.Connection) self.Connection = nil end end

if Config.AntiAFKEnabled then AntiAFKController:Enable() end

-- NORMAL FISHING: Safe mode dengan timing dari config
local function ExecuteFishing()
    local success, err = pcall(function()
        if Config.MultiCast then
            local totalCasts = math.min(Config.CastAmount, 3)
            local completed = 0
            
            for i = 1, totalCasts do
                task.spawn(function()
                    pcall(function()
                        -- 1. Charge
                        Net["RF/ChargeFishingRod"]:InvokeServer()
                        task.wait(Config.ChargeTime)
                        
                        -- 2. Cast (start minigame)
                        local angle = Config.CastAngleMin + (math.random() * (Config.CastAngleMax - Config.CastAngleMin))
                        Net["RF/RequestFishingMinigameStarted"]:InvokeServer(angle, Config.CastPower, os.clock())
                        
                        -- 3. Wait (simulate minigame time)
                        task.wait(Config.ReelDelay)
                        
                        -- 4. Complete
                        Net["RE/FishingCompleted"]:FireServer()
                        task.wait(0.05)
                        Net["RE/FishingCompleted"]:FireServer()
                        
                        Stats.FishCaught = Stats.FishCaught + 1
                        completed = completed + 1
                    end)
                end)
                task.wait(0.3)
            end
            
            local timeout = Config.ChargeTime + Config.ReelDelay + 2
            local startTime = os.clock()
            while completed < totalCasts and (os.clock() - startTime) < timeout do
                task.wait(0.1)
            end
        else
            -- 1. Charge
            Net["RF/ChargeFishingRod"]:InvokeServer()
            task.wait(Config.ChargeTime)
            
            -- 2. Cast (start minigame)
            local angle = Config.CastAngleMin + (math.random() * (Config.CastAngleMax - Config.CastAngleMin))
            Net["RF/RequestFishingMinigameStarted"]:InvokeServer(angle, Config.CastPower, os.clock())
            
            -- 3. Wait (simulate minigame time - server validates this!)
            task.wait(Config.ReelDelay)
            
            -- 4. Complete
            Net["RE/FishingCompleted"]:FireServer()
            task.wait(0.05)
            Net["RE/FishingCompleted"]:FireServer()
            
            Stats.FishCaught = Stats.FishCaught + 1
        end
    end)
    if not success then warn("[Normal] Error:", err) end
end

local function StartAutoFishingLoop()
    while Config.BlatantMode do
        FishingActive = true
        ExecuteFishing()
        if Config.AutoSell and Stats.FishCaught > 0 and Stats.FishCaught % Config.AutoSellThreshold == 0 then 
            pcall(SellAllFish) 
        end
        FishingActive = false
        if Config.FishingDelay > 0 then task.wait(Config.FishingDelay) end
        task.wait(0.01)
    end
    FishingActive = false
end

-- ================================
-- DANUHUB PREMIUM GUI
-- ================================

local Theme = {
    Primary = Color3.fromRGB(99, 102, 241),
    PrimaryDark = Color3.fromRGB(79, 70, 229),
    PrimaryLight = Color3.fromRGB(129, 140, 248),
    Secondary = Color3.fromRGB(139, 92, 246),
    Accent = Color3.fromRGB(34, 211, 238),
    AccentBlue = Color3.fromRGB(59, 130, 246),
    Neon = Color3.fromRGB(168, 85, 247),
    NeonBlue = Color3.fromRGB(96, 165, 250),
    NeonCyan = Color3.fromRGB(34, 211, 238),
    Success = Color3.fromRGB(16, 185, 129),
    Danger = Color3.fromRGB(239, 68, 68),
    Warning = Color3.fromRGB(245, 158, 11),
    
    BgDark = Color3.fromRGB(15, 15, 25),
    BgMedium = Color3.fromRGB(22, 22, 35),
    BgLight = Color3.fromRGB(32, 32, 50),
    BgCard = Color3.fromRGB(28, 28, 45),
    BgSidebar = Color3.fromRGB(18, 18, 30),
    BgTransparent = Color3.fromRGB(20, 20, 35),
    
    TextPrimary = Color3.fromRGB(255, 255, 255),
    TextSecondary = Color3.fromRGB(180, 180, 200),
    TextMuted = Color3.fromRGB(120, 120, 150),
}

local function CreateTween(obj, props, duration, style, direction)
    return TweenService:Create(obj, TweenInfo.new(duration or 0.3, style or Enum.EasingStyle.Quart, direction or Enum.EasingDirection.Out), props)
end

local function AddHoverEffect(button, normalColor, hoverColor)
    button.MouseEnter:Connect(function()
        CreateTween(button, {BackgroundColor3 = hoverColor}, 0.2):Play()
    end)
    button.MouseLeave:Connect(function()
        CreateTween(button, {BackgroundColor3 = normalColor}, 0.2):Play()
    end)
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DanuHubPremium"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 450, 0, 320)
MainFrame.Position = UDim2.new(0.5, -225, 0.5, -160)
MainFrame.BackgroundColor3 = Theme.BgDark
MainFrame.BackgroundTransparency = 0.05
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Theme.Primary
MainStroke.Thickness = 1.5
MainStroke.Transparency = 0.5

local GlowEffect = Instance.new("ImageLabel", MainFrame)
GlowEffect.Name = "Glow"
GlowEffect.Size = UDim2.new(1, 60, 1, 60)
GlowEffect.Position = UDim2.new(0, -30, 0, -30)
GlowEffect.BackgroundTransparency = 1
GlowEffect.Image = "rbxassetid://6014261993"
GlowEffect.ImageColor3 = Theme.Primary
GlowEffect.ImageTransparency = 0.85
GlowEffect.ScaleType = Enum.ScaleType.Slice
GlowEffect.SliceCenter = Rect.new(49, 49, 450, 450)
GlowEffect.ZIndex = 0

-- Resize Handles
local MIN_SIZE = Vector2.new(350, 280)
local MAX_SIZE = Vector2.new(800, 500)

local function CreateResizeHandle(name, size, position, cursor)
    local handle = Instance.new("TextButton", MainFrame)
    handle.Name = "Resize_" .. name
    handle.Size = size
    handle.Position = position
    handle.BackgroundTransparency = 1
    handle.Text = ""
    handle.ZIndex = 10
    handle.AutoButtonColor = false
    return handle
end

-- Right edge
local ResizeRight = CreateResizeHandle("Right", UDim2.new(0, 8, 1, -20), UDim2.new(1, -4, 0, 10))
-- Bottom edge
local ResizeBottom = CreateResizeHandle("Bottom", UDim2.new(1, -20, 0, 8), UDim2.new(0, 10, 1, -4))
-- Corner (bottom-right)
local ResizeCorner = CreateResizeHandle("Corner", UDim2.new(0, 16, 0, 16), UDim2.new(1, -12, 1, -12))
-- Left edge
local ResizeLeft = CreateResizeHandle("Left", UDim2.new(0, 8, 1, -20), UDim2.new(0, -4, 0, 10))
-- Top edge (below title bar)
local ResizeTop = CreateResizeHandle("Top", UDim2.new(1, -20, 0, 8), UDim2.new(0, 10, 0, -4))

-- Corner indicator (visual)
local CornerIcon = Instance.new("ImageLabel", ResizeCorner)
CornerIcon.Size = UDim2.new(0, 12, 0, 12)
CornerIcon.Position = UDim2.new(0.5, -6, 0.5, -6)
CornerIcon.BackgroundTransparency = 1
CornerIcon.Image = "rbxassetid://3926305904"
CornerIcon.ImageRectOffset = Vector2.new(284, 524)
CornerIcon.ImageRectSize = Vector2.new(36, 36)
CornerIcon.ImageColor3 = Theme.TextMuted
CornerIcon.ImageTransparency = 0.5
CornerIcon.ZIndex = 11

local function SetupResize(handle, resizeX, resizeY, fromRight, fromBottom)
    local resizing = false
    local startPos, startSize, startFramePos
    
    handle.MouseButton1Down:Connect(function()
        resizing = true
        startPos = UserInputService:GetMouseLocation()
        startSize = MainFrame.AbsoluteSize
        startFramePos = MainFrame.AbsolutePosition
    end)
    
    handle.MouseEnter:Connect(function()
        CornerIcon.ImageTransparency = 0.2
    end)
    
    handle.MouseLeave:Connect(function()
        if not resizing then
            CornerIcon.ImageTransparency = 0.5
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            resizing = false
            CornerIcon.ImageTransparency = 0.5
        end
    end)
    
    RunService.RenderStepped:Connect(function()
        if resizing then
            local mousePos = UserInputService:GetMouseLocation()
            local delta = mousePos - startPos
            
            local newWidth = startSize.X
            local newHeight = startSize.Y
            local newPosX = MainFrame.Position.X.Offset
            local newPosY = MainFrame.Position.Y.Offset
            
            if resizeX then
                if fromRight then
                    newWidth = math.clamp(startSize.X + delta.X, MIN_SIZE.X, MAX_SIZE.X)
                else
                    local widthDelta = -delta.X
                    newWidth = math.clamp(startSize.X + widthDelta, MIN_SIZE.X, MAX_SIZE.X)
                    local actualDelta = newWidth - startSize.X
                    newPosX = MainFrame.Position.X.Offset - actualDelta/2
                end
            end
            
            if resizeY then
                if fromBottom then
                    newHeight = math.clamp(startSize.Y + delta.Y, MIN_SIZE.Y, MAX_SIZE.Y)
                else
                    local heightDelta = -delta.Y
                    newHeight = math.clamp(startSize.Y + heightDelta, MIN_SIZE.Y, MAX_SIZE.Y)
                    local actualDelta = newHeight - startSize.Y
                    newPosY = MainFrame.Position.Y.Offset - actualDelta/2
                end
            end
            
            MainFrame.Size = UDim2.new(0, newWidth, 0, newHeight)
            MainFrame.Position = UDim2.new(0.5, -newWidth/2, 0.5, -newHeight/2)
        end
    end)
end

SetupResize(ResizeRight, true, false, true, false)
SetupResize(ResizeBottom, false, true, false, true)
SetupResize(ResizeCorner, true, true, true, true)
SetupResize(ResizeLeft, true, false, false, false)
SetupResize(ResizeTop, false, true, false, false)

-- Sidebar
local Sidebar = Instance.new("Frame", MainFrame)
Sidebar.Name = "Sidebar"
Sidebar.Size = UDim2.new(0, 140, 1, 0)
Sidebar.BackgroundColor3 = Theme.BgSidebar
Sidebar.BorderSizePixel = 0
Sidebar.ZIndex = 2
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 12)

local SidebarInner = Instance.new("Frame", Sidebar)
SidebarInner.Size = UDim2.new(1, 0, 1, 0)
SidebarInner.BackgroundColor3 = Theme.BgSidebar
SidebarInner.BorderSizePixel = 0
SidebarInner.ZIndex = 2

local SidebarCornerFix = Instance.new("Frame", SidebarInner)
SidebarCornerFix.Size = UDim2.new(0, 20, 1, 0)
SidebarCornerFix.Position = UDim2.new(1, -20, 0, 0)
SidebarCornerFix.BackgroundColor3 = Theme.BgSidebar
SidebarCornerFix.BorderSizePixel = 0
SidebarCornerFix.ZIndex = 2

-- Logo
local LogoContainer = Instance.new("Frame", Sidebar)
LogoContainer.Size = UDim2.new(1, 0, 0, 50)
LogoContainer.BackgroundTransparency = 1
LogoContainer.ZIndex = 3

local LogoText = Instance.new("TextLabel", LogoContainer)
LogoText.Size = UDim2.new(1, -10, 0, 22)
LogoText.Position = UDim2.new(0, 8, 0, 8)
LogoText.BackgroundTransparency = 1
LogoText.Text = "DanuHub"
LogoText.TextColor3 = Theme.TextPrimary
LogoText.TextSize = 14
LogoText.Font = Enum.Font.GothamBlack
LogoText.TextXAlignment = Enum.TextXAlignment.Left
LogoText.ZIndex = 4

local LogoSub = Instance.new("TextLabel", LogoContainer)
LogoSub.Size = UDim2.new(1, -10, 0, 12)
LogoSub.Position = UDim2.new(0, 8, 0, 30)
LogoSub.BackgroundTransparency = 1
LogoSub.Text = "Premium v1.0.1"
LogoSub.TextColor3 = Theme.Neon
LogoSub.TextSize = 9
LogoSub.Font = Enum.Font.GothamMedium
LogoSub.TextXAlignment = Enum.TextXAlignment.Left
LogoSub.ZIndex = 4

-- Menu Items Container
local MenuContainer = Instance.new("ScrollingFrame", Sidebar)
MenuContainer.Size = UDim2.new(1, -10, 1, -100)
MenuContainer.Position = UDim2.new(0, 5, 0, 55)
MenuContainer.BackgroundTransparency = 1
MenuContainer.ScrollBarThickness = 0
MenuContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
MenuContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
MenuContainer.ZIndex = 3

local MenuLayout = Instance.new("UIListLayout", MenuContainer)
MenuLayout.Padding = UDim.new(0, 5)
MenuLayout.SortOrder = Enum.SortOrder.LayoutOrder

local MenuItems = {
    {name = "Developer Info", icon = "rbxassetid://7733960981", page = "DevInfo", isMain = true, order = 1},
    {name = "Server List", icon = "rbxassetid://7734053495", page = "ServerList", isMain = true, order = 2},
    {name = "All Menu Here", icon = "rbxassetid://7733717447", page = nil, isMain = true, isExpander = true, order = 3},
    {name = "  Auto Fishing", icon = "rbxassetid://7733692590", page = "AutoFishing", isMain = false, parent = "All Menu Here", order = 4},
    {name = "  Auto Favorite", icon = "rbxassetid://7733964053", page = "AutoFavorite", isMain = false, parent = "All Menu Here", order = 5},
    {name = "  Weather Event", icon = "rbxassetid://7734053495", page = "Weather", isMain = false, parent = "All Menu Here", order = 6},
    {name = "  Cheat Menu", icon = "rbxassetid://7733717447", page = "AllMenu", isMain = false, parent = "All Menu Here", order = 7},
    {name = "  Performance", icon = "rbxassetid://7743878857", page = "Performance", isMain = false, parent = "All Menu Here", order = 8},
}

local MenuButtons = {}
local SubMenuButtons = {}
local Pages = {}
local CurrentPage = "DevInfo"
local SubMenuExpanded = false

local function CreateMenuButton(data, index)
    local btn = Instance.new("TextButton", MenuContainer)
    btn.Name = data.name
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = (data.page == "DevInfo") and Theme.Primary or Theme.BgLight
    btn.BackgroundTransparency = (data.page == "DevInfo") and 0 or 0.5
    btn.Text = ""
    btn.LayoutOrder = data.order or index
    btn.ZIndex = 4
    btn.Visible = data.isMain or false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    
    local iconLabel = Instance.new("ImageLabel", btn)
    iconLabel.Size = UDim2.new(0, 16, 0, 16)
    iconLabel.Position = UDim2.new(0, 8, 0.5, -8)
    iconLabel.BackgroundTransparency = 1
    iconLabel.Image = data.icon
    iconLabel.ImageColor3 = Theme.TextPrimary
    iconLabel.ZIndex = 5
    
    local textLabel = Instance.new("TextLabel", btn)
    textLabel.Size = UDim2.new(1, -35, 1, 0)
    textLabel.Position = UDim2.new(0, 28, 0, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = data.name
    textLabel.TextColor3 = Theme.TextPrimary
    textLabel.TextSize = 10
    textLabel.Font = Enum.Font.GothamMedium
    textLabel.TextXAlignment = Enum.TextXAlignment.Left
    textLabel.ZIndex = 5
    
    if data.isExpander then
        local arrow = Instance.new("TextLabel", btn)
        arrow.Name = "Arrow"
        arrow.Size = UDim2.new(0, 20, 0, 20)
        arrow.Position = UDim2.new(1, -25, 0.5, -10)
        arrow.BackgroundTransparency = 1
        arrow.Text = ">"
        arrow.TextColor3 = Theme.TextPrimary
        arrow.TextSize = 14
        arrow.Font = Enum.Font.GothamBold
        arrow.ZIndex = 5
    end
    
    if data.page then
        MenuButtons[data.page] = btn
    end
    if data.parent then
        if not SubMenuButtons[data.parent] then
            SubMenuButtons[data.parent] = {}
        end
        table.insert(SubMenuButtons[data.parent], btn)
    end
    
    return btn, data
end

local AllMenuButtons = {}
for i, item in ipairs(MenuItems) do
    local btn, data = CreateMenuButton(item, i)
    table.insert(AllMenuButtons, {btn = btn, data = data})
end

for _, menuData in ipairs(AllMenuButtons) do
    local btn = menuData.btn
    local data = menuData.data
    
    btn.MouseButton1Click:Connect(function()
        if data.isExpander then
            SubMenuExpanded = not SubMenuExpanded
            local arrow = btn:FindFirstChild("Arrow")
            if arrow then
                arrow.Text = SubMenuExpanded and "v" or ">"
            end
            if SubMenuButtons[data.name] then
                for _, subBtn in ipairs(SubMenuButtons[data.name]) do
                    subBtn.Visible = SubMenuExpanded
                end
            end
        elseif data.page then
            for pageName, pageBtn in pairs(MenuButtons) do
                local isActive = pageName == data.page
                CreateTween(pageBtn, {
                    BackgroundColor3 = isActive and Theme.Primary or Theme.BgLight,
                    BackgroundTransparency = isActive and 0 or 0.5
                }, 0.2):Play()
            end
            for pageName, pageFrame in pairs(Pages) do
                pageFrame.Visible = pageName == data.page
            end
            CurrentPage = data.page
            PageTitle.Text = data.name:gsub("^%s+", "")
        end
    end)
end

-- User Profile at bottom
local ProfileContainer = Instance.new("Frame", Sidebar)
ProfileContainer.Size = UDim2.new(1, -10, 0, 40)
ProfileContainer.Position = UDim2.new(0, 5, 1, -45)
ProfileContainer.BackgroundColor3 = Theme.BgLight
ProfileContainer.BackgroundTransparency = 0.5
ProfileContainer.ZIndex = 3
Instance.new("UICorner", ProfileContainer).CornerRadius = UDim.new(0, 8)

local ProfileImage = Instance.new("ImageLabel", ProfileContainer)
ProfileImage.Size = UDim2.new(0, 28, 0, 28)
ProfileImage.Position = UDim2.new(0, 6, 0.5, -14)
ProfileImage.BackgroundColor3 = Theme.Primary
ProfileImage.ZIndex = 4
Instance.new("UICorner", ProfileImage).CornerRadius = UDim.new(1, 0)

pcall(function()
    local userId = Player.UserId
    local thumbType = Enum.ThumbnailType.HeadShot
    local thumbSize = Enum.ThumbnailSize.Size100x100
    local content = Players:GetUserThumbnailAsync(userId, thumbType, thumbSize)
    ProfileImage.Image = content
end)

local ProfileName = Instance.new("TextLabel", ProfileContainer)
ProfileName.Size = UDim2.new(1, -45, 0, 16)
ProfileName.Position = UDim2.new(0, 38, 0, 5)
ProfileName.BackgroundTransparency = 1
ProfileName.Text = Player.Name
ProfileName.TextColor3 = Theme.TextPrimary
ProfileName.TextSize = 9
ProfileName.Font = Enum.Font.GothamBold
ProfileName.TextXAlignment = Enum.TextXAlignment.Left
ProfileName.TextTruncate = Enum.TextTruncate.AtEnd
ProfileName.ZIndex = 4

local ProfileStatus = Instance.new("TextLabel", ProfileContainer)
ProfileStatus.Size = UDim2.new(1, -45, 0, 12)
ProfileStatus.Position = UDim2.new(0, 38, 0, 22)
ProfileStatus.BackgroundTransparency = 1
ProfileStatus.Text = "Premium"
ProfileStatus.TextColor3 = Theme.Neon
ProfileStatus.TextSize = 8
ProfileStatus.Font = Enum.Font.Gotham
ProfileStatus.TextXAlignment = Enum.TextXAlignment.Left
ProfileStatus.ZIndex = 4

-- Content Area
local ContentArea = Instance.new("Frame", MainFrame)
ContentArea.Name = "Content"
ContentArea.Size = UDim2.new(1, -150, 1, -40)
ContentArea.Position = UDim2.new(0, 145, 0, 35)
ContentArea.BackgroundTransparency = 1
ContentArea.ZIndex = 2

-- Top Bar
local TopBar = Instance.new("Frame", MainFrame)
TopBar.Size = UDim2.new(1, -140, 0, 32)
TopBar.Position = UDim2.new(0, 140, 0, 0)
TopBar.BackgroundTransparency = 1
TopBar.ZIndex = 3

local PageTitle = Instance.new("TextLabel", TopBar)
PageTitle.Size = UDim2.new(0.5, 0, 1, 0)
PageTitle.Position = UDim2.new(0, 10, 0, 0)
PageTitle.BackgroundTransparency = 1
PageTitle.Text = "Developer Info"
PageTitle.TextColor3 = Theme.TextPrimary
PageTitle.TextSize = 12
PageTitle.Font = Enum.Font.GothamBold
PageTitle.TextXAlignment = Enum.TextXAlignment.Left
PageTitle.ZIndex = 4

-- Window Controls
local ControlsContainer = Instance.new("Frame", TopBar)
ControlsContainer.Size = UDim2.new(0, 70, 0, 24)
ControlsContainer.Position = UDim2.new(1, -75, 0.5, -12)
ControlsContainer.BackgroundTransparency = 1
ControlsContainer.ZIndex = 4

local function CreateControlBtn(name, text, pos, color)
    local btn = Instance.new("TextButton", ControlsContainer)
    btn.Name = name
    btn.Size = UDim2.new(0, 20, 0, 20)
    btn.Position = pos
    btn.BackgroundColor3 = color
    btn.BackgroundTransparency = 0.3
    btn.Text = text
    btn.TextColor3 = Theme.TextPrimary
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamBold
    btn.ZIndex = 5
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    AddHoverEffect(btn, color, Color3.new(math.min(color.R * 1.3, 1), math.min(color.G * 1.3, 1), math.min(color.B * 1.3, 1)))
    return btn
end

local MinBtn = CreateControlBtn("Min", "-", UDim2.new(0, 0, 0, 0), Theme.Warning)
local MaxBtn = CreateControlBtn("Max", "+", UDim2.new(0, 24, 0, 0), Theme.Success)
local CloseBtn = CreateControlBtn("Close", "X", UDim2.new(0, 48, 0, 0), Theme.Danger)

-- Page Creation Function
local function CreatePage(name)
    local page = Instance.new("ScrollingFrame", ContentArea)
    page.Name = name
    page.Size = UDim2.new(1, -10, 1, -10)
    page.Position = UDim2.new(0, 5, 0, 5)
    page.BackgroundColor3 = Theme.BgCard
    page.BackgroundTransparency = 0.3
    page.ScrollBarThickness = 5
    page.ScrollBarImageColor3 = Theme.Primary
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.ZIndex = 3
    page.BorderSizePixel = 0
    page.ScrollingDirection = Enum.ScrollingDirection.Y
    Instance.new("UICorner", page).CornerRadius = UDim.new(0, 12)
    
    local padding = Instance.new("UIPadding", page)
    padding.PaddingTop = UDim.new(0, 15)
    padding.PaddingBottom = UDim.new(0, 20)
    padding.PaddingLeft = UDim.new(0, 15)
    padding.PaddingRight = UDim.new(0, 15)
    
    local layout = Instance.new("UIListLayout", page)
    layout.Padding = UDim.new(0, 10)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    
    Pages[name] = page
    return page
end

-- Slider Creator dengan Text Input
local function CreateSlider(parent, name, defaultVal, minVal, maxVal, configKey, order)
    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(1, 0, 0, 65)
    container.BackgroundColor3 = Theme.BgLight
    container.BackgroundTransparency = 0.3
    container.LayoutOrder = order
    container.ZIndex = 4
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 10)
    
    local containerStroke = Instance.new("UIStroke", container)
    containerStroke.Color = Theme.Primary
    containerStroke.Thickness = 1
    containerStroke.Transparency = 1
    
    -- Hover detection frame (invisible)
    local hoverDetect = Instance.new("TextButton", container)
    hoverDetect.Size = UDim2.new(1, 0, 1, 0)
    hoverDetect.BackgroundTransparency = 1
    hoverDetect.Text = ""
    hoverDetect.ZIndex = 3
    
    hoverDetect.MouseEnter:Connect(function()
        CreateTween(container, {BackgroundTransparency = 0.1}, 0.15):Play()
        CreateTween(containerStroke, {Transparency = 0.5}, 0.15):Play()
    end)
    
    hoverDetect.MouseLeave:Connect(function()
        CreateTween(container, {BackgroundTransparency = 0.3}, 0.15):Play()
        CreateTween(containerStroke, {Transparency = 1}, 0.15):Play()
    end)
    
    local label = Instance.new("TextLabel", container)
    label.Size = UDim2.new(1, -80, 0, 20)
    label.Position = UDim2.new(0, 12, 0, 8)
    label.BackgroundTransparency = 1
    label.Text = name .. " (Default: " .. defaultVal .. ")"
    label.TextColor3 = Theme.TextSecondary
    label.TextSize = 11
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 5
    
    -- Text Input untuk edit manual (menggantikan valueLabel)
    local valueInput = Instance.new("TextBox", container)
    valueInput.Size = UDim2.new(0, 55, 0, 22)
    valueInput.Position = UDim2.new(1, -67, 0, 6)
    valueInput.BackgroundColor3 = Theme.BgDark
    valueInput.BackgroundTransparency = 0.5
    valueInput.Text = tostring(Config[configKey])
    valueInput.TextColor3 = Theme.NeonCyan
    valueInput.TextSize = 12
    valueInput.Font = Enum.Font.GothamBold
    valueInput.TextXAlignment = Enum.TextXAlignment.Center
    valueInput.ZIndex = 6
    valueInput.ClearTextOnFocus = false
    Instance.new("UICorner", valueInput).CornerRadius = UDim.new(0, 6)
    
    local inputStroke = Instance.new("UIStroke", valueInput)
    inputStroke.Color = Theme.NeonCyan
    inputStroke.Thickness = 1
    inputStroke.Transparency = 0.7
    
    local sliderBg = Instance.new("TextButton", container)
    sliderBg.Size = UDim2.new(1, -24, 0, 12)
    sliderBg.Position = UDim2.new(0, 12, 0, 40)
    sliderBg.BackgroundColor3 = Theme.BgDark
    sliderBg.Text = ""
    sliderBg.AutoButtonColor = false
    sliderBg.ZIndex = 5
    Instance.new("UICorner", sliderBg).CornerRadius = UDim.new(1, 0)
    
    local sliderFill = Instance.new("Frame", sliderBg)
    local percent = math.clamp((Config[configKey] - minVal) / (maxVal - minVal), 0, 1)
    sliderFill.Size = UDim2.new(percent, 0, 1, 0)
    sliderFill.BackgroundColor3 = Theme.AccentBlue
    sliderFill.ZIndex = 6
    Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(1, 0)
    
    local fillGrad = Instance.new("UIGradient", sliderFill)
    fillGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.Primary),
        ColorSequenceKeypoint.new(1, Theme.NeonCyan)
    })
    
    local knob = Instance.new("TextButton", sliderBg)
    knob.Size = UDim2.new(0, 20, 0, 20)
    knob.Position = UDim2.new(percent, -10, 0.5, -10)
    knob.BackgroundColor3 = Theme.TextPrimary
    knob.Text = ""
    knob.AutoButtonColor = false
    knob.ZIndex = 8
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    
    local knobStroke = Instance.new("UIStroke", knob)
    knobStroke.Color = Theme.NeonCyan
    knobStroke.Thickness = 2
    knobStroke.Transparency = 0.3
    
    local dragging = false
    
    local function updateSlider(inputX)
        local sliderPos = sliderBg.AbsolutePosition.X
        local sliderSize = sliderBg.AbsoluteSize.X
        local newPercent = math.clamp((inputX - sliderPos) / sliderSize, 0, 1)
        local value = minVal + (maxVal - minVal) * newPercent
        value = math.floor(value * 100) / 100
        Config[configKey] = value
        valueInput.Text = tostring(value)
        sliderFill.Size = UDim2.new(newPercent, 0, 1, 0)
        knob.Position = UDim2.new(newPercent, -10, 0.5, -10)
    end
    
    local function updateFromValue(value)
        value = math.clamp(value, minVal, maxVal)
        value = math.floor(value * 100) / 100
        Config[configKey] = value
        valueInput.Text = tostring(value)
        local newPercent = (value - minVal) / (maxVal - minVal)
        sliderFill.Size = UDim2.new(newPercent, 0, 1, 0)
        knob.Position = UDim2.new(newPercent, -10, 0.5, -10)
    end
    
    -- Text Input events
    valueInput.Focused:Connect(function()
        CreateTween(inputStroke, {Transparency = 0, Color = Theme.Primary}, 0.2):Play()
    end)
    
    valueInput.FocusLost:Connect(function(enterPressed)
        CreateTween(inputStroke, {Transparency = 0.7, Color = Theme.NeonCyan}, 0.2):Play()
        local num = tonumber(valueInput.Text)
        if num then
            updateFromValue(num)
        else
            valueInput.Text = tostring(Config[configKey])
        end
    end)
    
    sliderBg.MouseButton1Down:Connect(function()
        dragging = true
        local mouse = Players.LocalPlayer:GetMouse()
        updateSlider(mouse.X)
    end)
    
    knob.MouseButton1Down:Connect(function()
        dragging = true
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local mouse = Players.LocalPlayer:GetMouse()
            updateSlider(mouse.X)
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    return container
end

-- Toggle Button Creator dengan Animasi
local function CreateToggle(parent, name, configKey, order, callback)
    local container = Instance.new("TextButton", parent)
    container.Size = UDim2.new(1, 0, 0, 48)
    container.BackgroundColor3 = Theme.BgLight
    container.BackgroundTransparency = 0.3
    container.LayoutOrder = order
    container.ZIndex = 4
    container.Text = ""
    container.AutoButtonColor = false
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 10)
    
    local containerStroke = Instance.new("UIStroke", container)
    containerStroke.Color = Theme.Primary
    containerStroke.Thickness = 1
    containerStroke.Transparency = 1
    
    local label = Instance.new("TextLabel", container)
    label.Size = UDim2.new(1, -80, 1, 0)
    label.Position = UDim2.new(0, 15, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Theme.TextPrimary
    label.TextSize = 13
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 5
    
    local toggleBg = Instance.new("Frame", container)
    toggleBg.Size = UDim2.new(0, 52, 0, 28)
    toggleBg.Position = UDim2.new(1, -65, 0.5, -14)
    toggleBg.BackgroundColor3 = Config[configKey] and Theme.Success or Theme.BgDark
    toggleBg.ZIndex = 5
    Instance.new("UICorner", toggleBg).CornerRadius = UDim.new(1, 0)
    
    local toggleKnob = Instance.new("Frame", toggleBg)
    toggleKnob.Size = UDim2.new(0, 22, 0, 22)
    toggleKnob.Position = Config[configKey] and UDim2.new(1, -25, 0.5, -11) or UDim2.new(0, 3, 0.5, -11)
    toggleKnob.BackgroundColor3 = Theme.TextPrimary
    toggleKnob.ZIndex = 6
    Instance.new("UICorner", toggleKnob).CornerRadius = UDim.new(1, 0)
    
    -- Hover animation
    container.MouseEnter:Connect(function()
        CreateTween(container, {BackgroundTransparency = 0.1}, 0.15):Play()
        CreateTween(containerStroke, {Transparency = 0.5}, 0.15):Play()
    end)
    
    container.MouseLeave:Connect(function()
        CreateTween(container, {BackgroundTransparency = 0.3}, 0.15):Play()
        CreateTween(containerStroke, {Transparency = 1}, 0.15):Play()
    end)
    
    container.MouseButton1Click:Connect(function()
        -- Click animation
        CreateTween(container, {Size = UDim2.new(0.98, 0, 0, 45)}, 0.08):Play()
        task.wait(0.08)
        CreateTween(container, {Size = UDim2.new(1, 0, 0, 48)}, 0.08):Play()
        
        Config[configKey] = not Config[configKey]
        CreateTween(toggleBg, {BackgroundColor3 = Config[configKey] and Theme.Success or Theme.BgDark}, 0.2):Play()
        CreateTween(toggleKnob, {Position = Config[configKey] and UDim2.new(1, -25, 0.5, -11) or UDim2.new(0, 3, 0.5, -11)}, 0.2):Play()
        if callback then callback(Config[configKey]) end
    end)
    
    return container
end

-- Action Button Creator dengan Animasi
local function CreateActionBtn(parent, name, order, color, callback)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(1, 0, 0, 48)
    btn.BackgroundColor3 = color or Theme.Primary
    btn.Text = name
    btn.TextColor3 = Theme.TextPrimary
    btn.TextSize = 14
    btn.Font = Enum.Font.GothamBold
    btn.LayoutOrder = order
    btn.ZIndex = 5
    btn.AutoButtonColor = false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
    
    local btnStroke = Instance.new("UIStroke", btn)
    btnStroke.Color = Theme.TextPrimary
    btnStroke.Thickness = 1
    btnStroke.Transparency = 0.8
    
    local originalColor = color or Theme.Primary
    
    -- Hover animation
    btn.MouseEnter:Connect(function()
        CreateTween(btn, {BackgroundColor3 = originalColor:Lerp(Color3.new(1,1,1), 0.15)}, 0.15):Play()
        CreateTween(btnStroke, {Transparency = 0.3}, 0.15):Play()
    end)
    
    btn.MouseLeave:Connect(function()
        CreateTween(btn, {BackgroundColor3 = originalColor}, 0.15):Play()
        CreateTween(btnStroke, {Transparency = 0.8}, 0.15):Play()
    end)
    
    btn.MouseButton1Click:Connect(function()
        -- Click animation
        CreateTween(btn, {Size = UDim2.new(0.98, 0, 0, 44)}, 0.08):Play()
        task.wait(0.08)
        CreateTween(btn, {Size = UDim2.new(1, 0, 0, 48)}, 0.08):Play()
        if callback then callback() end
    end)
    
    return btn
end

-- Section Title Creator
local function CreateSection(parent, title, order)
    local section = Instance.new("TextLabel", parent)
    section.Size = UDim2.new(1, 0, 0, 30)
    section.BackgroundTransparency = 1
    section.Text = title
    section.TextColor3 = Theme.Neon
    section.TextSize = 14
    section.Font = Enum.Font.GothamBold
    section.TextXAlignment = Enum.TextXAlignment.Left
    section.LayoutOrder = order
    section.ZIndex = 4
    return section
end

-- Info Card Creator
local function CreateInfoCard(parent, title, value, order)
    local card = Instance.new("Frame", parent)
    card.Size = UDim2.new(0.48, 0, 0, 70)
    card.BackgroundColor3 = Theme.BgLight
    card.BackgroundTransparency = 0.3
    card.LayoutOrder = order
    card.ZIndex = 4
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
    
    local titleLabel = Instance.new("TextLabel", card)
    titleLabel.Size = UDim2.new(1, -20, 0, 20)
    titleLabel.Position = UDim2.new(0, 10, 0, 10)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = Theme.TextMuted
    titleLabel.TextSize = 11
    titleLabel.Font = Enum.Font.Gotham
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.ZIndex = 5
    
    local valueLabel = Instance.new("TextLabel", card)
    valueLabel.Name = "Value"
    valueLabel.Size = UDim2.new(1, -20, 0, 25)
    valueLabel.Position = UDim2.new(0, 10, 0, 35)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = value
    valueLabel.TextColor3 = Theme.TextPrimary
    valueLabel.TextSize = 16
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextXAlignment = Enum.TextXAlignment.Left
    valueLabel.ZIndex = 5
    
    return card
end

-- ==================== PAGES ====================

-- Developer Info Page
local DevInfoPage = CreatePage("DevInfo")
DevInfoPage.Visible = true

CreateSection(DevInfoPage, "Developer Information", 1)

local devCard = Instance.new("Frame", DevInfoPage)
devCard.Size = UDim2.new(1, 0, 0, 120)
devCard.BackgroundColor3 = Theme.BgLight
devCard.BackgroundTransparency = 0.3
devCard.LayoutOrder = 2
devCard.ZIndex = 4
Instance.new("UICorner", devCard).CornerRadius = UDim.new(0, 12)

local devAvatar = Instance.new("Frame", devCard)
devAvatar.Size = UDim2.new(0, 80, 0, 80)
devAvatar.Position = UDim2.new(0, 20, 0.5, -40)
devAvatar.BackgroundColor3 = Theme.Primary
devAvatar.ZIndex = 5
Instance.new("UICorner", devAvatar).CornerRadius = UDim.new(0, 12)

local devAvatarText = Instance.new("TextLabel", devAvatar)
devAvatarText.Size = UDim2.new(1, 0, 1, 0)
devAvatarText.BackgroundTransparency = 1
devAvatarText.Text = "D"
devAvatarText.TextColor3 = Theme.TextPrimary
devAvatarText.TextSize = 36
devAvatarText.Font = Enum.Font.GothamBlack
devAvatarText.ZIndex = 6

local devName = Instance.new("TextLabel", devCard)
devName.Size = UDim2.new(1, -130, 0, 25)
devName.Position = UDim2.new(0, 115, 0, 25)
devName.BackgroundTransparency = 1
devName.Text = "DANU"
devName.TextColor3 = Theme.TextPrimary
devName.TextSize = 18
devName.Font = Enum.Font.GothamBold
devName.TextXAlignment = Enum.TextXAlignment.Left
devName.ZIndex = 5

local devRole = Instance.new("TextLabel", devCard)
devRole.Size = UDim2.new(1, -130, 0, 18)
devRole.Position = UDim2.new(0, 115, 0, 50)
devRole.BackgroundTransparency = 1
devRole.Text = "Script Developer"
devRole.TextColor3 = Theme.Neon
devRole.TextSize = 12
devRole.Font = Enum.Font.GothamMedium
devRole.TextXAlignment = Enum.TextXAlignment.Left
devRole.ZIndex = 5

local devDesc = Instance.new("TextLabel", devCard)
devDesc.Size = UDim2.new(1, -130, 0, 30)
devDesc.Position = UDim2.new(0, 115, 0, 72)
devDesc.BackgroundTransparency = 1
devDesc.Text = "Creator of DanuHub Premium for Fish It"
devDesc.TextColor3 = Theme.TextSecondary
devDesc.TextSize = 11
devDesc.Font = Enum.Font.Gotham
devDesc.TextXAlignment = Enum.TextXAlignment.Left
devDesc.ZIndex = 5

CreateSection(DevInfoPage, "Script Information", 3)

local infoGrid = Instance.new("Frame", DevInfoPage)
infoGrid.Size = UDim2.new(1, 0, 0, 160)
infoGrid.BackgroundTransparency = 1
infoGrid.LayoutOrder = 4
infoGrid.ZIndex = 4

local gridLayout = Instance.new("UIGridLayout", infoGrid)
gridLayout.CellSize = UDim2.new(0.48, 0, 0, 70)
gridLayout.CellPadding = UDim2.new(0.04, 0, 0, 10)

CreateInfoCard(infoGrid, "Version", "1.0.1", 1)
CreateInfoCard(infoGrid, "Game", "Fish It", 2)
CreateInfoCard(infoGrid, "Status", "Active", 3)
CreateInfoCard(infoGrid, "Last Update", "28 Nov 2025", 4)

CreateSection(DevInfoPage, "Social Links", 5)

local discordBtn = Instance.new("TextButton", DevInfoPage)
discordBtn.Size = UDim2.new(1, 0, 0, 50)
discordBtn.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
discordBtn.Text = "Join Discord Server"
discordBtn.TextColor3 = Theme.TextPrimary
discordBtn.TextSize = 14
discordBtn.Font = Enum.Font.GothamBold
discordBtn.LayoutOrder = 6
discordBtn.ZIndex = 5
discordBtn.AutoButtonColor = true
Instance.new("UICorner", discordBtn).CornerRadius = UDim.new(0, 10)

local discordIcon = Instance.new("ImageLabel", discordBtn)
discordIcon.Size = UDim2.new(0, 24, 0, 24)
discordIcon.Position = UDim2.new(0, 15, 0.5, -12)
discordIcon.BackgroundTransparency = 1
discordIcon.Image = "rbxassetid://7733756006"
discordIcon.ImageColor3 = Theme.TextPrimary
discordIcon.ZIndex = 6

discordBtn.MouseButton1Click:Connect(function()
    if setclipboard then
        setclipboard("https://discord.gg/fg6T76dJ")
    end
    if request or http_request or syn and syn.request then
        local httpFunc = request or http_request or (syn and syn.request)
        pcall(function()
            httpFunc({Url = "https://discord.gg/fg6T76dJ", Method = "GET"})
        end)
    end
    pcall(function()
        game:GetService("GuiService"):OpenBrowserWindow("https://discord.gg/fg6T76dJ")
    end)
end)

-- Server List Page
local ServerListPage = CreatePage("ServerList")

CreateSection(ServerListPage, "Available Servers", 1)

local serverRefreshBtn = CreateActionBtn(ServerListPage, "Refresh Server List", 2, Theme.AccentBlue, function()
    -- Refresh server list logic
end)

for i = 1, 5 do
    local serverCard = Instance.new("Frame", ServerListPage)
    serverCard.Size = UDim2.new(1, 0, 0, 60)
    serverCard.BackgroundColor3 = Theme.BgLight
    serverCard.BackgroundTransparency = 0.3
    serverCard.LayoutOrder = 2 + i
    serverCard.ZIndex = 4
    Instance.new("UICorner", serverCard).CornerRadius = UDim.new(0, 10)
    
    local serverIcon = Instance.new("Frame", serverCard)
    serverIcon.Size = UDim2.new(0, 40, 0, 40)
    serverIcon.Position = UDim2.new(0, 10, 0.5, -20)
    serverIcon.BackgroundColor3 = Theme.Success
    serverIcon.ZIndex = 5
    Instance.new("UICorner", serverIcon).CornerRadius = UDim.new(1, 0)
    
    local serverNum = Instance.new("TextLabel", serverIcon)
    serverNum.Size = UDim2.new(1, 0, 1, 0)
    serverNum.BackgroundTransparency = 1
    serverNum.Text = tostring(i)
    serverNum.TextColor3 = Theme.TextPrimary
    serverNum.TextSize = 16
    serverNum.Font = Enum.Font.GothamBold
    serverNum.ZIndex = 6
    
    local serverName = Instance.new("TextLabel", serverCard)
    serverName.Size = UDim2.new(0.5, -60, 0, 20)
    serverName.Position = UDim2.new(0, 60, 0, 12)
    serverName.BackgroundTransparency = 1
    serverName.Text = "Server #" .. tostring(math.random(1000, 9999))
    serverName.TextColor3 = Theme.TextPrimary
    serverName.TextSize = 13
    serverName.Font = Enum.Font.GothamBold
    serverName.TextXAlignment = Enum.TextXAlignment.Left
    serverName.ZIndex = 5
    
    local serverPlayers = Instance.new("TextLabel", serverCard)
    serverPlayers.Size = UDim2.new(0.5, -60, 0, 16)
    serverPlayers.Position = UDim2.new(0, 60, 0, 32)
    serverPlayers.BackgroundTransparency = 1
    serverPlayers.Text = tostring(math.random(5, 20)) .. "/20 Players"
    serverPlayers.TextColor3 = Theme.TextSecondary
    serverPlayers.TextSize = 11
    serverPlayers.Font = Enum.Font.Gotham
    serverPlayers.TextXAlignment = Enum.TextXAlignment.Left
    serverPlayers.ZIndex = 5
    
    local joinBtn = Instance.new("TextButton", serverCard)
    joinBtn.Size = UDim2.new(0, 70, 0, 30)
    joinBtn.Position = UDim2.new(1, -80, 0.5, -15)
    joinBtn.BackgroundColor3 = Theme.Primary
    joinBtn.Text = "Join"
    joinBtn.TextColor3 = Theme.TextPrimary
    joinBtn.TextSize = 11
    joinBtn.Font = Enum.Font.GothamBold
    joinBtn.ZIndex = 5
    Instance.new("UICorner", joinBtn).CornerRadius = UDim.new(0, 8)
    
    joinBtn.MouseButton1Click:Connect(function()
        pcall(function()
            TeleportService:Teleport(game.PlaceId, Player)
        end)
    end)
end

-- All Menu Page
local AllMenuPage = CreatePage("AllMenu")

CreateSection(AllMenuPage, "Movement Cheats", 1)

CreateToggle(AllMenuPage, "Fly Mode", "FlyEnabled", 2, function(enabled)
    if enabled then FlyController:Enable() else FlyController:Disable() end
end)

CreateToggle(AllMenuPage, "Speed Hack", "SpeedEnabled", 3, function(enabled)
    updateSpeed()
end)

CreateToggle(AllMenuPage, "Noclip", "NoclipEnabled", 4, function(enabled)
    if enabled then NoclipController:Enable() else NoclipController:Disable() end
end)

CreateSection(AllMenuPage, "Movement Settings", 5)
CreateSlider(AllMenuPage, "Fly Speed", "50", 10, 200, "FlySpeed", 6)
CreateSlider(AllMenuPage, "Walk Speed", "16", 16, 200, "WalkSpeed", 7)

CreateSection(AllMenuPage, "Utility", 8)

CreateToggle(AllMenuPage, "Anti AFK", "AntiAFKEnabled", 9, function(enabled)
    if enabled then AntiAFKController:Enable() else AntiAFKController:Disable() end
end)

CreateToggle(AllMenuPage, "Auto Rejoin", "AutoRejoinEnabled", 10, function(enabled)
    if enabled then AutoRejoinController:Enable() else AutoRejoinController:Disable() end
end)

CreateActionBtn(AllMenuPage, "Sell All Fish", 11, Theme.Success, SellAllFish)

-- Auto Fishing Page
local AutoFishingPage = CreatePage("AutoFishing")

CreateSection(AutoFishingPage, "Auto Fishing Controls", 1)

-- Fishing Button References (for mutual exclusion)
local FishingButtons = {}

local function StopAllFishing()
    Config.BlatantMode = false
    FishingActive = false
    if FishingButtons.Auto then
        FishingButtons.Auto.Text = "START AUTO FISHING"
        FishingButtons.Auto.BackgroundColor3 = Theme.Success
    end
end

local startFishingBtn = Instance.new("TextButton", AutoFishingPage)
startFishingBtn.Name = "StartFishing"
startFishingBtn.Size = UDim2.new(1, 0, 0, 50)
startFishingBtn.BackgroundColor3 = Theme.Success
startFishingBtn.Text = "START AUTO FISHING"
startFishingBtn.TextColor3 = Theme.TextPrimary
startFishingBtn.TextSize = 16
startFishingBtn.Font = Enum.Font.GothamBold
startFishingBtn.LayoutOrder = 2
startFishingBtn.ZIndex = 5
startFishingBtn.AutoButtonColor = true
Instance.new("UICorner", startFishingBtn).CornerRadius = UDim.new(0, 10)

FishingButtons.Auto = startFishingBtn

startFishingBtn.MouseButton1Click:Connect(function()
    local wasActive = Config.BlatantMode
    StopAllFishing()
    
    if not wasActive then
        Config.BlatantMode = true
        startFishingBtn.Text = "STOP AUTO FISHING"
        startFishingBtn.BackgroundColor3 = Theme.Danger
        Stats.StartTime = os.clock()
        Stats.FishCaught, Stats.TotalSold = 0, 0
        task.spawn(StartAutoFishingLoop)
    end
end)

CreateSection(AutoFishingPage, "Fishing Modes", 3)

CreateToggle(AutoFishingPage, "Instant Fish", "InstantFish", 4)
CreateToggle(AutoFishingPage, "Multi Cast", "MultiCast", 5)
CreateToggle(AutoFishingPage, "Auto Sell", "AutoSell", 6)

CreateSection(AutoFishingPage, "Fishing Settings", 7)
CreateSlider(AutoFishingPage, "Charge Time", "0.3", 0, 10, "ChargeTime", 8)
CreateSlider(AutoFishingPage, "Reel Delay", "0.1", 0, 10, "ReelDelay", 9)
CreateSlider(AutoFishingPage, "Fish Delay", "0.2", 0, 10, "FishingDelay", 10)
CreateSlider(AutoFishingPage, "Cast Amount", "3", 1, 10, "CastAmount", 11)
CreateSlider(AutoFishingPage, "Cast Power", "0.55", 0, 1, "CastPower", 12)

-- Auto Favorite Page
local AutoFavoritePage = CreatePage("AutoFavorite")

CreateSection(AutoFavoritePage, "Auto Favorite Settings", 1)

CreateToggle(AutoFavoritePage, "Enable Auto Favorite", "AutoFavoriteEnabled", 2, function(enabled)
    if enabled then AutoFavoriteController:Enable() else AutoFavoriteController:Disable() end
end)

CreateSection(AutoFavoritePage, "Minimum Rarity to Favorite", 3)

local rarityButtons = {}
for i, rarity in ipairs(RarityList) do
    local rarityBtn = Instance.new("TextButton", AutoFavoritePage)
    rarityBtn.Size = UDim2.new(1, 0, 0, 40)
    rarityBtn.BackgroundColor3 = Config.FavoriteRarity == rarity and Theme.Primary or Theme.BgLight
    rarityBtn.BackgroundTransparency = Config.FavoriteRarity == rarity and 0 or 0.5
    rarityBtn.Text = rarity
    rarityBtn.TextColor3 = Theme.TextPrimary
    rarityBtn.TextSize = 13
    rarityBtn.Font = Enum.Font.GothamMedium
    rarityBtn.LayoutOrder = 3 + i
    rarityBtn.ZIndex = 4
    Instance.new("UICorner", rarityBtn).CornerRadius = UDim.new(0, 10)
    
    rarityButtons[rarity] = rarityBtn
    
    rarityBtn.MouseButton1Click:Connect(function()
        Config.FavoriteRarity = rarity
        for r, btn in pairs(rarityButtons) do
            CreateTween(btn, {
                BackgroundColor3 = r == rarity and Theme.Primary or Theme.BgLight,
                BackgroundTransparency = r == rarity and 0 or 0.5
            }, 0.2):Play()
        end
    end)
end

CreateSection(AutoFavoritePage, "Information", 10)

local favInfoCard = Instance.new("Frame", AutoFavoritePage)
favInfoCard.Size = UDim2.new(1, 0, 0, 60)
favInfoCard.BackgroundColor3 = Theme.BgLight
favInfoCard.BackgroundTransparency = 0.3
favInfoCard.LayoutOrder = 11
favInfoCard.ZIndex = 4
Instance.new("UICorner", favInfoCard).CornerRadius = UDim.new(0, 10)

local favInfoText = Instance.new("TextLabel", favInfoCard)
favInfoText.Size = UDim2.new(1, -20, 1, -20)
favInfoText.Position = UDim2.new(0, 10, 0, 10)
favInfoText.BackgroundTransparency = 1
favInfoText.Text = "Auto Favorite will automatically mark fish as favorite based on the minimum rarity you select above."
favInfoText.TextColor3 = Theme.TextSecondary
favInfoText.TextSize = 11
favInfoText.Font = Enum.Font.Gotham
favInfoText.TextWrapped = true
favInfoText.TextXAlignment = Enum.TextXAlignment.Left
favInfoText.TextYAlignment = Enum.TextYAlignment.Top
favInfoText.ZIndex = 5

-- Weather Event Page
local WeatherPage = CreatePage("Weather")

CreateSection(WeatherPage, "Weather Event Controls", 1)

CreateToggle(WeatherPage, "Auto Buy Events", "AutoBuyEventEnabled", 2, function(enabled)
    if enabled then AutoBuyEventController:Enable() else AutoBuyEventController:Disable() end
end)

CreateSlider(WeatherPage, "Check Interval (sec)", "5", 1, 30, "AutoBuyCheckInterval", 3)

CreateSection(WeatherPage, "Select Event to Buy", 4)

local eventButtons = {}
for i, eventName in ipairs(EventList) do
    local eventBtn = Instance.new("TextButton", WeatherPage)
    eventBtn.Size = UDim2.new(1, 0, 0, 40)
    eventBtn.BackgroundColor3 = Config.SelectedEvent == eventName and Theme.Primary or Theme.BgLight
    eventBtn.BackgroundTransparency = Config.SelectedEvent == eventName and 0 or 0.5
    eventBtn.Text = eventName
    eventBtn.TextColor3 = Theme.TextPrimary
    eventBtn.TextSize = 13
    eventBtn.Font = Enum.Font.GothamMedium
    eventBtn.LayoutOrder = 4 + i
    eventBtn.ZIndex = 4
    eventBtn.AutoButtonColor = false
    Instance.new("UICorner", eventBtn).CornerRadius = UDim.new(0, 10)
    
    local eventStroke = Instance.new("UIStroke", eventBtn)
    eventStroke.Color = Theme.NeonCyan
    eventStroke.Thickness = 1
    eventStroke.Transparency = 1
    
    eventButtons[eventName] = eventBtn
    
    -- Hover animation
    eventBtn.MouseEnter:Connect(function()
        if Config.SelectedEvent ~= eventName then
            CreateTween(eventBtn, {BackgroundTransparency = 0.2}, 0.15):Play()
        end
        CreateTween(eventStroke, {Transparency = 0.5}, 0.15):Play()
    end)
    
    eventBtn.MouseLeave:Connect(function()
        if Config.SelectedEvent ~= eventName then
            CreateTween(eventBtn, {BackgroundTransparency = 0.5}, 0.15):Play()
        end
        CreateTween(eventStroke, {Transparency = 1}, 0.15):Play()
    end)
    
    eventBtn.MouseButton1Click:Connect(function()
        -- Click animation
        CreateTween(eventBtn, {Size = UDim2.new(0.98, 0, 0, 38)}, 0.08):Play()
        task.wait(0.08)
        CreateTween(eventBtn, {Size = UDim2.new(1, 0, 0, 40)}, 0.08):Play()
        
        Config.SelectedEvent = eventName
        for e, btn in pairs(eventButtons) do
            CreateTween(btn, {
                BackgroundColor3 = e == eventName and Theme.Primary or Theme.BgLight,
                BackgroundTransparency = e == eventName and 0 or 0.5
            }, 0.2):Play()
        end
    end)
end

CreateSection(WeatherPage, "Manual Buy", 11)

local buyEventBtn = Instance.new("TextButton", WeatherPage)
buyEventBtn.Size = UDim2.new(1, 0, 0, 45)
buyEventBtn.BackgroundColor3 = Theme.Success
buyEventBtn.Text = "BUY SELECTED EVENT NOW"
buyEventBtn.TextColor3 = Theme.TextPrimary
buyEventBtn.TextSize = 14
buyEventBtn.Font = Enum.Font.GothamBold
buyEventBtn.LayoutOrder = 12
buyEventBtn.ZIndex = 5
buyEventBtn.AutoButtonColor = true
Instance.new("UICorner", buyEventBtn).CornerRadius = UDim.new(0, 10)

buyEventBtn.MouseButton1Click:Connect(function()
    -- Animasi click
    CreateTween(buyEventBtn, {Size = UDim2.new(0.98, 0, 0, 42)}, 0.1):Play()
    task.wait(0.1)
    CreateTween(buyEventBtn, {Size = UDim2.new(1, 0, 0, 45)}, 0.1):Play()
    
    -- Pakai remote yang benar (sama dengan AutoBuy)
    pcall(function()
        Net["RF/PurchaseWeatherEvent"]:InvokeServer(Config.SelectedEvent)
    end)
end)

CreateSection(WeatherPage, "Information", 13)

local weatherInfoCard = Instance.new("Frame", WeatherPage)
weatherInfoCard.Size = UDim2.new(1, 0, 0, 80)
weatherInfoCard.BackgroundColor3 = Theme.BgLight
weatherInfoCard.BackgroundTransparency = 0.3
weatherInfoCard.LayoutOrder = 14
weatherInfoCard.ZIndex = 4
Instance.new("UICorner", weatherInfoCard).CornerRadius = UDim.new(0, 10)

local weatherInfoText = Instance.new("TextLabel", weatherInfoCard)
weatherInfoText.Size = UDim2.new(1, -20, 1, -20)
weatherInfoText.Position = UDim2.new(0, 10, 0, 10)
weatherInfoText.BackgroundTransparency = 1
weatherInfoText.Text = "Weather Events provide special fishing bonuses. Enable Auto Buy to automatically purchase events, or manually buy with the button above."
weatherInfoText.TextColor3 = Theme.TextSecondary
weatherInfoText.TextSize = 11
weatherInfoText.Font = Enum.Font.Gotham
weatherInfoText.TextWrapped = true
weatherInfoText.TextXAlignment = Enum.TextXAlignment.Left
weatherInfoText.TextYAlignment = Enum.TextYAlignment.Top
weatherInfoText.ZIndex = 5

-- Performance Page
local PerformancePage = CreatePage("Performance")

CreateSection(PerformancePage, "Performance Boost", 1)

CreateToggle(PerformancePage, "Performance Mode (VFX + Sound)", "PerformanceMode", 2, function(enabled)
    if enabled then PerformanceController:Enable() else PerformanceController:Disable() end
end)

CreateToggle(PerformancePage, "Anti Lag Mode", "AntiLagEnabled", 3, function(enabled)
    if enabled then AntiLagController:Enable() else AntiLagController:Disable() end
end)

CreateToggle(PerformancePage, "No Animation", "NoAnimation", 4, function(enabled)
    if enabled then AnimationController:Disable() else AnimationController:Enable() end
end)

CreateSection(PerformancePage, "Information", 5)

local perfInfoCard = Instance.new("Frame", PerformancePage)
perfInfoCard.Size = UDim2.new(1, 0, 0, 120)
perfInfoCard.BackgroundColor3 = Theme.BgLight
perfInfoCard.BackgroundTransparency = 0.3
perfInfoCard.LayoutOrder = 6
perfInfoCard.ZIndex = 4
Instance.new("UICorner", perfInfoCard).CornerRadius = UDim.new(0, 10)

local perfInfoText = Instance.new("TextLabel", perfInfoCard)
perfInfoText.Size = UDim2.new(1, -20, 1, -20)
perfInfoText.Position = UDim2.new(0, 10, 0, 10)
perfInfoText.BackgroundTransparency = 1
perfInfoText.Text = "Performance settings help reduce lag and improve FPS:\n\n- Performance Mode: Disable all VFX, particles, sounds\n- Anti Lag: Reduce graphics quality, disable shadows\n- No Animation: Stop character animations"
perfInfoText.TextColor3 = Theme.TextSecondary
perfInfoText.TextSize = 10
perfInfoText.Font = Enum.Font.Gotham
perfInfoText.TextWrapped = true
perfInfoText.TextXAlignment = Enum.TextXAlignment.Left
perfInfoText.TextYAlignment = Enum.TextYAlignment.Top
perfInfoText.ZIndex = 5

-- Stats Bar at Bottom
local StatsBar = Instance.new("Frame", MainFrame)
StatsBar.Size = UDim2.new(1, -150, 0, 28)
StatsBar.Position = UDim2.new(0, 145, 1, -32)
StatsBar.BackgroundColor3 = Theme.BgCard
StatsBar.BackgroundTransparency = 0.5
StatsBar.ZIndex = 3
Instance.new("UICorner", StatsBar).CornerRadius = UDim.new(0, 6)

local StatsText = Instance.new("TextLabel", StatsBar)
StatsText.Size = UDim2.new(1, -20, 1, 0)
StatsText.Position = UDim2.new(0, 8, 0, 0)
StatsText.BackgroundTransparency = 1
StatsText.Text = "Fish: 0 | Sold: 0 | 0/min"
StatsText.TextColor3 = Theme.TextSecondary
StatsText.TextSize = 9
StatsText.Font = Enum.Font.GothamMedium
StatsText.TextXAlignment = Enum.TextXAlignment.Left
StatsText.ZIndex = 4

local StatusIndicator = Instance.new("Frame", StatsBar)
StatusIndicator.Size = UDim2.new(0, 10, 0, 10)
StatusIndicator.Position = UDim2.new(1, -20, 0.5, -5)
StatusIndicator.BackgroundColor3 = Theme.TextMuted
StatusIndicator.ZIndex = 4
Instance.new("UICorner", StatusIndicator).CornerRadius = UDim.new(1, 0)

-- Window Controls Functions
local isMinimized = false
local savedSize = nil

MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        savedSize = MainFrame.Size
        CreateTween(MainFrame, {Size = UDim2.new(0, 140, 0, 55)}, 0.3):Play()
        ContentArea.Visible = false
        StatsBar.Visible = false
        MenuContainer.Visible = false
        ProfileContainer.Visible = false
    else
        CreateTween(MainFrame, {Size = savedSize or UDim2.new(0, 450, 0, 320)}, 0.3):Play()
        task.wait(0.3)
        ContentArea.Visible = true
        StatsBar.Visible = true
        MenuContainer.Visible = true
        ProfileContainer.Visible = true
    end
end)

local isMaximized = false

MaxBtn.MouseButton1Click:Connect(function()
    isMaximized = not isMaximized
    if isMaximized then
        CreateTween(MainFrame, {Size = UDim2.new(0, 600, 0, 420), Position = UDim2.new(0.5, -300, 0.5, -210)}, 0.3):Play()
    else
        CreateTween(MainFrame, {Size = UDim2.new(0, 450, 0, 320), Position = UDim2.new(0.5, -225, 0.5, -160)}, 0.3):Play()
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    Config.BlatantMode = false
    FishingActive = false
    if Config.NoAnimation then AnimationController:Enable() end
    if Config.FlyEnabled then FlyController:Disable() end
    if Config.SpeedEnabled then Config.SpeedEnabled = false updateSpeed() end
    if Config.NoclipEnabled then NoclipController:Disable() end
    if Config.AutoBuyEventEnabled then AutoBuyEventController:Disable() end
    if Config.AntiAFKEnabled then AntiAFKController:Disable() end
    if Config.AutoRejoinEnabled then AutoRejoinController:Disable() end
    if Config.AntiLagEnabled then AntiLagController:Disable() end
    if Config.AutoFavoriteEnabled then AutoFavoriteController:Disable() end
    if Config.PerformanceMode then PerformanceController:Disable() end
    if Config.AutoCatchEnabled then AutoCatchController:Disable() end
    
    CreateTween(MainFrame, {Size = UDim2.new(0, 0, 0, 0), Position = UDim2.new(0.5, 0, 0.5, 0)}, 0.3):Play()
    task.wait(0.3)
    ScreenGui:Destroy()
end)

-- Stats Update Loop
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(0.5)
        local rt = os.clock() - Stats.StartTime
        local cpm = rt > 0 and (Stats.FishCaught / rt) * 60 or 0
        StatsText.Text = string.format("Fish: %d | Sold: %d | %.1f/min", Stats.FishCaught, Stats.TotalSold, cpm)
        
        if Config.BlatantMode then
            StatusIndicator.BackgroundColor3 = Theme.Success
        else
            StatusIndicator.BackgroundColor3 = Theme.TextMuted
        end
    end
end)

-- Character handlers
task.spawn(function()
    local char = Player.Character or Player.CharacterAdded:Wait()
    if char:FindFirstChild("Humanoid") then
        char.Humanoid.Died:Connect(function()
            Config.BlatantMode = false
            FishingActive = false
        end)
    end
end)

Player.CharacterAdded:Connect(function()
    task.wait(1)
    updateSpeed()
end)

-- Parent GUI
ScreenGui.Parent = Player:WaitForChild("PlayerGui")

-- Intro Animation
MainFrame.Size = UDim2.new(0, 0, 0, 0)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
task.wait(0.1)
CreateTween(MainFrame, {
    Size = UDim2.new(0, 450, 0, 320),
    Position = UDim2.new(0.5, -225, 0.5, -160)
}, 0.5, Enum.EasingStyle.Back):Play()
