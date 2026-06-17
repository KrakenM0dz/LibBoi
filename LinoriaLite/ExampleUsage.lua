local Library = loadstring(readfile("LinoriaLite.lua"))()
local SaveManager = loadstring(readfile("SaveManager.lua"))()
local ThemeManager = loadstring(readfile("ThemeManager.lua"))()
-- In Roblox Studio/Exploit you would typically load the module via require() or loadstring() from a URL.
-- For local script testing, you can paste the library code directly above or require it.

-- Assume Library is the returned table from LinoriaLite.lua
local Window = Library:CreateWindow({
    Title = "Linoria Lite | Example",
    Size = UDim2.new(0, 500, 0, 450)
})

local Tab1 = Window:CreateTab("Main")
local Tab2 = Window:CreateTab("Settings")

-- Left GroupBox
local Group1 = Tab1:CreateGroupBox("Left", "Local Player")

Group1:AddToggle("Infinite Jump", false, function(state)
    print("Infinite Jump:", state)
end)

Group1:AddToggle("Noclip", false, function(state)
    print("Noclip:", state)
end)

Group1:AddSlider("WalkSpeed", 16, 100, 16, function(value)
    print("WalkSpeed changed to:", value)
    if game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("Humanoid") then
        game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = value
    end
end)

Group1:AddButton("Reset Character", function()
    print("Resetting character...")
    if game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("Humanoid") then
        game.Players.LocalPlayer.Character.Humanoid.Health = 0
    end
end)

-- Right GroupBox
local Group2 = Tab1:CreateGroupBox("Right", "Visuals")

Group2:AddToggle("ESP Boxes", true, function(state)
    print("ESP Boxes:", state)
end)

Group2:AddDropdown("ESP Mode", {"Box", "Skeleton", "Chams", "Tracers"}, "Box", function(selected)
    print("ESP Mode set to:", selected)
end)

-- Another Left GroupBox
local Group3 = Tab1:CreateGroupBox("Left", "Combat")

Group3:AddToggle("Aimbot", false, function(state)
    print("Aimbot:", state)
end)

Group3:AddLabel("Aimbot Settings")
Group3:AddSlider("FOV Size", 0, 360, 90, function(value)
    print("FOV changed to:", value)
end)
Group3:AddDivider()
Group3:AddKeybind("Toggle Aimbot Key", Enum.KeyCode.E, function(key)
    print("Aimbot key pressed:", key)
end)
Group3:AddColorPicker("FOV Circle Color", Color3.fromRGB(255, 0, 0), function(color)
    print("FOV Color set to:", color)
end)

-- Section Tabs Example (TabBox)
local TabBox1 = Tab1:CreateTabBox("Right")

local PlayersTab = TabBox1:AddTab("Players")
local espToggle = PlayersTab:AddToggle("Player ESP", false, function(s) print("Player ESP:", s) end)
espToggle:AddTooltip("Highlights enemy players through walls")
espToggle:AddKeybind(Enum.KeyCode.Q) -- Inline keybind

PlayersTab:AddDropdown("Player Color", {"Red", "Blue", "Green"}, "Red", function(c) end)
PlayersTab:AddMultiDropdown("ESP Details", {"Name", "Health", "Distance", "Weapon"}, {"Name", "Distance"}, function(opts)
    print("ESP Details selected:", unpack(opts))
end)

local BotsTab = TabBox1:AddTab("Bots")
BotsTab:AddToggle("Bot ESP", false, function(s) print("Bot ESP:", s) end)
BotsTab:AddSlider("Bot Max Dist", 0, 1000, 500, function(v) end)


-- UI Settings Tab
local MenuGroup = Tab2:CreateGroupBox("Left", "Menu")
MenuGroup:AddButton("Unload", function()
    print("Unloading UI...")
    Library:Unload()
end)
MenuGroup:AddKeybind("Menu bind", Enum.KeyCode.End, function(key)
    if Library.ScreenGui then
        Library.ScreenGui.Enabled = not Library.ScreenGui.Enabled
    end
end)

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

ThemeManager:SetFolder("MyScriptHub")
SaveManager:SetFolder("MyScriptHub")

SaveManager:IgnoreThemeSettings()
ThemeManager:BuildThemeSection(Tab2)
SaveManager:BuildConfigSection(Tab2)

-- Initialize Watermark at start
Window:SetWatermark("Linoria Lite | Initialized")
_G.wmState = true

-- Send an initial notification
Window:Notify("UI successfully loaded!", 5)

-- Load states
ThemeManager:LoadDefaultTheme()
SaveManager:LoadAutoloadConfig()

print("UI Loaded!")
