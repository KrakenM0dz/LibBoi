local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local Library = {}
Library.Connections = {}
Library.Options = {}
Library.ThemeObjects = {}
Library.Keybinds = {}    -- every bound key, standalone or attached to a toggle (feeds the keybind list)
Library.Buttons = {}     -- name -> callback, so Library:Press(name) can click it

-- Scripts can register cleanup (restore WalkSpeed, destroy ESP, stop loops...)
-- that runs when the UI unloads, after every toggle has been switched off.
Library.UnloadCallbacks = {}
function Library:OnUnload(fn)
    if type(fn) == "function" then table.insert(Library.UnloadCallbacks, fn) end
end

function Library:Unload()
    if Library.Unloading then return end
    Library.Unloading = true

    -- Switch every toggle off first. SetValue runs the toggle's callback, so a
    -- hub's features (loops, ESP, aimbot...) stop instead of outliving the UI.
    -- The library's own "__" settings are skipped; they die with the GUI.
    for idx, obj in pairs(Library.Options) do
        if obj.Type == "Toggle" and tostring(idx):sub(1, 2) ~= "__" and obj.Value then
            pcall(function() obj:SetValue(false) end)
        end
    end
    for _, fn in ipairs(Library.UnloadCallbacks) do pcall(fn) end
    table.clear(Library.UnloadCallbacks)

    for _, connection in ipairs(Library.Connections) do
        if connection.Connected then
            connection:Disconnect()
        end
    end
    table.clear(Library.Connections)
    table.clear(Library.ThemeObjects)
    table.clear(Library.Options)
    table.clear(Library.Buttons)
    table.clear(Library.Keybinds)
    Library.Window, Library.SettingsTab, Library.SettingsMenuGroup = nil, nil, nil
    Library.NativeSettings = false
    if Library.ScreenGui then
        Library.ScreenGui:Destroy()
        Library.ScreenGui = nil
    end
    if Library.HudGui then
        Library.HudGui:Destroy()
        Library.HudGui = nil
    end
    Library.Unloading = false
end

function Library:Notify(text, duration)
    if Library.Window then Library.Window:Notify(text, duration) end
end

-- Every global input hook goes through here so Unload() can drop all of them.
-- Hooks left connected keep firing against destroyed instances and stack up
-- again each time the script is re-run.
local function TrackInput(event, fn)
    local conn = event:Connect(fn)
    table.insert(Library.Connections, conn)
    return conn
end

-- Drop an instance (and its descendants) from the theme map before destroying
-- it, otherwise the map keeps them alive for the lifetime of the session.
local function Untrack(instance)
    Library.ThemeObjects[instance] = nil
    for _, child in ipairs(instance:GetDescendants()) do
        Library.ThemeObjects[child] = nil
    end
end

-- Rows a dropdown/multi-dropdown shows before its list starts scrolling.
Library.DropdownMaxItems = 6
local DROPDOWN_ROW_HEIGHT = 18

Library.Theme = {
    BackgroundColor = Color3.fromRGB(15, 15, 15),
    MainColor = Color3.fromRGB(20, 20, 20),
    GroupBoxColor = Color3.fromRGB(15, 15, 15),
    OutlineColor = Color3.fromRGB(0, 0, 0),
    InlineColor = Color3.fromRGB(50, 50, 50),
    AccentColor = Color3.fromRGB(0, 255, 255),
    Font = Enum.Font.Code,
    TextColor = Color3.fromRGB(255, 255, 255),
    TextMuted = Color3.fromRGB(150, 150, 150),
}

function Library:UpdateTheme(themeVar, newColor)
    Library.Theme[themeVar] = newColor
    for obj, props in pairs(Library.ThemeObjects) do
        for propName, themeKey in pairs(props) do
            if themeKey == themeVar then
                pcall(function() obj[propName] = newColor end)
            end
        end
    end
    for _, obj in pairs(Library.Options) do
        if type(obj.UpdateColors) == "function" then
            -- pcall so one element's failure can't stop the rest from updating.
            pcall(function() obj:UpdateColors() end)
        end
    end
end

local function Create(className, properties)
    local instance = Instance.new(className)
    properties = properties or {}
    local themeMap = properties.ThemeMap
    properties.ThemeMap = nil
    for k, v in pairs(properties) do
        instance[k] = v
    end
    if themeMap then
        Library.ThemeObjects[instance] = themeMap
    end
    return instance
end

-- =====================================================================
-- Protection: keep the UI out of reach of game scripts
-- =====================================================================
-- Parents a ScreenGui to the safest container the executor offers
-- (gethui > protect_gui + CoreGui > CoreGui > PlayerGui), gives it a random
-- name so name-based scans miss it, and flags it so it survives respawns.
Library.Protect = {
    RandomName = true,   -- random GUI names instead of "LinoriaLiteGui"
    UseHui = true,       -- prefer gethui() when available
}

local function RandomString(n)
    local t = table.create(n)
    for i = 1, n do
        local r = math.random(1, 3)
        t[i] = string.char(r == 1 and math.random(48, 57) or r == 2 and math.random(65, 90) or math.random(97, 122))
    end
    return table.concat(t)
end

local function ProtectGui(gui)
    if Library.Protect.RandomName then gui.Name = RandomString(math.random(10, 20)) end
    -- Draw above Roblox's own menus: OnTopOfCoreBlur lifts the GUI over the escape
    -- menu's dim/blur, and DisplayOrder keeps it above other GUIs (set by the caller).
    pcall(function() gui.OnTopOfCoreBlur = true end)
    local env = getgenv and getgenv() or _G
    local parent
    if Library.Protect.UseHui then
        local f = env.gethui or gethui
        if f then
            local ok, h = pcall(f)
            if ok and typeof(h) == "Instance" then parent = h end
        end
    end
    if not parent then
        local prot = (env.syn and env.syn.protect_gui) or env.protect_gui or env.protectgui
        if prot then pcall(prot, gui) end
        if pcall(function() gui.Parent = CoreGui end) and gui.Parent then return end
    end
    if parent then
        gui.Parent = parent
    else
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end

local function GetTextBounds(text, font, size)
    return TextService:GetTextSize(tostring(text or ""), size, font, Vector2.new(9999, 9999))
end

-- =====================================================================
-- Scrollbar: Linoria-styled slider for a ScrollingFrame
-- =====================================================================
-- Roblox's built-in bar can't be skinned to match the outline/accent look,
-- so the native one is hidden (ScrollBarThickness = 0) and this draws a
-- track + draggable accent thumb over the frame instead.
local SCROLLBAR_WIDTH = 6

local function AttachScrollbar(scrollFrame, parent, zIndex)
    zIndex = zIndex or (scrollFrame.ZIndex + 10)

    local Track = Create("Frame", {
        Name = "ScrollTrack",
        Parent = parent,
        BackgroundColor3 = Library.Theme.OutlineColor,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -1, 0, 1),
        Size = UDim2.new(0, SCROLLBAR_WIDTH, 1, -2),
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = zIndex,
        ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })
    local Thumb = Create("Frame", {
        Name = "ScrollThumb",
        Parent = Track,
        BackgroundColor3 = Library.Theme.AccentColor,
        Position = UDim2.new(0, 1, 0, 0),
        Size = UDim2.new(1, -2, 0, 0),
        BorderSizePixel = 0,
        ZIndex = zIndex + 1,
        ThemeMap = {BackgroundColor3 = "AccentColor"}
    })
    Create("UIGradient", {
        Parent = Thumb,
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(1, Color3.new(0.7, 0.7, 0.7))
        })
    })

    local thumbHeight = 0

    local function Refresh()
        local view = scrollFrame.AbsoluteWindowSize.Y
        local content = scrollFrame.AbsoluteCanvasSize.Y
        if view <= 0 or content <= view + 1 then
            Track.Visible = false
            return
        end
        Track.Visible = true

        local trackH = Track.AbsoluteSize.Y
        thumbHeight = math.clamp(math.floor(trackH * (view / content)), 12, trackH)
        local maxScroll = content - view
        local alpha = maxScroll > 0 and math.clamp(scrollFrame.CanvasPosition.Y / maxScroll, 0, 1) or 0

        Thumb.Size = UDim2.new(1, -2, 0, thumbHeight)
        Thumb.Position = UDim2.new(0, 1, 0, math.floor((trackH - thumbHeight) * alpha))
    end

    local dragging = false

    -- Jump/drag: centre the thumb on the cursor and map that back to canvas Y.
    local function ScrollTo(input)
        local trackH = Track.AbsoluteSize.Y
        local span = trackH - thumbHeight
        if span <= 0 then return end
        local offset = input.Position.Y - Track.AbsolutePosition.Y - (thumbHeight / 2)
        local alpha = math.clamp(offset / span, 0, 1)
        local maxScroll = math.max(scrollFrame.AbsoluteCanvasSize.Y - scrollFrame.AbsoluteWindowSize.Y, 0)
        scrollFrame.CanvasPosition = Vector2.new(0, maxScroll * alpha)
    end

    Track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            ScrollTo(input)
        end
    end)

    local endConn = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    table.insert(Library.Connections, endConn)

    local moveConn = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            ScrollTo(input)
        end
    end)
    table.insert(Library.Connections, moveConn)

    scrollFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(Refresh)
    scrollFrame:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(Refresh)
    scrollFrame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(Refresh)
    Track:GetPropertyChangedSignal("AbsoluteSize"):Connect(Refresh)

    return { Refresh = Refresh, Track = Track, Thumb = Thumb }
end

-- =====================================================================
-- Keybind helpers: short display names + mouse-button (M1/M2/M3) support
-- =====================================================================
-- A "bind" is either an Enum.KeyCode or an Enum.UserInputType (mouse buttons).
Library.KeyShortNames = {
    -- Mouse buttons
    MouseButton1 = "M1",
    MouseButton2 = "M2",
    MouseButton3 = "M3",
    -- Modifiers
    LeftControl = "Ctrl", RightControl = "RCtrl",
    LeftShift = "Shift",  RightShift = "RShift",
    LeftAlt = "Alt",      RightAlt = "RAlt",
    LeftSuper = "Win",    RightSuper = "RWin",
    LeftMeta = "Meta",    RightMeta = "RMeta",
    -- Navigation / editing
    Return = "Enter", Escape = "Esc", Backspace = "Bksp",
    Delete = "Del", Insert = "Ins", PageUp = "PgUp", PageDown = "PgDn",
    CapsLock = "Caps", PrintScreen = "PrtSc",
    -- Arrows
    Up = "Up", Down = "Down", Left = "Left", Right = "Right",
}

-- True when a bind actually points at a key/button.
local function IsBound(bind)
    return bind ~= nil and typeof(bind) == "EnumItem" and bind ~= Enum.KeyCode.Unknown
end

-- Short label for the bind chip, e.g. "M1", "Ctrl", "F" or "None".
local function GetBindName(bind)
    if not IsBound(bind) then return "None" end
    return Library.KeyShortNames[bind.Name] or bind.Name
end

-- While capturing a new bind: convert raw input into a storable bind.
--   returns a bind            -> set it
--   returns Enum.KeyCode.Unknown -> clear it (Escape)
--   returns nil               -> ignore this input
local function GetBindFromInput(input)
    local t = input.UserInputType
    if t == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.Escape then
            return Enum.KeyCode.Unknown
        end
        return input.KeyCode
    elseif t == Enum.UserInputType.MouseButton1
        or t == Enum.UserInputType.MouseButton2
        or t == Enum.UserInputType.MouseButton3 then
        return t
    end
    return nil
end

-- While in use: does this input fire the bind?
local function InputMatchesBind(input, bind)
    if not IsBound(bind) then return false end
    if bind.EnumType == Enum.KeyCode then
        return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == bind
    elseif bind.EnumType == Enum.UserInputType then
        return input.UserInputType == bind
    end
    return false
end

-- Resolve a saved name (e.g. "MouseButton2", "F") back into a bind for configs.
local function ResolveBind(name)
    if type(name) ~= "string" or name == "" or name == "None" or name == "Unknown" then
        return Enum.KeyCode.Unknown
    end
    local okK, k = pcall(function() return Enum.KeyCode[name] end)
    if okK and k then return k end
    local okU, u = pcall(function() return Enum.UserInputType[name] end)
    if okU and u then return u end
    return Enum.KeyCode.Unknown
end

local function MakeDraggable(dragHandle, window)
    local dragging, dragInput, dragStart, startPos

    local function update(input)
        local delta = input.Position - dragStart
        window.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = window.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    TrackInput(UserInputService.InputChanged, function(input)
        if input == dragInput and dragging then
            update(input)
        end
    end)
end

-- =====================================================================
-- Colour picker
-- =====================================================================
-- One implementation, shared by the standalone element and the one that rides
-- on a toggle, so the two can no longer drift apart. Beyond the SV/hue square
-- it carries an alpha bar, a hex field, preset swatches and a rainbow mode.

-- A single heartbeat drives every rainbow-enabled picker, rather than one
-- connection per picker sitting idle in the frame loop.
local RainbowTargets = {}
local RainbowConn = nil
local function SetRainbowDriver(fn, on)
    if on then
        RainbowTargets[fn] = true
        if not RainbowConn then
            RainbowConn = RunService.Heartbeat:Connect(function(dt)
                for f in pairs(RainbowTargets) do f(dt) end
            end)
            table.insert(Library.Connections, RainbowConn)
        end
    else
        RainbowTargets[fn] = nil
    end
end

Library.RainbowSpeed = 0.35   -- hue revolutions per second

local PRESET_COLORS = {
    Color3.fromRGB(255, 255, 255), Color3.fromRGB(0, 0, 0),
    Color3.fromRGB(255, 60, 60),   Color3.fromRGB(255, 150, 40),
    Color3.fromRGB(255, 240, 60),  Color3.fromRGB(70, 230, 110),
    Color3.fromRGB(0, 220, 255),   Color3.fromRGB(120, 110, 255),
}

local function ColorToHex(c)
    return string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- Accepts "#RRGGBB", "RRGGBB" and the "#RGB" shorthand; nil when unparseable.
local function HexToColor(text)
    local hex = tostring(text or ""):gsub("#", ""):gsub("%s", "")
    if #hex == 3 then
        hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
    end
    if #hex ~= 6 or hex:match("%X") then return nil end
    return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end

-- Coerce whatever a config/hub hands us into a Color3.
local function CoerceColor(c)
    if typeof(c) == "Color3" then return c end
    if type(c) == "string" then return HexToColor(c) end
    if type(c) == "table" then
        local r = c.R or c.r or c[1] or 1
        local g = c.G or c.g or c[2] or 1
        local b = c.B or c.b or c[3] or 1
        if r > 1 or g > 1 or b > 1 then return Color3.fromRGB(r, g, b) end
        return Color3.new(r, g, b)
    end
    return nil
end

local FLYOUT_W = 180

-- cfg: ScreenGui, WindowObj, SwatchParent, ClickParent, AnchorFrame,
--      Default, DefaultTransparency, Callback, Idx
local function BuildColorPicker(cfg)
    local ScreenGui = cfg.ScreenGui
    local WindowObj = cfg.WindowObj
    local callback  = cfg.Callback or function() end
    local idx       = cfg.Idx
    local default   = CoerceColor(cfg.Default) or Color3.new(1, 1, 1)

    local obj
    local h, s, v = Color3.toHSV(default)
    local alpha = math.clamp(tonumber(cfg.DefaultTransparency) or 0, 0, 1)  -- 0 = opaque
    local rainbow = false
    local open = false

    ------------------------------------------------------------------ swatch
    local BoxOutline = Create("Frame", {
        Parent = cfg.SwatchParent,
        BackgroundColor3 = Library.Theme.OutlineColor,
        Position = UDim2.new(1, -20, 0, 2),
        Size = UDim2.new(0, 20, 0, 10),
        BorderSizePixel = 0,
        ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })
    local BoxInline = Create("Frame", {
        Parent = BoxOutline,
        BackgroundColor3 = Library.Theme.InlineColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
        ThemeMap = {BackgroundColor3 = "InlineColor"}
    })
    local ColorDisplay = Create("Frame", {
        Parent = BoxInline,
        BackgroundColor3 = default,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0
    })

    -- No ClickParent means only the swatch opens the flyout (the toggle row
    -- itself belongs to the toggle).
    local ToggleBtn = Create("TextButton", {
        Parent = cfg.ClickParent or BoxOutline,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        ZIndex = 5
    })

    ------------------------------------------------------------------ flyout
    local FlyoutOutline = Create("Frame", {
        Parent = ScreenGui,
        BackgroundColor3 = Library.Theme.OutlineColor,
        Size = UDim2.new(0, FLYOUT_W, 0, 218),
        Visible = false,
        ZIndex = 6000,
        ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })
    local FlyoutInline = Create("Frame", {
        Parent = FlyoutOutline,
        BackgroundColor3 = Library.Theme.InlineColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
        ZIndex = 6000,
        ThemeMap = {BackgroundColor3 = "InlineColor"}
    })
    local FlyoutBg = Create("Frame", {
        Parent = FlyoutInline,
        BackgroundColor3 = Library.Theme.GroupBoxColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
        ZIndex = 6000,
        ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
    })

    -- helper for the outlined sub-panels inside the flyout
    local function Panel(y, height)
        local outline = Create("Frame", {
            Parent = FlyoutBg,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 5, 0, y),
            Size = UDim2.new(1, -10, 0, height),
            BorderSizePixel = 0,
            ZIndex = 6001,
            ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local inner = Create("Frame", {
            Parent = outline,
            BackgroundColor3 = Color3.new(1, 1, 1),
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 6002
        })
        return outline, inner
    end

    -- SV square ------------------------------------------------------
    local SVOutline, SVBg = Panel(5, 118)
    SVBg.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
    local SVWhite = Create("Frame", {
        Parent = SVBg,
        BackgroundColor3 = Color3.new(1, 1, 1),
        Size = UDim2.new(1, 0, 1, 0),
        BorderSizePixel = 0,
        ZIndex = 6003
    })
    Create("UIGradient", {
        Parent = SVWhite,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)
        })
    })
    local SVBlack = Create("Frame", {
        Parent = SVBg,
        BackgroundColor3 = Color3.new(0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        BorderSizePixel = 0,
        ZIndex = 6004
    })
    Create("UIGradient", {
        Parent = SVBlack,
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)
        })
    })
    local SVCursor = Create("Frame", {
        Parent = SVBg,
        BackgroundColor3 = Color3.new(1, 1, 1),
        Size = UDim2.new(0, 4, 0, 4),
        Position = UDim2.new(s, -2, 1 - v, -2),
        BorderSizePixel = 1,
        BorderColor3 = Color3.new(0, 0, 0),
        ZIndex = 6005
    })

    -- hue bar --------------------------------------------------------
    local HueOutline, HueBg = Panel(127, 13)
    Create("UIGradient", {
        Parent = HueBg,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
            ColorSequenceKeypoint.new(0.167, Color3.fromHSV(0.167, 1, 1)),
            ColorSequenceKeypoint.new(0.333, Color3.fromHSV(0.333, 1, 1)),
            ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.5, 1, 1)),
            ColorSequenceKeypoint.new(0.667, Color3.fromHSV(0.667, 1, 1)),
            ColorSequenceKeypoint.new(0.833, Color3.fromHSV(0.833, 1, 1)),
            ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1))
        })
    })
    local HueCursor = Create("Frame", {
        Parent = HueBg,
        BackgroundColor3 = Color3.new(1, 1, 1),
        Size = UDim2.new(0, 2, 1, 0),
        Position = UDim2.new(h, -1, 0, 0),
        BorderSizePixel = 1,
        BorderColor3 = Color3.new(0, 0, 0),
        ZIndex = 6003
    })

    -- alpha bar: dark base, colour fading in left (clear) to right (solid)
    local AlphaOutline, AlphaBase = Panel(144, 13)
    AlphaBase.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    local AlphaFill = Create("Frame", {
        Parent = AlphaBase,
        BackgroundColor3 = default,
        Size = UDim2.new(1, 0, 1, 0),
        BorderSizePixel = 0,
        ZIndex = 6003
    })
    Create("UIGradient", {
        Parent = AlphaFill,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)
        })
    })
    local AlphaCursor = Create("Frame", {
        Parent = AlphaBase,
        BackgroundColor3 = Color3.new(1, 1, 1),
        Size = UDim2.new(0, 2, 1, 0),
        Position = UDim2.new(1 - alpha, -1, 0, 0),
        BorderSizePixel = 1,
        BorderColor3 = Color3.new(0, 0, 0),
        ZIndex = 6004
    })

    -- hex field ------------------------------------------------------
    local HexOutline, HexBg = Panel(161, 18)
    HexBg.BackgroundColor3 = Library.Theme.GroupBoxColor
    Library.ThemeObjects[HexBg] = {BackgroundColor3 = "GroupBoxColor"}
    local HexBox = Create("TextBox", {
        Parent = HexBg,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 5, 0, 0),
        Size = UDim2.new(1, -10, 1, 0),
        Font = Library.Theme.Font,
        Text = ColorToHex(default),
        TextColor3 = Library.Theme.TextColor,
        PlaceholderText = "#RRGGBB",
        PlaceholderColor3 = Library.Theme.TextMuted,
        TextSize = 12,
        ClearTextOnFocus = false,
        ZIndex = 6003,
        ThemeMap = {TextColor3 = "TextColor", PlaceholderColor3 = "TextMuted"}
    })

    -- preset swatches ------------------------------------------------
    local PresetRow = Create("Frame", {
        Parent = FlyoutBg,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 5, 0, 183),
        Size = UDim2.new(1, -10, 0, 13),
        ZIndex = 6001
    })
    local presetButtons = {}

    -- rainbow toggle -------------------------------------------------
    local RainbowRow = Create("Frame", {
        Parent = FlyoutBg,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 5, 0, 200),
        Size = UDim2.new(1, -10, 0, 13),
        ZIndex = 6001
    })
    local RbOutline = Create("Frame", {
        Parent = RainbowRow,
        BackgroundColor3 = Library.Theme.OutlineColor,
        Size = UDim2.new(0, 10, 0, 10),
        Position = UDim2.new(0, 0, 0.5, -5),
        BorderSizePixel = 0,
        ZIndex = 6002,
        ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })
    local RbInline = Create("Frame", {
        Parent = RbOutline,
        BackgroundColor3 = Library.Theme.InlineColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
        ZIndex = 6003,
        ThemeMap = {BackgroundColor3 = "InlineColor"}
    })
    local RbFill = Create("Frame", {
        Parent = RbInline,
        BackgroundColor3 = Library.Theme.GroupBoxColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
        ZIndex = 6004
    })
    local RbLabel = Create("TextLabel", {
        Parent = RainbowRow,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 16, 0, 0),
        Size = UDim2.new(1, -16, 1, 0),
        Font = Library.Theme.Font,
        Text = "Rainbow",
        TextColor3 = Library.Theme.TextMuted,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6002
    })
    local RbButton = Create("TextButton", {
        Parent = RainbowRow,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        ZIndex = 6005
    })

    ------------------------------------------------------------------ state
    local function UpdateColor()
        local c = Color3.fromHSV(h, s, v)
        ColorDisplay.BackgroundColor3 = c
        ColorDisplay.BackgroundTransparency = alpha
        SVBg.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        SVCursor.Position = UDim2.new(math.clamp(s, 0, 1), -2, math.clamp(1 - v, 0, 1), -2)
        HueCursor.Position = UDim2.new(math.clamp(h, 0, 1), -1, 0, 0)
        AlphaFill.BackgroundColor3 = c
        AlphaCursor.Position = UDim2.new(math.clamp(1 - alpha, 0, 1), -1, 0, 0)
        if not (HexBox.IsFocused and HexBox:IsFocused()) then HexBox.Text = ColorToHex(c) end
        if obj then
            obj.Value = c
            obj.Transparency = alpha
            obj.Rainbow = rainbow
        end
        if Library.Options[idx] then
            Library.Options[idx].Value = c
            Library.Options[idx].Transparency = alpha
        end
        callback(c, alpha)
    end

    local function RainbowStep(dt)
        h = (h + dt * (Library.RainbowSpeed or 0.35)) % 1
        UpdateColor()
    end

    local function SetRainbow(on)
        rainbow = on and true or false
        RbFill.BackgroundColor3 = rainbow and Library.Theme.AccentColor or Library.Theme.GroupBoxColor
        RbLabel.TextColor3 = rainbow and Library.Theme.TextColor or Library.Theme.TextMuted
        SetRainbowDriver(RainbowStep, rainbow)
        if obj then obj.Rainbow = rainbow end
    end

    RbButton.MouseButton1Click:Connect(function() SetRainbow(not rainbow) end)

    -- preset swatches need UpdateColor, so they are wired after it exists
    for i, c in ipairs(PRESET_COLORS) do
        local swatchOutline = Create("Frame", {
            Parent = PresetRow,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new((i - 1) / #PRESET_COLORS, 0, 0, 0),
            Size = UDim2.new(1 / #PRESET_COLORS, -2, 1, 0),
            BorderSizePixel = 0,
            ZIndex = 6002,
            ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local swatch = Create("Frame", {
            Parent = swatchOutline,
            BackgroundColor3 = c,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 6003
        })
        local btn = Create("TextButton", {
            Parent = swatchOutline,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "",
            ZIndex = 6004
        })
        btn.MouseButton1Click:Connect(function()
            SetRainbow(false)
            h, s, v = Color3.toHSV(c)
            UpdateColor()
        end)
        table.insert(presetButtons, swatch)
    end

    HexBox.FocusLost:Connect(function()
        local c = HexToColor(HexBox.Text)
        if c then
            SetRainbow(false)
            h, s, v = Color3.toHSV(c)
        end
        UpdateColor()   -- also restores the text when the input was rejected
    end)

    ------------------------------------------------------------------ dragging
    local draggingSV, draggingHue, draggingAlpha = false, false, false

    local function UpdateSV(input)
        local bounds, offset = SVBg.AbsoluteSize, SVBg.AbsolutePosition
        if bounds.X <= 0 or bounds.Y <= 0 then return end
        s = math.clamp((input.Position.X - offset.X) / bounds.X, 0, 1)
        v = 1 - math.clamp((input.Position.Y - offset.Y) / bounds.Y, 0, 1)
        UpdateColor()
    end
    local function UpdateH(input)
        local bounds, offset = HueBg.AbsoluteSize, HueBg.AbsolutePosition
        if bounds.X <= 0 then return end
        h = math.clamp((input.Position.X - offset.X) / bounds.X, 0, 1)
        UpdateColor()
    end
    local function UpdateA(input)
        local bounds, offset = AlphaBase.AbsoluteSize, AlphaBase.AbsolutePosition
        if bounds.X <= 0 then return end
        alpha = 1 - math.clamp((input.Position.X - offset.X) / bounds.X, 0, 1)
        UpdateColor()
    end

    local function beginDrag(frame, setFlag)
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                setFlag(input)
            end
        end)
    end
    beginDrag(SVOutline, function(input) draggingSV = true; SetRainbow(false); UpdateSV(input) end)
    beginDrag(HueOutline, function(input) draggingHue = true; SetRainbow(false); UpdateH(input) end)
    beginDrag(AlphaOutline, function(input) draggingAlpha = true; UpdateA(input) end)

    TrackInput(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSV, draggingHue, draggingAlpha = false, false, false
        end
    end)
    TrackInput(UserInputService.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if draggingSV then UpdateSV(input) end
            if draggingHue then UpdateH(input) end
            if draggingAlpha then UpdateA(input) end
        end
    end)

    ------------------------------------------------------------------ open/close
    local function Reposition()
        FlyoutOutline.Position = UDim2.new(0, BoxOutline.AbsolutePosition.X + 25, 0, BoxOutline.AbsolutePosition.Y)
    end
    local function CloseFlyout()
        if not open then return end
        open = false
        FlyoutOutline.Visible = false
    end
    if WindowObj.RegisterPopup then WindowObj.RegisterPopup(CloseFlyout) end

    ToggleBtn.MouseButton1Click:Connect(function()
        if open then
            CloseFlyout()
            return
        end
        if WindowObj.ClosePopups then WindowObj.ClosePopups(CloseFlyout) end
        open = true
        FlyoutOutline.Visible = true
        Reposition()
    end)

    cfg.AnchorFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
        if open then Reposition() end
    end)

    TrackInput(UserInputService.InputBegan, function(input)
        if open and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            local m = input.Position
            local fPos, fSize = FlyoutOutline.AbsolutePosition, FlyoutOutline.AbsoluteSize
            local bPos, bSize = BoxOutline.AbsolutePosition, BoxOutline.AbsoluteSize
            local inFlyout = m.X >= fPos.X and m.X <= fPos.X + fSize.X and m.Y >= fPos.Y and m.Y <= fPos.Y + fSize.Y
            local inBox = m.X >= bPos.X and m.X <= bPos.X + bSize.X and m.Y >= bPos.Y and m.Y <= bPos.Y + bSize.Y
            if not inFlyout and not inBox then CloseFlyout() end
        end
    end)

    UpdateColor()

    ------------------------------------------------------------------ api
    obj = {
        Type = "ColorPicker",
        Value = Color3.fromHSV(h, s, v),
        Transparency = alpha,
        Rainbow = false,
        UpdateColors = function()
            RbFill.BackgroundColor3 = rainbow and Library.Theme.AccentColor or Library.Theme.GroupBoxColor
            RbLabel.TextColor3 = rainbow and Library.Theme.TextColor or Library.Theme.TextMuted
        end,
        Save = function(self)
            return {
                R = self.Value.R, G = self.Value.G, B = self.Value.B,
                A = self.Transparency, Rainbow = self.Rainbow,
            }
        end,
        Load = function(self, val)
            if type(val) ~= "table" then return end
            local c = CoerceColor(val)
            if c then self:SetValue(c) end
            if val.A ~= nil then self:SetTransparency(val.A) end
            self:SetRainbow(val.Rainbow == true)
        end,
        SetValue = function(self, c)
            c = CoerceColor(c)
            if not c then return end
            h, s, v = Color3.toHSV(c)
            UpdateColor()
        end,
        SetTransparency = function(self, a)
            alpha = math.clamp(tonumber(a) or 0, 0, 1)
            UpdateColor()
        end,
        SetRainbow = function(self, on)
            SetRainbow(on)
            UpdateColor()
        end,
        GetHex = function(self) return ColorToHex(self.Value) end,
        SetHex = function(self, hex)
            local c = HexToColor(hex)
            if c then self:SetValue(c) end
        end,
        Close = function() CloseFlyout() end,
        AddTooltip = function(self, text)
            if not text or text == "" then return end
            BoxOutline.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
            BoxOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
        end,
    }
    return obj
end

local function BindElementMethods(Obj, ElementContainer, WindowObj)
    local ScreenGui = WindowObj.ScreenGui
    function Obj:AddLabel(text)
        local LabelFrame = Create("Frame", {
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14)
        })
        local Label = Create("TextLabel", {
            Parent = LabelFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Font = Library.Theme.Font,
            Text = text,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
ThemeMap = {TextColor3 = "TextColor"}
        })

        -- Long text wraps and the row grows to fit it instead of running past the
        -- group box. Width is 0 while a tab is hidden, so it re-runs when that changes.
        local function Resize()
            local w = LabelFrame.AbsoluteSize.X
            if w <= 0 then return end
            local b = TextService:GetTextSize(Label.Text, 12, Library.Theme.Font, Vector2.new(w, 9999))
            LabelFrame.Size = UDim2.new(1, 0, 0, math.max(14, b.Y + 2))
        end
        LabelFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(Resize)
        Resize()

        -- Accepts both `label:SetText(s)` and `label.SetText(s)`; hub scripts use both.
        local LabelObj
        LabelObj = {
            SetText = function(a, b)
                local newText = (a == LabelObj) and b or a
                Label.Text = tostring(newText == nil and "" or newText)
                Resize()
            end
        }
        return LabelObj
    end

    function Obj:AddDivider()
        local DivContainer = Create("Frame", {
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 6)
        })
        local DivOutline = Create("Frame", {
            Parent = DivContainer,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.new(1, 0, 0, 1),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local DivInline = Create("Frame", {
            Parent = DivContainer,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 0, 0.5, 1),
            Size = UDim2.new(1, 0, 0, 1),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
    end

    function Obj:AddToggle(name, default, callback, idx)
        idx = idx or name:gsub(" ", "")
        local state = default or false
        callback = callback or function() end

        local ToggleFrame = Create("Frame", {
            Name = name.."_Toggle",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 18)
        })

        local CheckOutline = Create("Frame", {
            Parent = ToggleFrame,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Size = UDim2.new(0, 15, 0, 15),
            Position = UDim2.new(0, 0, 0.5, -7),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local CheckInline = Create("Frame", {
            Parent = CheckOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local CheckFill = Create("Frame", {
            Parent = CheckInline,
            BackgroundColor3 = state and Library.Theme.AccentColor or Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0
        })

        local Label = Create("TextLabel", {
            Name = "Label",
            Parent = ToggleFrame,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 23, 0, 0),
            Size = UDim2.new(1, -23, 1, 0),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = state and Library.Theme.TextColor or Library.Theme.TextMuted,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left
        })

        local Button = Create("TextButton", {
            Parent = ToggleFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = ""
        })

        -- Declared before SetState so every state change writes through to
        -- ToggleObj.Value -- that field is what configs and hub scripts read.
        local ToggleObj

        local function SetState(newState)
            state = newState and true or false
            local targetBg = state and Library.Theme.AccentColor or Library.Theme.GroupBoxColor
            local targetText = state and Library.Theme.TextColor or Library.Theme.TextMuted
            -- Apply instantly so the accent fill snaps in with no fade lag.
            CheckFill.BackgroundColor3 = targetBg
            Label.TextColor3 = targetText
            if ToggleObj then ToggleObj.Value = state end
            callback(state)
        end

        Button.MouseButton1Click:Connect(function() SetState(not state) end)
        SetState(state)
        
        ToggleObj = { 
            SetValue = function(self, newState) SetState(newState) end,
            AddTooltip = function(self, text)
                if not text or text == "" then return end
                Button.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
                Button.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end,
            HasColorPicker = false
        }

        function ToggleObj:AddKeybind(defaultKey, mode)
            local key = defaultKey or Enum.KeyCode.Unknown
            mode = mode or "Toggle"      -- "Toggle" or "Hold"
            local binding = false
            local held = false
            local justBound = false      -- swallows the click-release that sets M1

            local xOffset = ToggleObj.HasColorPicker and -75 or -50

            local ValueLabel = Create("TextLabel", {
                Parent = ToggleFrame,
                BackgroundTransparency = 1,
                Position = UDim2.new(1, xOffset, 0, 0),
                Size = UDim2.new(0, 50, 1, 0),
                Font = Library.Theme.Font,
                Text = "[" .. GetBindName(key) .. "]",
                TextColor3 = Library.Theme.TextMuted,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Right,
                ZIndex = 5,
ThemeMap = {TextColor3 = "TextMuted"}
            })

            local BindBtn = Create("TextButton", {
                Parent = ValueLabel,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 1, 0),
                Text = "",
                ZIndex = 6
            })

            BindBtn.MouseButton1Click:Connect(function()
                if justBound then return end
                binding = true
                ValueLabel.Text = "[...]"
                ValueLabel.TextColor3 = Library.Theme.AccentColor
            end)

            -- Right-click the chip to switch between Toggle / Hold.
            BindBtn.MouseButton2Click:Connect(function()
                if binding then return end
                mode = (mode == "Toggle") and "Hold" or "Toggle"
                WindowObj.ShowTooltip("Keybind mode: " .. mode)
                task.delay(0.75, WindowObj.HideTooltip)
            end)

            local keyConn = UserInputService.InputBegan:Connect(function(input, processed)
                if binding then
                    local newBind = GetBindFromInput(input)
                    if newBind ~= nil then
                        key = newBind
                        binding = false
                        if newBind == Enum.UserInputType.MouseButton1 then
                            justBound = true
                            task.delay(0.15, function() justBound = false end)
                        end
                        ValueLabel.Text = "[" .. GetBindName(key) .. "]"
                        ValueLabel.TextColor3 = Library.Theme.TextMuted
                    end
                elseif not processed and InputMatchesBind(input, key) then
                    if mode == "Hold" then
                        held = true
                        SetState(true)
                    else
                        SetState(not state)
                    end
                end
            end)
            table.insert(Library.Connections, keyConn)

            local keyEndConn = UserInputService.InputEnded:Connect(function(input)
                if mode == "Hold" and held and InputMatchesBind(input, key) then
                    held = false
                    SetState(false)
                end
            end)
            table.insert(Library.Connections, keyEndConn)

            local BindObj
            BindObj = {
                -- Accepts colon or dot calls, and an EnumItem or a saved name
                -- like "MouseButton2" / "F".
                SetKey = function(a, b)
                    local newKey = (a == BindObj) and b or a
                    if type(newKey) == "string" then newKey = ResolveBind(newKey) end
                    key = (typeof(newKey) == "EnumItem") and newKey or Enum.KeyCode.Unknown
                    ValueLabel.Text = "[" .. GetBindName(key) .. "]"
                end,
                SetMode = function(a, b)
                    local newMode = (a == BindObj) and b or a
                    mode = (newMode == "Hold") and "Hold" or "Toggle"
                end,
                GetKey = function() return key end,
                GetMode = function() return mode end
            }
            Library.Keybinds[idx .. "_bind"] = {
                Name = name,
                GetKey = function() return key end,
                GetMode = function() return mode end,
                IsActive = function() return state and key ~= Enum.KeyCode.Unknown end,
            }
            return BindObj
        end

        function ToggleObj:AddColorPicker(default, callback, cpIdx)
            cpIdx = cpIdx or (idx .. "Color")
            ToggleObj.HasColorPicker = true

            local cpObj = BuildColorPicker({
                ScreenGui = ScreenGui,
                WindowObj = WindowObj,
                SwatchParent = ToggleFrame,
                AnchorFrame = ToggleFrame,
                Default = default,
                Callback = callback,
                Idx = cpIdx,
            })
            Library.Options[cpIdx] = cpObj

            -- The keybind chip shares this row, so shift it clear of the swatch.
            for _, child in pairs(ToggleFrame:GetChildren()) do
                if child:IsA("TextLabel") and child.Name ~= "Label" then
                    child.Position = UDim2.new(1, -75, 0, 0)
                end
            end

            return cpObj
        end

        ToggleObj.Type = "Toggle"
        ToggleObj.Value = state
        ToggleObj.UpdateColors = function()
            local targetBg = state and Library.Theme.AccentColor or Library.Theme.GroupBoxColor
            local targetText = state and Library.Theme.TextColor or Library.Theme.TextMuted
            CheckFill.BackgroundColor3 = targetBg
            Label.TextColor3 = targetText
        end
        ToggleObj.Save = function(self) return self.Value end
        ToggleObj.Load = function(self, val) self:SetValue(val) end
        Library.Options[idx] = ToggleObj
        return ToggleObj
    end

    function Obj:AddButton(name, callback)
        callback = callback or function() end
        
        local ButtonFrame = Create("Frame", {
            Name = name.."_Button",
            Parent = ElementContainer,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Size = UDim2.new(1, 0, 0, 20),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local BtnInline = Create("Frame", {
            Parent = ButtonFrame,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local BtnBg = Create("Frame", {
            Parent = BtnInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })

        local Label = Create("TextLabel", {
            Parent = BtnBg,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            ZIndex = 2,
ThemeMap = {TextColor3 = "TextColor"}
        })

        local Button = Create("TextButton", {
            Parent = BtnBg,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "",
            ZIndex = 3
        })
        
        Create("UIGradient", {
            Parent = BtnBg,
            Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.new(0.7, 0.7, 0.7))
            })
        })

        Button.MouseButton1Down:Connect(function() TweenService:Create(BtnBg, TweenInfo.new(0.1), {BackgroundColor3 = Library.Theme.InlineColor}):Play() end)
        Button.MouseButton1Up:Connect(function() TweenService:Create(BtnBg, TweenInfo.new(0.1), {BackgroundColor3 = Library.Theme.GroupBoxColor}):Play() end)
        Button.MouseLeave:Connect(function() TweenService:Create(BtnBg, TweenInfo.new(0.1), {BackgroundColor3 = Library.Theme.GroupBoxColor}):Play() end)
        Button.MouseButton1Click:Connect(callback)
        Library.Buttons[name] = callback

        return {
            Press = function(self) callback() end,
            AddTooltip = function(self, text)
                if not text or text == "" then return end
                Button.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
                Button.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
    end

    function Obj:AddInput(name, default, callback, idx)
        idx = idx or name:gsub(" ", "")
        default = default or ""
        callback = callback or function() end

        local InputFrame = Create("Frame", {
            Name = name.."_Input",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 36)
        })

        local Label = Create("TextLabel", {
            Parent = InputFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })

        local BoxOutline = Create("Frame", {
            Parent = InputFrame,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 0, 0, 16),
            Size = UDim2.new(1, 0, 0, 20),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local BoxInline = Create("Frame", {
            Parent = BoxOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local BoxBg = Create("Frame", {
            Parent = BoxInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })

        local TextBox = Create("TextBox", {
            Parent = BoxBg,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 6, 0, 0),
            Size = UDim2.new(1, -12, 1, 0),
            Font = Library.Theme.Font,
            Text = tostring(default),
            TextColor3 = Library.Theme.TextColor,
            PlaceholderText = "...",
            PlaceholderColor3 = Library.Theme.TextMuted,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClearTextOnFocus = false,
ThemeMap = {TextColor3 = "TextColor", PlaceholderColor3 = "TextMuted"}
        })

        local obj = {
            Type = "Input",
            Value = default,
            UpdateColors = function()
                Label.TextColor3 = Library.Theme.TextColor
                TextBox.TextColor3 = Library.Theme.TextColor
                TextBox.PlaceholderColor3 = Library.Theme.TextMuted
            end,
            Save = function(self) return self.Value end,
            Load = function(self, val) self:SetValue(val) end,
            SetValue = function(self, text) 
                TextBox.Text = tostring(text)
                if Library.Options[idx] then Library.Options[idx].Value = TextBox.Text end
                callback(TextBox.Text) 
            end,
            AddTooltip = function(self, text)
                if not text or text == "" then return end
                BoxOutline.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
                BoxOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
        TextBox:GetPropertyChangedSignal("Text"):Connect(function()
            if Library.Options[idx] then Library.Options[idx].Value = TextBox.Text end
        end)
        TextBox.FocusLost:Connect(function()
            if Library.Options[idx] then Library.Options[idx].Value = TextBox.Text end
            callback(TextBox.Text)
        end)
        Library.Options[idx] = obj
        return obj
    end

    function Obj:AddSlider(name, min, max, default, callback, idx)
        idx = idx or name:gsub(" ", "")
        min = min or 0
        max = max or 100
        default = default or min
        callback = callback or function() end
        
        local value = default

        -- Decimal places follow the numbers given: 0-0.4 with default 0.1 steps
        -- by 0.01, whole-number sliders keep stepping by 1. Capped at 3.
        local decimals = 0
        for _, n in ipairs({min, max, default}) do
            local str = string.format("%.3f", n):gsub("0+$", "")
            local frac = str:match("%.(%d*)$")
            if frac and #frac > decimals then decimals = #frac end
        end
        -- A sub-1 range with whole-number bounds (eg 0..1) still wants fine steps.
        if decimals == 0 and (max - min) <= 1 then decimals = 2 end
        -- Fractional ranges need at least ~40 steps across the bar (0..0.4 -> 0.01).
        while decimals > 0 and decimals < 3 and (max - min) * 10 ^ decimals < 40 do
            decimals = decimals + 1
        end
        local mult = 10 ^ decimals
        local function Fmt(n)
            local str = string.format("%." .. decimals .. "f", n)
            if decimals > 0 then str = str:gsub("0+$", ""):gsub("%.$", "") end
            return str
        end

        local SliderFrame = Create("Frame", {
            Name = name.."_Slider",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 28)
        })

        local Label = Create("TextLabel", {
            Parent = SliderFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })

        local SliderOutline = Create("Frame", {
            Parent = SliderFrame,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 0, 0, 14),
            Size = UDim2.new(1, 0, 0, 14),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local SliderInline = Create("Frame", {
            Parent = SliderOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local SliderBg = Create("Frame", {
            Parent = SliderInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })

        local SliderFill = Create("Frame", {
            Parent = SliderBg,
            BackgroundColor3 = Library.Theme.AccentColor,
            Size = UDim2.new(0, 0, 1, 0),
            BorderSizePixel = 0,
            ZIndex = 2,
ThemeMap = {BackgroundColor3 = "AccentColor"}
        })
        
        Create("UIGradient", {
            Parent = SliderFill,
            Rotation = 90,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.new(0.7, 0.7, 0.7))
            })
        })

        local ValueLabel = Create("TextLabel", {
            Parent = SliderBg,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Font = Library.Theme.Font,
            Text = Fmt(value) .. "/" .. Fmt(max),
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            ZIndex = 4,
ThemeMap = {TextColor3 = "TextColor"}
        })
        Create("UIStroke", {
            Parent = ValueLabel,
            Color = Library.Theme.OutlineColor,
            Thickness = 1,
ThemeMap = {Color = "OutlineColor"}
        })

        local function UpdateSlider(val, instant)
            value = math.clamp(tonumber(val) or min, min, max)
            value = math.floor(value * mult + 0.5) / mult   -- nearest step
            -- max == min would divide by zero and leave the fill at nan.
            local percent = (max > min) and ((value - min) / (max - min)) or 0
            if instant then
                SliderFill.Size = UDim2.new(percent, 0, 1, 0)
            else
                TweenService:Create(SliderFill, TweenInfo.new(0.05), {Size = UDim2.new(percent, 0, 1, 0)}):Play()
            end
            ValueLabel.Text = Fmt(value) .. "/" .. Fmt(max)
            if Library.Options[idx] then Library.Options[idx].Value = value end
            callback(value)
        end

        local dragging = false
        
        local function move(input)
            -- Zero width while the tab is hidden; dividing by it yields nan.
            local width = SliderBg.AbsoluteSize.X
            if width <= 0 then return end
            local pos = input.Position.X - SliderBg.AbsolutePosition.X
            local percent = math.clamp(pos / width, 0, 1)
            local newValue = min + (max - min) * percent
            UpdateSlider(newValue, false)
        end

        SliderOutline.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                move(input)
            end
        end)

        TrackInput(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)

        TrackInput(UserInputService.InputChanged, function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                move(input)
            end
        end)

        UpdateSlider(default, true)
        local obj = { 
            Type = "Slider",
            Value = default,
            UpdateColors = function()
                SliderFill.BackgroundColor3 = Library.Theme.AccentColor
                ValueLabel.TextColor3 = Library.Theme.TextColor
                Label.TextColor3 = Library.Theme.TextColor
            end,
            SetValue = function(self, newVal) UpdateSlider(newVal, false) end,
            Save = function(self) return self.Value end,
            Load = function(self, val) self:SetValue(val) end,
            AddTooltip = function(self, text)
                if not text or text == "" then return end
                SliderOutline.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
                SliderOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
        Library.Options[idx] = obj
        return obj
    end
    
    function Obj:AddDropdown(name, options, default, callback, idx)
        idx = idx or name:gsub(" ", "")
        options = options or {}
        default = default or options[1]
        callback = callback or function() end
        
        local selected = default
        local open = false
        -- Forward-declared so the methods below can tell a colon call from a dot call.
        local obj
        
        local DropdownFrame = Create("Frame", {
            Name = name.."_Dropdown",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 36)
        })

        local Label = Create("TextLabel", {
            Parent = DropdownFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })

        local BoxOutline = Create("Frame", {
            Parent = DropdownFrame,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 0, 0, 16),
            Size = UDim2.new(1, 0, 0, 20),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local BoxInline = Create("Frame", {
            Parent = BoxOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local BoxBg = Create("Frame", {
            Parent = BoxInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })
        
        local SelectedLabel = Create("TextLabel", {
            Parent = BoxBg,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 6, 0, 0),
            Size = UDim2.new(1, -26, 1, 0),
            Font = Library.Theme.Font,
            Text = tostring(selected),
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })
        
        local Indicator = Create("TextLabel", {
            Parent = BoxBg,
            BackgroundTransparency = 1,
            Position = UDim2.new(1, -20, 0, 0),
            Size = UDim2.new(0, 20, 1, 0),
            Font = Library.Theme.Font,
            Text = "▼",
            TextColor3 = Library.Theme.TextMuted,
            TextSize = 10,
ThemeMap = {TextColor3 = "TextMuted"}
        })
        
        local ToggleBtn = Create("TextButton", {
            Parent = BoxOutline,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "",
            ZIndex = 5
        })
        
        local OptsOutline = Create("Frame", {
            Parent = ScreenGui,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Size = UDim2.new(0, BoxOutline.AbsoluteSize.X, 0, 0),
            Position = UDim2.new(0, BoxOutline.AbsolutePosition.X, 0, BoxOutline.AbsolutePosition.Y + 21),
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 5000,
            ClipsDescendants = true,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local OptsInline = Create("Frame", {
            Parent = OptsOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 5000,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local OptsBg = Create("ScrollingFrame", {
            Parent = OptsInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 5000,
            ClipsDescendants = true,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            ScrollingDirection = Enum.ScrollingDirection.Y,
            -- Native bar is hidden; AttachScrollbar draws the themed one.
            ScrollBarThickness = 0,
            ElasticBehavior = Enum.ElasticBehavior.Never,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })

        local OptionsLayout = Create("UIListLayout", {
            Parent = OptsBg,
            SortOrder = Enum.SortOrder.LayoutOrder
        })

        local Scrollbar = AttachScrollbar(OptsBg, OptsInline, 5010)

        local function UpdateOptions()
            -- Full list height, and the capped height actually shown on screen.
            local contentY = OptionsLayout.AbsoluteContentSize.Y
            local maxY = math.max(Library.DropdownMaxItems or 6, 1) * DROPDOWN_ROW_HEIGHT
            local visibleY = math.min(contentY, maxY)

            -- Canvas is always the full list so the overflow scrolls.
            OptsBg.CanvasSize = UDim2.new(0, 0, 0, contentY)

            -- Narrow the rows when the slider shows so nothing hides under it.
            local needsBar = contentY > visibleY + 1
            OptsBg.Size = UDim2.new(1, -2 - (needsBar and SCROLLBAR_WIDTH or 0), 1, -2)
            Scrollbar.Refresh()

            local targetSize = UDim2.new(0, BoxOutline.AbsoluteSize.X, 0, open and (visibleY + 4) or 0)
            if open then OptsOutline.Visible = true end
            
            local tween = TweenService:Create(OptsOutline, TweenInfo.new(0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = targetSize})
            tween:Play()
            
            if not open then
                tween.Completed:Connect(function()
                    if not open then OptsOutline.Visible = false end
                end)
            end
            
            OptsOutline.Position = UDim2.new(0, BoxOutline.AbsolutePosition.X, 0, BoxOutline.AbsolutePosition.Y + 21)
        end
        
        BoxOutline:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
            if open then UpdateOptions() end
        end)
        BoxOutline:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            if open then UpdateOptions() end
        end)
        -- Layout size settles a frame after options are built, so keep the canvas in sync.
        OptionsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            OptsBg.CanvasSize = UDim2.new(0, 0, 0, OptionsLayout.AbsoluteContentSize.Y)
            Scrollbar.Refresh()
        end)
        
        local function CloseList()
            if not open then return end
            open = false
            OptsOutline.Visible = false
            Indicator.Text = "▼"
        end
        if WindowObj.RegisterPopup then WindowObj.RegisterPopup(CloseList) end

        local optionButtons = {}
        
        local function SetOptions(newOptions)
            options = newOptions
            for _, btn in pairs(optionButtons) do btn:Destroy() end
            table.clear(optionButtons)
            
            for i, opt in ipairs(options) do
                local OptBtn = Create("TextButton", {
                    Parent = OptsBg,
                    BackgroundColor3 = Library.Theme.GroupBoxColor,
                    Size = UDim2.new(1, 0, 0, 18),
                    BorderSizePixel = 0,
                    Font = Library.Theme.Font,
                    Text = "  " .. tostring(opt),
                    TextColor3 = (opt == selected) and Library.Theme.AccentColor or Library.Theme.TextColor,
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 5005,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
                })
                
                OptBtn.MouseButton1Click:Connect(function()
                    selected = opt
                    SelectedLabel.Text = tostring(opt)
                    if Library.Options[idx] then Library.Options[idx].Value = opt end
                    callback(opt)
                    for _, b in pairs(optionButtons) do
                        b.TextColor3 = Library.Theme.TextColor
                    end
                    OptBtn.TextColor3 = Library.Theme.AccentColor
                    CloseList()
                end)
                
                OptBtn.MouseEnter:Connect(function() OptBtn.BackgroundColor3 = Library.Theme.InlineColor end)
                OptBtn.MouseLeave:Connect(function() OptBtn.BackgroundColor3 = Library.Theme.GroupBoxColor end)
                table.insert(optionButtons, OptBtn)
            end
            UpdateOptions()
        end
        
        SetOptions(options)
        
        ToggleBtn.MouseButton1Click:Connect(function()
            if open then
                CloseList()
                return
            end
            if WindowObj.ClosePopups then WindowObj.ClosePopups(CloseList) end
            open = true
            OptsOutline.Visible = true
            Indicator.Text = "▲"
            UpdateOptions()
        end)
        
        TrackInput(UserInputService.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if open then
                    local mPos = input.Position
                    local cPos, cSize = OptsOutline.AbsolutePosition, OptsOutline.AbsoluteSize
                    local bPos, bSize = BoxOutline.AbsolutePosition, BoxOutline.AbsoluteSize
                    
                    local inOptions = (mPos.X >= cPos.X and mPos.X <= cPos.X + cSize.X and mPos.Y >= cPos.Y and mPos.Y <= cPos.Y + cSize.Y)
                    local inBox = (mPos.X >= bPos.X and mPos.X <= bPos.X + bSize.X and mPos.Y >= bPos.Y and mPos.Y <= bPos.Y + bSize.Y)
                    
                    if not inOptions and not inBox then
                        CloseList()
                    end
                end
            end
        end)

        obj = {
            Type = "Dropdown",
            Value = selected,
            UpdateColors = function()
                Label.TextColor3 = Library.Theme.TextColor
                SelectedLabel.TextColor3 = Library.Theme.TextColor
                for _, b in pairs(optionButtons) do
                    b.TextColor3 = (string.sub(b.Text, 3) == tostring(selected)) and Library.Theme.AccentColor or Library.Theme.TextColor
                end
            end,
            Save = function(self) return self.Value end,
            Load = function(self, val) self:SetValue(val) end,
            SetValue = function(self, newVal)
                selected = newVal
                if Library.Options[idx] then Library.Options[idx].Value = newVal end
                SelectedLabel.Text = tostring(newVal)
                for _, b in pairs(optionButtons) do
                    b.TextColor3 = (string.sub(b.Text, 3) == tostring(newVal)) and Library.Theme.AccentColor or Library.Theme.TextColor
                end
                callback(newVal)
            end,
            -- Accepts both `dd:RefreshOptions(list)` and `dd.RefreshOptions(list)`.
            -- Called with a colon before, `self` was consumed as the option list
            -- and ipairs() over it yielded nothing, emptying the dropdown.
            RefreshOptions = function(a, b)
                local newOptions = (a == obj) and b or a
                SetOptions(type(newOptions) == "table" and newOptions or {})
            end,
            AddTooltip = function(self, text)
                if not text or text == "" then return end
                BoxOutline.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
                BoxOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
        Library.Options[idx] = obj
        return obj
    end

    function Obj:AddMultiDropdown(name, options, default, callback, idx)
        idx = idx or name:gsub(" ", "")
        options = options or {}
        default = default or {}
        callback = callback or function() end
        
        local selected = {}
        for _, v in ipairs(default) do selected[v] = true end
        local open = false
        -- Forward-declared so the methods below can tell a colon call from a dot call.
        local obj
        
        local DropdownFrame = Create("Frame", {
            Name = name.."_MultiDropdown",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 36)
        })

        local Label = Create("TextLabel", {
            Parent = DropdownFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })

        local BoxOutline = Create("Frame", {
            Parent = DropdownFrame,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 0, 0, 16),
            Size = UDim2.new(1, 0, 0, 20),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local BoxInline = Create("Frame", {
            Parent = BoxOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local BoxBg = Create("Frame", {
            Parent = BoxInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })
        
        local function GetSelectedString()
            local str = ""
            for _, opt in ipairs(options) do
                if selected[opt] then
                    str = str .. tostring(opt) .. ", "
                end
            end
            if str == "" then return "None" end
            return string.sub(str, 1, -3)
        end

        local SelectedLabel = Create("TextLabel", {
            Parent = BoxBg,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 6, 0, 0),
            Size = UDim2.new(1, -26, 1, 0),
            Font = Library.Theme.Font,
            Text = GetSelectedString(),
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
ThemeMap = {TextColor3 = "TextColor"}
        })
        
        local Indicator = Create("TextLabel", {
            Parent = BoxBg,
            BackgroundTransparency = 1,
            Position = UDim2.new(1, -20, 0, 0),
            Size = UDim2.new(0, 20, 1, 0),
            Font = Library.Theme.Font,
            Text = "▼",
            TextColor3 = Library.Theme.TextMuted,
            TextSize = 10,
ThemeMap = {TextColor3 = "TextMuted"}
        })
        
        local ToggleBtn = Create("TextButton", {
            Parent = BoxOutline,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = "",
            ZIndex = 5
        })
        
        local OptsOutline = Create("Frame", {
            Parent = ScreenGui,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Size = UDim2.new(0, BoxOutline.AbsoluteSize.X, 0, 0),
            Position = UDim2.new(0, BoxOutline.AbsolutePosition.X, 0, BoxOutline.AbsolutePosition.Y + 21),
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 5000,
            ClipsDescendants = true,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local OptsInline = Create("Frame", {
            Parent = OptsOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 5000,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local OptsBg = Create("ScrollingFrame", {
            Parent = OptsInline,
            BackgroundColor3 = Library.Theme.GroupBoxColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 5000,
            ClipsDescendants = true,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            ScrollingDirection = Enum.ScrollingDirection.Y,
            -- Native bar is hidden; AttachScrollbar draws the themed one.
            ScrollBarThickness = 0,
            ElasticBehavior = Enum.ElasticBehavior.Never,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
        })

        local OptionsLayout = Create("UIListLayout", {
            Parent = OptsBg,
            SortOrder = Enum.SortOrder.LayoutOrder
        })

        local Scrollbar = AttachScrollbar(OptsBg, OptsInline, 5010)

        local function UpdateOptions()
            -- Full list height, and the capped height actually shown on screen.
            local contentY = OptionsLayout.AbsoluteContentSize.Y
            local maxY = math.max(Library.DropdownMaxItems or 6, 1) * DROPDOWN_ROW_HEIGHT
            local visibleY = math.min(contentY, maxY)

            -- Canvas is always the full list so the overflow scrolls.
            OptsBg.CanvasSize = UDim2.new(0, 0, 0, contentY)

            -- Narrow the rows when the slider shows so nothing hides under it.
            local needsBar = contentY > visibleY + 1
            OptsBg.Size = UDim2.new(1, -2 - (needsBar and SCROLLBAR_WIDTH or 0), 1, -2)
            Scrollbar.Refresh()

            local targetSize = UDim2.new(0, BoxOutline.AbsoluteSize.X, 0, open and (visibleY + 4) or 0)
            if open then OptsOutline.Visible = true end
            
            local tween = TweenService:Create(OptsOutline, TweenInfo.new(0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = targetSize})
            tween:Play()
            
            if not open then
                tween.Completed:Connect(function()
                    if not open then OptsOutline.Visible = false end
                end)
            end
            
            OptsOutline.Position = UDim2.new(0, BoxOutline.AbsolutePosition.X, 0, BoxOutline.AbsolutePosition.Y + 21)
        end
        
        BoxOutline:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
            if open then UpdateOptions() end
        end)
        BoxOutline:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            if open then UpdateOptions() end
        end)
        -- Layout size settles a frame after options are built, so keep the canvas in sync.
        OptionsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            OptsBg.CanvasSize = UDim2.new(0, 0, 0, OptionsLayout.AbsoluteContentSize.Y)
            Scrollbar.Refresh()
        end)
        
        local function CloseList()
            if not open then return end
            open = false
            OptsOutline.Visible = false
            Indicator.Text = "▼"
        end
        if WindowObj.RegisterPopup then WindowObj.RegisterPopup(CloseList) end

        local optionButtons = {}
        
        local function SetOptions(newOptions)
            options = newOptions
            for _, btn in pairs(optionButtons) do btn:Destroy() end
            table.clear(optionButtons)
            
            for i, opt in ipairs(options) do
                local isSelected = selected[opt] or false
                local OptBtn = Create("TextButton", {
                    Parent = OptsBg,
                    BackgroundColor3 = Library.Theme.GroupBoxColor,
                    Size = UDim2.new(1, 0, 0, 18),
                    BorderSizePixel = 0,
                    Font = Library.Theme.Font,
                    Text = "  " .. (isSelected and "[X] " or "[ ] ") .. tostring(opt),
                    TextColor3 = isSelected and Library.Theme.AccentColor or Library.Theme.TextColor,
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 5005,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
                })
                
                OptBtn.MouseButton1Click:Connect(function()
                    selected[opt] = not selected[opt]
                    local newSelected = selected[opt]
                    OptBtn.Text = "  " .. (newSelected and "[X] " or "[ ] ") .. tostring(opt)
                    OptBtn.TextColor3 = newSelected and Library.Theme.AccentColor or Library.Theme.TextColor
                    SelectedLabel.Text = GetSelectedString()
                    
                    local activeList = {}
                    for _, o in ipairs(options) do
                        if selected[o] then table.insert(activeList, o) end
                    end
                    callback(activeList)
                end)
                
                OptBtn.MouseEnter:Connect(function() OptBtn.BackgroundColor3 = Library.Theme.InlineColor end)
                OptBtn.MouseLeave:Connect(function() OptBtn.BackgroundColor3 = Library.Theme.GroupBoxColor end)
                table.insert(optionButtons, OptBtn)
            end
            UpdateOptions()
        end
        
        SetOptions(options)
        
        ToggleBtn.MouseButton1Click:Connect(function()
            if open then
                CloseList()
                return
            end
            if WindowObj.ClosePopups then WindowObj.ClosePopups(CloseList) end
            open = true
            OptsOutline.Visible = true
            Indicator.Text = "▲"
            UpdateOptions()
        end)
        
        local mConn = UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if open then
                    local mPos = input.Position
                    local cPos, cSize = OptsOutline.AbsolutePosition, OptsOutline.AbsoluteSize
                    local bPos, bSize = BoxOutline.AbsolutePosition, BoxOutline.AbsoluteSize
                    
                    local inOptions = (mPos.X >= cPos.X and mPos.X <= cPos.X + cSize.X and mPos.Y >= cPos.Y and mPos.Y <= cPos.Y + cSize.Y)
                    local inBox = (mPos.X >= bPos.X and mPos.X <= bPos.X + bSize.X and mPos.Y >= bPos.Y and mPos.Y <= bPos.Y + bSize.Y)
                    
                    if not inOptions and not inBox then
                        CloseList()
                    end
                end
            end
        end)
        table.insert(Library.Connections, mConn)

        obj = {
            Type = "MultiDropdown",
            Value = selected,
            UpdateColors = function()
                Label.TextColor3 = Library.Theme.TextColor
                SelectedLabel.TextColor3 = Library.Theme.TextColor
                for _, b in pairs(optionButtons) do
                    local optText = string.sub(b.Text, 7)
                    b.TextColor3 = selected[optText] and Library.Theme.AccentColor or Library.Theme.TextColor
                end
            end,
            Save = function(self)
                local res = {}
                for k, v in pairs(self.Value) do if v then table.insert(res, k) end end
                return res
            end,
            Load = function(self, val) self:SetValue(val) end,
            SetValue = function(self, newTable)
                -- Cleared in place: obj.Value aliases this table, so rebinding it
                -- would strand Value (and therefore Save) on the old selection.
                table.clear(selected)
                for _, v in ipairs(newTable or {}) do selected[v] = true end
                SetOptions(options)
                SelectedLabel.Text = GetSelectedString()
                -- Same shape the click handler passes: the selected options in order.
                local activeList = {}
                for _, o in ipairs(options) do
                    if selected[o] then table.insert(activeList, o) end
                end
                callback(activeList)
            end,
            -- Accepts both `dd:RefreshOptions(list)` and `dd.RefreshOptions(list)`.
            -- Called with a colon before, `self` was consumed as the option list
            -- and ipairs() over it yielded nothing, emptying the dropdown.
            RefreshOptions = function(a, b)
                local newOptions = (a == obj) and b or a
                SetOptions(type(newOptions) == "table" and newOptions or {})
            end,
            AddTooltip = function(self, text)
                if not text or text == "" then return end
                BoxOutline.MouseEnter:Connect(function() WindowObj.ShowTooltip(text) end)
                BoxOutline.MouseLeave:Connect(function() WindowObj.HideTooltip() end)
            end
        }
        Library.Options[idx] = obj
        return obj
    end

    function Obj:AddKeybind(name, default, callback, idx)
        idx = idx or name:gsub(" ", "")
        default = default or Enum.KeyCode.Unknown
        callback = callback or function() end

        local key = default
        local binding = false
        local mode = "Always"          -- "Always" | "Toggle" | "Hold"
        local Modes = {"Always", "Toggle", "Hold"}
        local toggled = false
        local held = false
        local justBound = false        -- swallows the click-release that sets M1

        local KeybindFrame = Create("Frame", {
            Name = name.."_Keybind",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14)
        })

        local Label = Create("TextLabel", {
            Parent = KeybindFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -90, 1, 0),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })

        local ValueLabel = Create("TextLabel", {
            Parent = KeybindFrame,
            BackgroundTransparency = 1,
            Position = UDim2.new(1, -90, 0, 0),
            Size = UDim2.new(0, 90, 1, 0),
            Font = Library.Theme.Font,
            Text = "[None]",
            TextColor3 = Library.Theme.TextMuted,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Right,
ThemeMap = {TextColor3 = "TextMuted"}
        })

        local function refresh()
            local t = "[" .. GetBindName(key) .. "]"
            if IsBound(key) and mode ~= "Always" then
                t = t .. " " .. mode
            end
            ValueLabel.Text = t
        end
        refresh()

        local Button = Create("TextButton", {
            Parent = KeybindFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Text = ""
        })

        Button.MouseButton1Click:Connect(function()
            if justBound then return end
            binding = true
            ValueLabel.Text = "[...]"
            ValueLabel.TextColor3 = Library.Theme.AccentColor
        end)

        -- Right-click to cycle Always -> Toggle -> Hold.
        Button.MouseButton2Click:Connect(function()
            if binding or not IsBound(key) then return end
            local i = table.find(Modes, mode) or 1
            mode = Modes[(i % #Modes) + 1]
            toggled = false
            refresh()
        end)

        TrackInput(UserInputService.InputBegan, function(input, processed)
            if binding then
                local newBind = GetBindFromInput(input)
                if newBind ~= nil then
                    binding = false
                    key = newBind
                    if newBind == Enum.UserInputType.MouseButton1 then
                        justBound = true
                        task.delay(0.15, function() justBound = false end)
                    end
                    ValueLabel.TextColor3 = Library.Theme.TextMuted
                    refresh()
                    if Library.Options[idx] then Library.Options[idx].Value = key.Name end
                    callback(key)
                end
            elseif not processed and InputMatchesBind(input, key) then
                if mode == "Toggle" then
                    toggled = not toggled
                elseif mode == "Hold" then
                    held = true
                end
                callback(key)
            end
        end)

        TrackInput(UserInputService.InputEnded, function(input)
            if mode == "Hold" and held and InputMatchesBind(input, key) then
                held = false
                callback(key)
            end
        end)

        local obj = {
            Type = "Keybind",
            Name = name,
            Value = key.Name,
            Save = function(self) return self.Value end,
            Load = function(self, val)
                if type(val) == "string" then
                    self:SetValue(ResolveBind(val))
                end
            end,
            SetValue = function(self, k)
                -- A bare string used to fall through to key.Name = nil, silently
                -- clearing the bind instead of setting it.
                if type(k) == "string" then k = ResolveBind(k) end
                key = (typeof(k) == "EnumItem") and k or Enum.KeyCode.Unknown
                if Library.Options[idx] then Library.Options[idx].Value = key.Name end
                refresh()
            end,
            SetMode = function(self, m)
                mode = m or "Always"
                toggled = false
                refresh()
            end,
            GetMode = function(self) return mode end,
            -- For Toggle/Hold binds: current on/off state. (Always = momentary.)
            GetState = function(self)
                if mode == "Toggle" then return toggled end
                if mode == "Hold" then return held end
                return false
            end
        }
        Library.Options[idx] = obj
        Library.Keybinds[idx] = {
            Name = name,
            GetKey = function() return key end,
            GetMode = function() return mode end,
            IsActive = function()
                if mode == "Toggle" then return toggled end
                if mode == "Hold" then return held end
                return false
            end,
        }
        return obj
    end

    function Obj:AddColorPicker(name, default, callback, idx)
        idx = idx or name:gsub(" ", "")

        local PickerFrame = Create("Frame", {
            Name = name.."_ColorPicker",
            Parent = ElementContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 14)
        })

        local Label = Create("TextLabel", {
            Parent = PickerFrame,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -30, 1, 0),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            ThemeMap = {TextColor3 = "TextColor"}
        })

        local obj = BuildColorPicker({
            ScreenGui = ScreenGui,
            WindowObj = WindowObj,
            SwatchParent = PickerFrame,
            ClickParent = PickerFrame,   -- the whole row opens the flyout
            AnchorFrame = PickerFrame,
            Default = default,
            Callback = callback,
            Idx = idx,
        })
        Library.Options[idx] = obj
        return obj
    end
end

-- =====================================================================
-- Scripting API (made for driving the UI from code / an executor MCP)
-- =====================================================================
-- All of these are safe to call from `execute`:
--   Library:Get("Idx")            -> current value
--   Library:Set("Idx", value)     -> true/false   (runs the element's callback)
--   Library:Press("Button name")  -> true/false   (clicks a button)
--   Library:SelectTab("Combat")   -> true/false
--   Library:SetVisible(true)      -> show / hide the menu (nil toggles)
--   Library:ListOptions()         -> { Idx = {Type=, Value=} }
--   Library:ListButtons()         -> { "name", ... }
--   Library:ListTabs()            -> { "name", ... }
--   Library:Dump()                -> JSON string of everything above
local HttpService = game:GetService("HttpService")

local function Plain(v)
    local t = typeof(v)
    if t == "Color3" then
        return string.format("#%02x%02x%02x", math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5))
    elseif t == "EnumItem" then return v.Name
    elseif t == "table" then
        local out = {}
        for k, x in pairs(v) do out[tostring(k)] = Plain(x) end
        return out
    elseif t == "number" or t == "string" or t == "boolean" or t == "nil" then return v
    end
    return tostring(v)
end

function Library:Get(idx)
    local o = Library.Options[idx]
    return o and o.Value
end

function Library:Set(idx, value)
    local o = Library.Options[idx]
    if not o or type(o.SetValue) ~= "function" then return false end
    local ok = pcall(function() o:SetValue(value) end)
    return ok
end

function Library:Press(name)
    local cb = Library.Buttons[name]
    if not cb then return false end
    return (pcall(cb))
end

function Library:SelectTab(name)
    return Library.Window ~= nil and Library.Window:SelectTab(name) or false
end

function Library:SetVisible(state)
    if not Library.ScreenGui then return false end
    if state == nil then state = not Library.ScreenGui.Enabled end
    Library.ScreenGui.Enabled = state and true or false
    return Library.ScreenGui.Enabled
end

function Library:ListOptions()
    local out = {}
    for idx, o in pairs(Library.Options) do
        out[tostring(idx)] = {Type = o.Type, Value = Plain(o.Value)}
    end
    return out
end

function Library:ListButtons()
    local out = {}
    for name in pairs(Library.Buttons) do out[#out + 1] = name end
    table.sort(out)
    return out
end

function Library:ListTabs()
    local out = {}
    if Library.Window then
        for _, t in ipairs(Library.Window.Tabs) do out[#out + 1] = t.Name end
    end
    return out
end

function Library:ListKeybinds()
    local out = {}
    for idx, k in pairs(Library.Keybinds) do
        local key = k.GetKey()
        out[tostring(idx)] = {
            Name = k.Name, Key = key and GetBindName(key) or "None",
            Mode = k.GetMode(), Active = k.IsActive() and true or false,
        }
    end
    return out
end

function Library:Dump()
    return HttpService:JSONEncode({
        Tabs = Library:ListTabs(), Buttons = Library:ListButtons(), Keybinds = Library:ListKeybinds(),
        Options = Library:ListOptions(), Visible = Library.ScreenGui and Library.ScreenGui.Enabled or false,
    })
end

-- =====================================================================
-- Optional key system
-- =====================================================================
-- Library:KeySystem{
--     Title    = "My Hub",
--     Note     = "Join the discord for a key",
--     Link     = "https://example.com/getkey",     -- "Get Key" copies this
--
--     -- how a key is checked (first one present wins):
--     Validate = function(key) return true, "optional message" end,
--     Url      = "https://api.example.com/check?key={key}&hwid={hwid}",
--     Keys     = {"abc", "def"},                   -- plain list (readable by anyone with the script)
--
--     -- Url options
--     Parse    = function(body, key) return ok, message end,  -- default: JSON {valid/success=true} or "true"/"valid"/"ok"
--     Timeout  = 8,        -- seconds per request
--     Retries  = 2,        -- extra attempts on network errors (never on "invalid")
--
--     -- abuse limits
--     MaxAttempts = 5,     -- wrong keys before a lockout
--     Cooldown    = 30,    -- lockout seconds
--
--     -- remembering a valid key (re-checked on every launch)
--     SaveFile = "MyHubKey.json",
--     SaveTTL  = 86400,    -- seconds the saved key stays usable (nil = forever)
--
--     OnSuccess = function(key) end,  OnFail = function(key, reason) end,
-- }
-- Blocks until the key is accepted (true) or the user cancels (false).
-- CreateWindow{KeySystem = {...}} runs this first; leave the field out to skip it.
-- NOTE: this runs on the player's machine, so it deters casual sharing only.
-- Real protection needs a server you control (use Url/Validate) -- never trust
-- the client alone.
function Library:KeySystem(opts)
    opts = opts or {}
    local MAX_ATTEMPTS = opts.MaxAttempts or 5
    local COOLDOWN = opts.Cooldown or 30
    local TIMEOUT = opts.Timeout or 8
    local RETRIES = opts.Retries or 2
    local RED = Color3.fromRGB(255, 80, 80)

    local function sanitize(raw)
        local key = tostring(raw or "")
        key = key:gsub("^%s+", "")
        key = key:gsub("%s+$", "")
        if #key > 200 or key:find("%c") then return nil end
        return key
    end

    local function hwid()
        local env = (getgenv and getgenv()) or _G
        local f = env.gethwid or env.get_hwid
        if f then
            local ok, v = pcall(f)
            if ok and v then return tostring(v) end
        end
        local ok, id = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
        return ok and tostring(id) or ""
    end

    -- Default reply format: JSON {valid=true | success=true | status="valid"} or a bare word.
    local function interpret(body)
        local okj, data = pcall(function() return HttpService:JSONDecode(body) end)
        if okj and type(data) == "table" then
            local v = data.valid
            if v == nil then v = data.success end
            if v == nil and type(data.status) == "string" then
                local st = data.status:lower()
                v = (st == "valid" or st == "ok" or st == "success")
            end
            return v == true, data.message
        end
        local t = tostring(body):lower()
        t = t:gsub("^%s+", "")
        t = t:gsub("%s+$", "")
        return (t == "true" or t == "valid" or t == "ok" or t == "success"), nil
    end

    local function httpCheck(key)
        local encKey = HttpService:UrlEncode(key)
        local encHwid = HttpService:UrlEncode(hwid())
        local url = opts.Url:gsub("{key}", function() return encKey end)
        url = url:gsub("{hwid}", function() return encHwid end)
        local lastErr = "Network error"
        for attempt = 0, RETRIES do
            local done, body, err = false, nil, nil
            task.spawn(function()
                local ok, res = pcall(game.HttpGet, game, url)
                if ok then body = res else err = res end
                done = true
            end)
            local t0 = os.clock()
            while not done and os.clock() - t0 < TIMEOUT do task.wait(0.05) end
            if done and body then
                if opts.Parse then
                    local ok, a, b = pcall(opts.Parse, body, key)
                    if not ok then return false, "Server reply not understood" end
                    return a and true or false, b
                end
                return interpret(body)
            end
            lastErr = done and "Request failed" or "Timed out"
            task.wait(math.min(2, 0.5 * (attempt + 1)))
        end
        return false, lastErr .. " - try again"
    end

    -- May yield (HTTP). Always called off the UI thread.
    local function Verify(raw)
        local key = sanitize(raw)
        if not key or key == "" then return false, "Enter a key" end
        if type(opts.Validate) == "function" then
            local ok, a, b = pcall(opts.Validate, key)
            if not ok then return false, "Validator error" end
            return a and true or false, b
        end
        if opts.Url then return httpCheck(key) end
        for _, k in ipairs(opts.Keys or {}) do
            if k == key then return true end
        end
        return false
    end

    -- A previously saved key skips the prompt (still re-verified, and may expire).
    if opts.SaveFile and isfile and readfile then
        local ok, raw = pcall(function() return isfile(opts.SaveFile) and readfile(opts.SaveFile) or nil end)
        if ok and raw then
            local savedKey, savedAt = raw, nil
            local okj, data = pcall(function() return HttpService:JSONDecode(raw) end)
            if okj and type(data) == "table" then savedKey, savedAt = data.key, data.time end
            local fresh = (not opts.SaveTTL) or (savedAt ~= nil and os.time() - savedAt < opts.SaveTTL)
            if savedKey and fresh and (Verify(savedKey)) then
                if opts.OnSuccess then pcall(opts.OnSuccess, sanitize(savedKey)) end
                return true
            end
        end
    end

    local gui = Create("ScreenGui", {
        Name = "LinoriaLiteKey", ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 2147483000
    })
    ProtectGui(gui)

    local function panel(parent, z, color, key)
        return Create("Frame", {
            Parent = parent, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z,
            ThemeMap = {BackgroundColor3 = key}
        })
    end
    local W, H = 320, 170
    local outline = panel(gui, 2, Library.Theme.OutlineColor, "OutlineColor")
    outline.Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2); outline.Size = UDim2.new(0, W, 0, H)
    local inline = panel(outline, 2, Library.Theme.InlineColor, "InlineColor")
    inline.Position = UDim2.new(0, 1, 0, 1); inline.Size = UDim2.new(1, -2, 1, -2)
    local bg = panel(inline, 2, Library.Theme.BackgroundColor, "BackgroundColor")
    bg.Position = UDim2.new(0, 1, 0, 1); bg.Size = UDim2.new(1, -2, 1, -2)
    local accent = panel(bg, 3, Library.Theme.AccentColor, "AccentColor")
    accent.Size = UDim2.new(1, 0, 0, 1)
    MakeDraggable(bg, outline)

    local function text(txt, y, h, color, key, align)
        return Create("TextLabel", {
            Parent = bg, BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, y),
            Size = UDim2.new(1, -20, 0, h), Font = Library.Theme.Font, Text = txt, TextSize = 12,
            TextColor3 = color, TextXAlignment = align or Enum.TextXAlignment.Left, ZIndex = 4,
            ThemeMap = {TextColor3 = key}
        })
    end
    text(opts.Title or "Key System", 8, 16, Library.Theme.TextColor, "TextColor")
    text(opts.Note or "Enter your key to continue", 26, 14, Library.Theme.TextMuted, "TextMuted")

    local boxOut = panel(bg, 4, Library.Theme.OutlineColor, "OutlineColor")
    boxOut.Position = UDim2.new(0, 10, 0, 50); boxOut.Size = UDim2.new(1, -20, 0, 24)
    local boxIn = panel(boxOut, 4, Library.Theme.InlineColor, "InlineColor")
    boxIn.Position = UDim2.new(0, 1, 0, 1); boxIn.Size = UDim2.new(1, -2, 1, -2)
    local boxBg = panel(boxIn, 4, Library.Theme.GroupBoxColor, "GroupBoxColor")
    boxBg.Position = UDim2.new(0, 1, 0, 1); boxBg.Size = UDim2.new(1, -2, 1, -2)
    local box = Create("TextBox", {
        Parent = boxBg, BackgroundTransparency = 1, Size = UDim2.new(1, -10, 1, 0),
        Position = UDim2.new(0, 5, 0, 0), Font = Library.Theme.Font, TextSize = 12,
        Text = "", PlaceholderText = "Key...", PlaceholderColor3 = Library.Theme.TextMuted,
        TextColor3 = Library.Theme.TextColor, TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false, ZIndex = 5, ThemeMap = {TextColor3 = "TextColor"}
    })

    local status = text("", 80, 14, Library.Theme.TextMuted, "TextMuted")
    local function setStatus(msg, color)
        status.Text = msg
        status.TextColor3 = color or Library.Theme.TextMuted
    end

    local function button(label, x, w, onClick)
        local o = panel(bg, 4, Library.Theme.OutlineColor, "OutlineColor")
        o.Position = UDim2.new(x, x == 0 and 10 or 0, 0, 108); o.Size = UDim2.new(w, -6, 0, 24)
        local i = panel(o, 4, Library.Theme.InlineColor, "InlineColor")
        i.Position = UDim2.new(0, 1, 0, 1); i.Size = UDim2.new(1, -2, 1, -2)
        local b = Create("TextButton", {
            Parent = i, BackgroundColor3 = Library.Theme.GroupBoxColor, BorderSizePixel = 0,
            Position = UDim2.new(0, 1, 0, 1), Size = UDim2.new(1, -2, 1, -2), Font = Library.Theme.Font,
            Text = label, TextSize = 12, TextColor3 = Library.Theme.TextColor, AutoButtonColor = false,
            ZIndex = 5, ThemeMap = {BackgroundColor3 = "GroupBoxColor", TextColor3 = "TextColor"}
        })
        b.MouseEnter:Connect(function() b.BackgroundColor3 = Library.Theme.MainColor end)
        b.MouseLeave:Connect(function() b.BackgroundColor3 = Library.Theme.GroupBoxColor end)
        b.MouseButton1Click:Connect(onClick)
        return o
    end

    local result                  -- nil = waiting, true / false = done
    local busy, attempts, lockedUntil, wasLocked = false, 0, 0, false

    local function submit()
        if busy then return end
        if os.clock() < lockedUntil then return end
        busy = true
        setStatus("Checking...")
        local entered = box.Text
        task.spawn(function()
            local ok, msg = Verify(entered)
            if ok then
                setStatus("Key accepted", Library.Theme.AccentColor)
                if opts.SaveFile and writefile then
                    local payload = HttpService:JSONEncode({key = sanitize(entered), time = os.time()})
                    pcall(writefile, opts.SaveFile, payload)
                end
                if opts.OnSuccess then pcall(opts.OnSuccess, sanitize(entered)) end
                task.delay(0.4, function() result = true end)
                return                      -- stay busy so it can't be re-submitted
            end
            attempts = attempts + 1
            if opts.OnFail then pcall(opts.OnFail, entered, msg or "Invalid key") end
            if attempts >= MAX_ATTEMPTS then
                attempts = 0
                lockedUntil = os.clock() + COOLDOWN
            else
                setStatus(msg or "Invalid key", RED)
            end
            busy = false
        end)
    end

    local hasLink = opts.Link and opts.Link ~= ""
    local n = hasLink and 3 or 2
    local idx = 0
    local function slot() idx = idx + 1; return (idx - 1) / n end
    button("Check Key", slot(), 1 / n, submit)
    if hasLink then
        button("Get Key", slot(), 1 / n, function()
            if setclipboard then
                pcall(setclipboard, opts.Link)
                setStatus("Link copied to clipboard")
            else
                setStatus(tostring(opts.Link))
            end
        end)
    end
    button("Cancel", slot(), 1 / n, function() result = false end)
    box.FocusLost:Connect(function(enter) if enter then submit() end end)

    while result == nil and gui.Parent do
        local left = lockedUntil - os.clock()
        if left > 0 then
            setStatus(string.format("Too many attempts - wait %ds", math.ceil(left)), RED)
            wasLocked = true
        elseif wasLocked then
            wasLocked = false
            setStatus("")
        end
        task.wait(0.1)
    end
    gui:Destroy()
    return result == true
end

-- =====================================================================
-- Built-in theme + config managers
-- =====================================================================
-- The Settings tab builds the Themes and Configuration sections by itself, so a
-- script never has to load or wire ThemeManager / SaveManager. Option ids match
-- the standalone managers (ThemeManager_*, SaveManager_*), so scripts that still
-- load those keep working; their UI calls are absorbed (Library.SettingsSink).
--
--   Library:SetFolder("MyHub")            -- config/theme folder (CreateWindow{Folder=} too)
--   Library.ThemeManager:ApplyTheme("Nord") / :LoadDefaultTheme()
--   Library.SaveManager:Save("name") / :Load("name") / :LoadAutoloadConfig()
local ThemeManager = {Folder = "LinoriaLiteSettings"}
local SaveManager = {Folder = "LinoriaLiteSettings", Ignore = {}}
Library.ThemeManager, Library.SaveManager = ThemeManager, SaveManager

-- Chains forever and does nothing: stands in for a group that already exists.
Library.SettingsSink = setmetatable({}, {__index = function(t) return function() return t end end})

ThemeManager.BuiltInThemes = {
    ["Default"] = {1, {FontColor = "ffffff", MainColor = "1c1c1c", AccentColor = "0055ff", BackgroundColor = "141414", OutlineColor = "323232"}},
    ["BBot"] = {2, {FontColor = "ffffff", MainColor = "1e1e1e", AccentColor = "7e48a3", BackgroundColor = "232323", OutlineColor = "141414"}},
    ["Fatality"] = {3, {FontColor = "ffffff", MainColor = "1e1842", AccentColor = "c50754", BackgroundColor = "191335", OutlineColor = "3c355d"}},
    ["Jester"] = {4, {FontColor = "ffffff", MainColor = "242424", AccentColor = "db4467", BackgroundColor = "1c1c1c", OutlineColor = "373737"}},
    ["Mint"] = {5, {FontColor = "ffffff", MainColor = "242424", AccentColor = "3db488", BackgroundColor = "1c1c1c", OutlineColor = "373737"}},
    ["Tokyo Night"] = {6, {FontColor = "ffffff", MainColor = "191925", AccentColor = "6759b3", BackgroundColor = "16161f", OutlineColor = "323232"}},
    ["Ubuntu"] = {7, {FontColor = "ffffff", MainColor = "3e3e3e", AccentColor = "e2581e", BackgroundColor = "323232", OutlineColor = "191919"}},
    ["Quartz"] = {8, {FontColor = "ffffff", MainColor = "232330", AccentColor = "426e87", BackgroundColor = "1d1b26", OutlineColor = "27232f"}},
    ["Midnight"] = {9, {FontColor = "ffffff", MainColor = "14161f", AccentColor = "4f8cff", BackgroundColor = "0e1017", OutlineColor = "262a38"}},
    ["Crimson"] = {10, {FontColor = "ffffff", MainColor = "1d1416", AccentColor = "e0283c", BackgroundColor = "150e10", OutlineColor = "3a2226"}},
    ["Sakura"] = {11, {FontColor = "ffffff", MainColor = "24181e", AccentColor = "ff7eb6", BackgroundColor = "1a1116", OutlineColor = "3d2832"}},
    ["Dracula"] = {12, {FontColor = "ffffff", MainColor = "282a36", AccentColor = "bd93f9", BackgroundColor = "21222c", OutlineColor = "44475a"}},
    ["Nord"] = {13, {FontColor = "ffffff", MainColor = "2e3440", AccentColor = "88c0d0", BackgroundColor = "262b35", OutlineColor = "434c5e"}},
    ["Gold"] = {14, {FontColor = "ffffff", MainColor = "1e1b14", AccentColor = "f5b83d", BackgroundColor = "15130e", OutlineColor = "3a3524"}},
    ["Toxic"] = {15, {FontColor = "ffffff", MainColor = "16201a", AccentColor = "7dff3a", BackgroundColor = "0f1612", OutlineColor = "27382c"}},
    ["Ocean"] = {16, {FontColor = "ffffff", MainColor = "10202b", AccentColor = "1fc8e0", BackgroundColor = "0b1720", OutlineColor = "1f3a4a"}},
}

local function TM_ParseHex(hex)
    hex = tostring(hex):gsub("#", "")
    return Color3.fromRGB(
        tonumber(hex:sub(1, 2), 16) or 255,
        tonumber(hex:sub(3, 4), 16) or 255,
        tonumber(hex:sub(5, 6), 16) or 255
    )
end

local function TM_ToHex(c)
    return string.format("%02x%02x%02x",
        math.clamp(math.floor(c.R * 255 + 0.5), 0, 255),
        math.clamp(math.floor(c.G * 255 + 0.5), 0, 255),
        math.clamp(math.floor(c.B * 255 + 0.5), 0, 255))
end

local function EnsureFolders(folder, sub)
    if not (isfolder and makefolder) then return end
    pcall(function()
        if not isfolder(folder) then makefolder(folder) end
        if sub and not isfolder(folder .. "/" .. sub) then makefolder(folder .. "/" .. sub) end
    end)
end

-- ---- themes ---------------------------------------------------------------
-- Accepts a built-in name ("Nord"), {order, data}, or a plain colour table.
function ThemeManager:ApplyTheme(theme)
    if type(theme) == "string" then
        theme = self.BuiltInThemes[theme]
        if not theme then return false end
    end
    local data = theme
    if type(theme) == "table" and theme[2] then data = theme[2] end

    local new = {}
    for rawKey, val in pairs(data) do
        local key = (rawKey == "FontColor") and "TextColor" or rawKey
        if typeof(val) == "Color3" then
            new[key] = val
        elseif type(val) == "string" then
            new[key] = TM_ParseHex(val)
        elseif type(val) == "table" then
            local r = val.R or val.r or val[1] or 1
            local g = val.G or val.g or val[2] or 1
            local b = val.B or val.b or val[3] or 1
            if r > 1 or g > 1 or b > 1 then new[key] = Color3.fromRGB(r, g, b)
            else new[key] = Color3.new(r, g, b) end
        end
    end
    if new.BackgroundColor then new.GroupBoxColor = new.BackgroundColor end
    if new.MainColor then
        new.InlineColor = Color3.new(
            math.clamp(new.MainColor.R + 30 / 255, 0, 1),
            math.clamp(new.MainColor.G + 30 / 255, 0, 1),
            math.clamp(new.MainColor.B + 30 / 255, 0, 1))
    end
    if new.TextColor then
        new.TextMuted = Color3.new(new.TextColor.R * 0.588, new.TextColor.G * 0.588, new.TextColor.B * 0.588)
    end
    for key, color in pairs(new) do
        if Library.Theme[key] ~= nil then
            Library:UpdateTheme(key, color)
            local picker = Library.Options["ThemeManager_" .. key]
            if picker then pcall(function() picker:SetValue(color) end) end
        end
    end
    return true
end

function ThemeManager:RefreshCustomThemes()
    local list = {}
    if listfiles and isfolder and isfolder(self.Folder .. "/themes") then
        for _, file in ipairs(listfiles(self.Folder .. "/themes")) do
            local name = file:match("([^/\\]+)%.json$")
            if name then list[#list + 1] = name end
        end
    end
    return list
end

function ThemeManager:SaveCustomTheme(name)
    if not writefile then return false end
    EnsureFolders(self.Folder, "themes")
    local t = Library.Theme
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode({
            BackgroundColor = TM_ToHex(t.BackgroundColor), MainColor = TM_ToHex(t.MainColor),
            AccentColor = TM_ToHex(t.AccentColor), OutlineColor = TM_ToHex(t.OutlineColor),
            FontColor = TM_ToHex(t.TextColor),
        })
    end)
    if not ok then return false end
    return (pcall(writefile, self.Folder .. "/themes/" .. name .. ".json", encoded))
end

function ThemeManager:LoadCustomTheme(name)
    if not readfile then return false end
    local ok, content = pcall(readfile, self.Folder .. "/themes/" .. name .. ".json")
    if not ok then return false end
    local okj, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not okj or type(data) ~= "table" then return false end
    return self:ApplyTheme(data)
end

function ThemeManager:LoadDefaultTheme()
    if not readfile then return end
    local ok, content = pcall(readfile, self.Folder .. "/themes/default.txt")
    -- readfile on a missing file returns nil (not an error) on some executors
    if not (ok and type(content) == "string" and content ~= "") then return end
    if self.BuiltInThemes[content] then
        self:ApplyTheme(content)
        local dd = Library.Options.ThemeManager_ThemeList
        if dd then pcall(function() dd:SetValue(content) end) end
    else
        self:LoadCustomTheme(content)
        local dd = Library.Options.ThemeManager_CustomThemeList
        if dd then pcall(function() dd:SetValue(content) end) end
    end
end

function ThemeManager:_BuildSection(Tab)
    local G = Tab:CreateGroupBox("Left", "Themes")

    G:AddColorPicker("Background color", Library.Theme.BackgroundColor, function(c)
        Library:UpdateTheme("BackgroundColor", c)
        Library:UpdateTheme("GroupBoxColor", c)
    end, "ThemeManager_BackgroundColor")
    G:AddColorPicker("Main color", Library.Theme.MainColor, function(c)
        Library:UpdateTheme("MainColor", c)
        Library:UpdateTheme("InlineColor", Color3.new(
            math.clamp(c.R + 30 / 255, 0, 1), math.clamp(c.G + 30 / 255, 0, 1), math.clamp(c.B + 30 / 255, 0, 1)))
    end, "ThemeManager_MainColor")
    G:AddColorPicker("Accent color", Library.Theme.AccentColor, function(c)
        Library:UpdateTheme("AccentColor", c)
    end, "ThemeManager_AccentColor")
    G:AddColorPicker("Outline color", Library.Theme.OutlineColor, function(c)
        Library:UpdateTheme("OutlineColor", c)
    end, "ThemeManager_OutlineColor")
    G:AddColorPicker("Font color", Library.Theme.TextColor, function(c)
        Library:UpdateTheme("TextColor", c)
        Library:UpdateTheme("TextMuted", Color3.new(c.R * 0.588, c.G * 0.588, c.B * 0.588))
    end, "ThemeManager_TextColor")

    local names = {}
    for name, v in pairs(self.BuiltInThemes) do names[v[1]] = name end
    G:AddDropdown("Theme list", names, "Default", function(theme)
        if self.BuiltInThemes[theme] then self:ApplyTheme(theme) end
    end, "ThemeManager_ThemeList")

    G:AddButton("Set as default", function()
        local name = Library.Options.ThemeManager_ThemeList.Value
        if writefile and name then
            EnsureFolders(self.Folder, "themes")
            pcall(writefile, self.Folder .. "/themes/default.txt", name)
            Library:Notify("Default theme: " .. name)
        end
    end)

    G:AddInput("Custom theme name", "", function() end, "ThemeManager_CustomThemeName")
    self._customList = G:AddDropdown("Custom themes", self:RefreshCustomThemes(), nil, function() end, "ThemeManager_CustomThemeList")

    G:AddButton("Save theme", function()
        local name = Library.Options.ThemeManager_CustomThemeName.Value
        if name and name ~= "" and self:SaveCustomTheme(name) then
            self._customList:RefreshOptions(self:RefreshCustomThemes())
            self._customList:SetValue(name)
            Library:Notify("Saved theme: " .. name)
        else
            Library:Notify("Enter a theme name first")
        end
    end)
    G:AddButton("Load theme", function()
        local name = Library.Options.ThemeManager_CustomThemeList.Value
        if name and name ~= "" then
            Library:Notify((self:LoadCustomTheme(name) and "Loaded theme: " or "Failed to load theme: ") .. name)
        end
    end)
    G:AddButton("Refresh list", function()
        self._customList:RefreshOptions(self:RefreshCustomThemes())
    end)
end

-- ---- configs --------------------------------------------------------------
function SaveManager:SetIgnoreIndexes(list)
    for _, idx in ipairs(list) do self.Ignore[idx] = true end
end

-- Themes are managed separately, and the picker/list widgets themselves aren't settings.
SaveManager:SetIgnoreIndexes({
    "ThemeManager_BackgroundColor", "ThemeManager_MainColor", "ThemeManager_AccentColor",
    "ThemeManager_OutlineColor", "ThemeManager_TextColor", "ThemeManager_ThemeList",
    "ThemeManager_CustomThemeName", "ThemeManager_CustomThemeList",
    "SaveManager_ConfigName", "SaveManager_ConfigList",
})
function SaveManager:IgnoreThemeSettings() end   -- already ignored; kept for old scripts

function SaveManager:Save(name)
    if not writefile or not name or name == "" then return false end
    EnsureFolders(self.Folder)
    local data = {}
    for idx, obj in pairs(Library.Options) do
        if not self.Ignore[idx] and type(obj.Save) == "function" then
            data[idx] = {Type = obj.Type, Value = obj:Save()}
        end
    end
    local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if not ok then return false end
    return (pcall(writefile, self.Folder .. "/" .. name .. ".json", encoded))
end

function SaveManager:Load(name)
    if not readfile then return false end
    local ok, content = pcall(readfile, self.Folder .. "/" .. name .. ".json")
    if not ok then return false end
    local okj, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not okj or type(data) ~= "table" then return false end
    for idx, saved in pairs(data) do
        local obj = Library.Options[idx]
        if obj and type(saved) == "table" and obj.Type == saved.Type
            and not self.Ignore[idx] and type(obj.Load) == "function" then
            pcall(function() obj:Load(saved.Value) end)
        end
    end
    return true
end

function SaveManager:RefreshConfigList()
    local list = {}
    if listfiles and isfolder and isfolder(self.Folder) then
        for _, file in ipairs(listfiles(self.Folder)) do
            local name = file:match("([^/\\]+)%.json$")
            if name then list[#list + 1] = name end
        end
    end
    return list
end

function SaveManager:LoadAutoloadConfig()
    if not readfile then return end
    local ok, content = pcall(readfile, self.Folder .. "/autoload.txt")
    if ok and type(content) == "string" and content ~= "" then self:Load(content) end
end

function SaveManager:_RefreshUI()
    if self._cfgList then self._cfgList:RefreshOptions(self:RefreshConfigList()) end
    if self._autoLabel then
        local text = "none"
        if readfile then
            local ok, content = pcall(readfile, self.Folder .. "/autoload.txt")
            if ok and type(content) == "string" and content ~= "" then text = content end
        end
        self._autoLabel:SetText("Autoload config: " .. text)
    end
end

function SaveManager:_BuildSection(Tab)
    local G = Tab:CreateGroupBox("Right", "Configuration")
    local nameBox = G:AddInput("Config name", "", function() end, "SaveManager_ConfigName")
    self._cfgList = G:AddDropdown("Config list", self:RefreshConfigList(), nil, function() end, "SaveManager_ConfigList")

    G:AddButton("Create config", function()
        local name = nameBox.Value
        if name and name ~= "" and self:Save(name) then
            self:_RefreshUI(); self._cfgList:SetValue(name)
            Library:Notify("Created config: " .. name)
        else
            Library:Notify("Enter a config name first")
        end
    end)
    G:AddButton("Load config", function()
        local name = self._cfgList.Value
        if name and name ~= "" then
            Library:Notify((self:Load(name) and "Loaded config: " or "Failed to load: ") .. name)
        end
    end)
    G:AddButton("Overwrite config", function()
        local name = self._cfgList.Value
        if name and name ~= "" and self:Save(name) then Library:Notify("Overwrote config: " .. name) end
    end)
    G:AddButton("Delete config", function()
        local name = self._cfgList.Value
        local path = name and (self.Folder .. "/" .. name .. ".json")
        if path and isfile and delfile and isfile(path) then
            pcall(delfile, path)
            self:_RefreshUI()
            self._cfgList:SetValue(self:RefreshConfigList()[1] or "")
            Library:Notify("Deleted config: " .. name)
        end
    end)
    G:AddButton("Refresh list", function() self:_RefreshUI() end)

    self._autoLabel = G:AddLabel("Autoload config: none")
    G:AddButton("Set as autoload", function()
        local name = self._cfgList.Value
        if name and name ~= "" and writefile then
            EnsureFolders(self.Folder)
            pcall(writefile, self.Folder .. "/autoload.txt", name)
            self:_RefreshUI()
            Library:Notify("Autoload config: " .. name)
        end
    end)
    G:AddButton("Clear autoload", function()
        if isfile and delfile and isfile(self.Folder .. "/autoload.txt") then
            pcall(delfile, self.Folder .. "/autoload.txt")
            self:_RefreshUI()
        end
    end)
    self:_RefreshUI()
end

-- One call moves both managers (and refreshes their lists) to a new folder.
function Library:SetFolder(name)
    name = tostring(name or ""):gsub("[^%w_%- ]", "")
    if name == "" then return end
    ThemeManager.Folder, SaveManager.Folder = name, name
    pcall(function() SaveManager:_RefreshUI() end)
    pcall(function()
        if ThemeManager._customList then ThemeManager._customList:RefreshOptions(ThemeManager:RefreshCustomThemes()) end
    end)
end

function Library:CreateWindow(options)
    options = options or {}
    if options.KeySystem then
        if not Library:KeySystem(options.KeySystem) then return nil end
    end
    local Title = options.Title or "Linoria Lite"
    local Size = options.Size or UDim2.new(0, 550, 0, 450)
    
    local WindowObj = {
        Tabs = {},
        CurrentTab = nil
    }

    local ScreenGui = Create("ScreenGui", {
        Name = "LinoriaLiteGui",
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 2147482500,
        ResetOnSpawn = false
    })
    Library.ScreenGui = ScreenGui
    WindowObj.ScreenGui = ScreenGui
    
    ProtectGui(ScreenGui)

    -- HUD overlays (watermark, keybind list, notifications) get their own GUI so they
    -- stay on screen when the menu is closed; closing the menu only disables ScreenGui.
    local HudGui = Create("ScreenGui", {
        Name = "LinoriaLiteHud", ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false, DisplayOrder = 2147482400
    })
    ProtectGui(HudGui)
    Library.HudGui = HudGui

    local TooltipOutline = Create("Frame", {
        Parent = ScreenGui,
        BackgroundColor3 = Library.Theme.OutlineColor,
        Size = UDim2.new(0, 0, 0, 18),
        Visible = false,
        ZIndex = 10000,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })
    local TooltipInline = Create("Frame", {
        Parent = TooltipOutline,
        BackgroundColor3 = Library.Theme.InlineColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
    })
    local TooltipBg = Create("Frame", {
        Parent = TooltipInline,
        BackgroundColor3 = Library.Theme.BackgroundColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "BackgroundColor"}
    })
    local TooltipText = Create("TextLabel", {
        Parent = TooltipBg,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Font = Library.Theme.Font,
        Text = "",
        TextColor3 = Library.Theme.TextColor,
        TextSize = 12,
ThemeMap = {TextColor3 = "TextColor"}
    })
    
    local function UpdateTooltip(text)
        if text and text ~= "" then
            local bounds = GetTextBounds(text, Library.Theme.Font, 12)
            TooltipOutline.Size = UDim2.new(0, bounds.X + 8, 0, 18)
            TooltipText.Text = text
            TooltipOutline.Visible = true
        else
            TooltipOutline.Visible = false
        end
    end
    
    local mouseConn = UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            if TooltipOutline.Visible then
                TooltipOutline.Position = UDim2.new(0, input.Position.X + 15, 0, input.Position.Y + 15)
            end
        end
    end)
    table.insert(Library.Connections, mouseConn)

    WindowObj.ShowTooltip = function(text) UpdateTooltip(text) end
    WindowObj.HideTooltip = function() UpdateTooltip(nil) end

    -- Dropdown lists and colour-picker flyouts are parented to the ScreenGui so
    -- they can overhang the window. Nothing hides them automatically, so they
    -- register a close function here and are shut when another one opens or the
    -- tab changes -- otherwise they float over whatever is shown next.
    local Popups = {}
    WindowObj.RegisterPopup = function(close) table.insert(Popups, close) end
    WindowObj.ClosePopups = function(except)
        for _, close in ipairs(Popups) do
            if close ~= except then close() end
        end
    end

    -- Watermark UI
    local WatermarkOutline = Create("Frame", {
        Name = "Watermark",
        Parent = HudGui,
        BackgroundColor3 = Library.Theme.OutlineColor,
        Position = UDim2.new(0, 15, 0, 15),
        Size = UDim2.new(0, 0, 0, 20),
        BorderSizePixel = 0,
        Visible = false,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })
    local WmInline = Create("Frame", {
        Parent = WatermarkOutline,
        BackgroundColor3 = Library.Theme.InlineColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
    })
    local WmBg = Create("Frame", {
        Parent = WmInline,
        BackgroundColor3 = Library.Theme.BackgroundColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "BackgroundColor"}
    })
    local WmAccent = Create("Frame", {
        Parent = WmBg,
        BackgroundColor3 = Library.Theme.AccentColor,
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "AccentColor"}
    })
    local WmText = Create("TextLabel", {
        Parent = WmBg,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Font = Library.Theme.Font,
        Text = "",
        TextColor3 = Library.Theme.TextColor,
        TextSize = 12,
ThemeMap = {TextColor3 = "TextColor"}
    })
    
    function WindowObj:SetWatermark(text)
        WmText.Text = text
        if text == "" then
            WatermarkOutline.Visible = false
        else
            local bounds = GetTextBounds(text, Library.Theme.Font, 12)
            WatermarkOutline.Size = UDim2.new(0, bounds.X + 16, 0, 20)
            WatermarkOutline.Visible = true
        end
    end

    -- Notification UI
    local NotificationContainer = Create("Frame", {
        Name = "Notifications",
        Parent = HudGui,
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -15, 1, -15),
        Size = UDim2.new(0, 250, 0, 500),
        AnchorPoint = Vector2.new(1, 1)
    })
    local NotifLayout = Create("UIListLayout", {
        Parent = NotificationContainer,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        VerticalAlignment = Enum.VerticalAlignment.Bottom
    })
    
    function WindowObj:Notify(text, duration)
        duration = duration or Library.NotifyDuration or 3
        
        local NotifOutline = Create("Frame", {
            Parent = NotificationContainer,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Size = UDim2.new(1, 0, 0, 24),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local NotifInline = Create("Frame", {
            Parent = NotifOutline,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local NotifBg = Create("Frame", {
            Parent = NotifInline,
            BackgroundColor3 = Library.Theme.BackgroundColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "BackgroundColor"}
        })
        Create("Frame", {
            Parent = NotifBg,
            BackgroundColor3 = Library.Theme.AccentColor,
            Size = UDim2.new(0, 2, 1, 0),
            BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "AccentColor"}
        })
        Create("TextLabel", {
            Parent = NotifBg,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 10, 0, 0),
            Size = UDim2.new(1, -10, 1, 0),
            Font = Library.Theme.Font,
            Text = tostring(text or ""),
            TextColor3 = Library.Theme.TextColor,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
        })
        
        task.spawn(function()
            task.wait(duration)
            -- Without this the theme map holds every notification ever shown.
            Untrack(NotifOutline)
            NotifOutline:Destroy()
        end)
    end

    local MainFrame = Create("Frame", {
        Name = "MainFrame",
        Parent = ScreenGui,
        BackgroundColor3 = Library.Theme.OutlineColor,
        Position = UDim2.new(0.5, -Size.X.Offset/2, 0.5, -Size.Y.Offset/2),
        Size = Size,
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })
    
    local Inline = Create("Frame", {
        Name = "Inline",
        Parent = MainFrame,
        BackgroundColor3 = Library.Theme.InlineColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
    })

    local WindowBg = Create("Frame", {
        Name = "WindowBg",
        Parent = Inline,
        BackgroundColor3 = Library.Theme.BackgroundColor,
        Position = UDim2.new(0, 1, 0, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "BackgroundColor"}
    })

    local Topbar = Create("Frame", {
        Name = "Topbar",
        Parent = WindowBg,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 18)
    })
    MakeDraggable(Topbar, MainFrame)
    
    Create("TextLabel", {
        Name = "Title",
        Parent = Topbar,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 6, 0, 0),
        Size = UDim2.new(1, -12, 1, 0),
        Font = Library.Theme.Font,
        Text = Title,
        TextColor3 = Library.Theme.TextColor,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
ThemeMap = {TextColor3 = "TextColor"}
    })
    
    Create("Frame", {
        Parent = WindowBg,
        BackgroundColor3 = Library.Theme.OutlineColor,
        Position = UDim2.new(0, 0, 0, 18),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })
    Create("Frame", {
        Parent = WindowBg,
        BackgroundColor3 = Library.Theme.InlineColor,
        Position = UDim2.new(0, 0, 0, 19),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
    })

    local TabContainer = Create("Frame", {
        Name = "TabContainer",
        Parent = WindowBg,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 20),
        Size = UDim2.new(1, 0, 0, 22)
    })
    
    local TabContainerLayout = Create("UIListLayout", {
        Parent = TabContainer,
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder
    })

    local TabLine = Create("Frame", {
        Parent = WindowBg,
        BackgroundColor3 = Library.Theme.InlineColor,
        Position = UDim2.new(0, 0, 0, 42),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        ZIndex = 1,
ThemeMap = {BackgroundColor3 = "InlineColor"}
    })
    local TabLineShadow = Create("Frame", {
        Parent = WindowBg,
        BackgroundColor3 = Library.Theme.OutlineColor,
        Position = UDim2.new(0, 0, 0, 43),
        Size = UDim2.new(1, 0, 0, 1),
        BorderSizePixel = 0,
        ZIndex = 1,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
    })

    local ContentContainer = Create("Frame", {
        Name = "ContentContainer",
        Parent = WindowBg,
        BackgroundColor3 = Library.Theme.MainColor,
        Position = UDim2.new(0, 0, 0, 44),
        Size = UDim2.new(1, 0, 1, -44),
        BorderSizePixel = 0,
        ZIndex = 2,
ThemeMap = {BackgroundColor3 = "MainColor"}
    })

    function WindowObj:SelectTab(name)
        local target
        for _, t in ipairs(WindowObj.Tabs) do
            if t.Name == name then target = t break end
        end
        if not target then return false end
        if WindowObj.ClosePopups then WindowObj.ClosePopups() end
        for _, t in ipairs(WindowObj.Tabs) do
            t.Content.Visible = false
            t.Label.TextColor3 = Library.Theme.TextMuted
            t.Border.Visible = false
        end
        target.Content.Visible = true
        target.Label.TextColor3 = Library.Theme.TextColor
        target.Border.Visible = true
        WindowObj.CurrentTab = target.Obj
        return true
    end

    function WindowObj:CreateTab(name, internal)
        -- A script asking for its own "Settings" tab gets the built-in one.
        if not internal and Library.SettingsTab and tostring(name):lower() == "settings" then
            return Library.SettingsTab
        end
        local TabObj = {}
        local groupCount = 0
        
        local bounds = GetTextBounds(name, Library.Theme.Font, 12)
        local TabButton = Create("TextButton", {
            Name = name.."_Tab",
            Parent = TabContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(0, bounds.X + 16, 1, 0),
            BorderSizePixel = 0,
            Font = Library.Theme.Font,
            Text = "",
            LayoutOrder = internal and 9999 or 0,
            ZIndex = 3
        })

        local TabBorder = Create("Frame", {
            Parent = TabButton,
            BackgroundColor3 = Library.Theme.OutlineColor,
            Size = UDim2.new(1, 0, 1, 2),
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 2,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local TabInline = Create("Frame", {
            Parent = TabBorder,
            BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0,
            ZIndex = 3,
ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local TabBg = Create("Frame", {
            Parent = TabInline,
            BackgroundColor3 = Library.Theme.MainColor,
            Position = UDim2.new(0, 1, 0, 1),
            Size = UDim2.new(1, -2, 1, 0),
            BorderSizePixel = 0,
            ZIndex = 4,
ThemeMap = {BackgroundColor3 = "MainColor"}
        })

        local TabText = Create("TextLabel", {
            Parent = TabButton,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Font = Library.Theme.Font,
            Text = name,
            TextColor3 = Library.Theme.TextMuted,
            TextSize = 12,
            ZIndex = 5,
ThemeMap = {TextColor3 = "TextMuted"}
        })

        local TabContent = Create("ScrollingFrame", {
            Name = name.."_Content",
            Parent = ContentContainer,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            CanvasSize = UDim2.new(0, 0, 0, 0),
            ScrollBarThickness = 0,
            Visible = false
        })

        local LeftCol = Create("Frame", {
            Name = "Left",
            Parent = TabContent,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 8, 0, 10),
            Size = UDim2.new(0.5, -12, 1, -20)
        })
        local LeftLayout = Create("UIListLayout", {
            Parent = LeftCol,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 12)
        })

        local RightCol = Create("Frame", {
            Name = "Right",
            Parent = TabContent,
            BackgroundTransparency = 1,
            Position = UDim2.new(0.5, 4, 0, 10),
            Size = UDim2.new(0.5, -12, 1, -20)
        })
        local RightLayout = Create("UIListLayout", {
            Parent = RightCol,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 12)
        })

        table.insert(WindowObj.Tabs, {
            Button = TabButton, 
            Content = TabContent,
            Border = TabBorder,
            Label = TabText,
            Obj = TabObj,
            Name = name
        })

        TabButton.MouseButton1Click:Connect(function()
            -- Flyouts live on the ScreenGui, not in the tab, so close them by hand.
            if WindowObj.ClosePopups then WindowObj.ClosePopups() end
            for _, tab in pairs(WindowObj.Tabs) do
                tab.Content.Visible = false
                tab.Label.TextColor3 = Library.Theme.TextMuted
                tab.Border.Visible = false
            end
            TabContent.Visible = true
            TabText.TextColor3 = Library.Theme.TextColor
            TabBorder.Visible = true
            WindowObj.CurrentTab = TabObj
        end)

        if not internal and WindowObj.CurrentTab == nil then
            TabContent.Visible = true
            TabText.TextColor3 = Library.Theme.TextColor
            TabBorder.Visible = true
            WindowObj.CurrentTab = TabObj
        end

        function TabObj:CreateGroupBox(side, groupName)
            -- Menu / Themes / Configuration belong to the built-in Settings tab,
            -- whichever tab a script asked for. Themes + Configuration already exist
            -- there (built in), so a script's own copies are absorbed by a sink.
            local n = tostring(groupName):lower()
            local isThemeOrConfig = (n == "themes" or n == "configuration" or n == "config")
            local target
            if Library.NativeSettings and isThemeOrConfig then
                target = Library.SettingsSink
            elseif not internal and Library.SettingsTab and Library.SettingsTab ~= TabObj then
                if n == "menu" then
                    target = Library.SettingsMenuGroup
                elseif isThemeOrConfig then
                    target = Library.SettingsTab:CreateGroupBox(n == "themes" and "Left" or "Right",
                        n == "config" and "Configuration" or groupName)
                end
            end
            if target then
                -- Hide this tab if nothing is left on it.
                task.defer(function()
                    if groupCount == 0 and TabButton.Parent and Library.SettingsTab ~= TabObj then
                        TabButton.Visible = false
                        TabContent.Visible = false
                        if WindowObj.CurrentTab == TabObj then
                            for _, t in ipairs(WindowObj.Tabs) do
                                if t.Button.Visible and t.Button ~= TabButton then
                                    t.Content.Visible = true
                                    t.Label.TextColor3 = Library.Theme.TextColor
                                    t.Border.Visible = true
                                    WindowObj.CurrentTab = t.Obj
                                    break
                                end
                            end
                        end
                    end
                end)
                return target
            end
            groupCount = groupCount + 1
            local GroupObj = {}
            local ParentCol = side == "Left" and LeftCol or RightCol
            
            local GroupBoxOutline = Create("Frame", {
                Name = groupName.."_Group",
                Parent = ParentCol,
                BackgroundColor3 = Library.Theme.OutlineColor,
                Size = UDim2.new(1, 0, 0, 20),
                BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
            })
            local GroupInline = Create("Frame", {
                Parent = GroupBoxOutline,
                BackgroundColor3 = Library.Theme.InlineColor,
                Position = UDim2.new(0, 1, 0, 1),
                Size = UDim2.new(1, -2, 1, -2),
                BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
            })
            local GroupBg = Create("Frame", {
                Parent = GroupInline,
                BackgroundColor3 = Library.Theme.GroupBoxColor,
                Position = UDim2.new(0, 1, 0, 1),
                Size = UDim2.new(1, -2, 1, -2),
                BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
            })

            local titleBounds = GetTextBounds(groupName, Library.Theme.Font, 12)
            local TitleLabel = Create("TextLabel", {
                Name = "Title",
                Parent = GroupBoxOutline,
                BackgroundColor3 = Library.Theme.MainColor,
                Position = UDim2.new(0, 8, 0, -6),
                Size = UDim2.new(0, titleBounds.X + 8, 0, 12),
                BorderSizePixel = 0,
                Font = Library.Theme.Font,
                Text = groupName,
                TextColor3 = Library.Theme.TextColor,
                TextSize = 12,
                ZIndex = 5,
ThemeMap = {BackgroundColor3 = "MainColor", TextColor3 = "TextColor"}
            })

            local ElementContainer = Create("Frame", {
                Name = "Container",
                Parent = GroupBg,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 0, 0, 10),
                Size = UDim2.new(1, 0, 1, -10)
            })
            
            local ContainerLayout = Create("UIListLayout", {
                Parent = ElementContainer,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 6)
            })
            
            Create("UIPadding", {
                Parent = ElementContainer,
                PaddingLeft = UDim.new(0, 8),
                PaddingRight = UDim.new(0, 8),
                PaddingTop = UDim.new(0, 2),
                PaddingBottom = UDim.new(0, 8)
            })

            local function UpdateSize()
                GroupBoxOutline.Size = UDim2.new(1, 0, 0, 10 + ContainerLayout.AbsoluteContentSize.Y + 12)
                TabContent.CanvasSize = UDim2.new(0, 0, 0, math.max(LeftLayout.AbsoluteContentSize.Y, RightLayout.AbsoluteContentSize.Y) + 20)
            end
            
            ContainerLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateSize)
            LeftLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateSize)
            RightLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateSize)

            BindElementMethods(GroupObj, ElementContainer, WindowObj)
            return GroupObj
        end
        
        function TabObj:CreateTabBox(side)
            local TabBoxObj = {}
            local ParentCol = side == "Left" and LeftCol or RightCol
            
            local BoxOutline = Create("Frame", {
                Parent = ParentCol,
                BackgroundColor3 = Library.Theme.OutlineColor,
                Size = UDim2.new(1, 0, 0, 40),
                BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
            })
            local BoxInline = Create("Frame", {
                Parent = BoxOutline,
                BackgroundColor3 = Library.Theme.InlineColor,
                Position = UDim2.new(0, 1, 0, 1),
                Size = UDim2.new(1, -2, 1, -2),
                BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
            })
            local BoxBg = Create("Frame", {
                Parent = BoxInline,
                BackgroundColor3 = Library.Theme.GroupBoxColor,
                Position = UDim2.new(0, 1, 0, 1),
                Size = UDim2.new(1, -2, 1, -2),
                BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
            })
            
            local TabButtonContainer = Create("Frame", {
                Parent = BoxBg,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 20)
            })
            
            local SepLine = Create("Frame", {
                Parent = BoxBg,
                BackgroundColor3 = Library.Theme.InlineColor,
                Position = UDim2.new(0, 0, 0, 20),
                Size = UDim2.new(1, 0, 0, 1),
                BorderSizePixel = 0,
                ZIndex = 2,
ThemeMap = {BackgroundColor3 = "InlineColor"}
            })
            local SepShadow = Create("Frame", {
                Parent = BoxBg,
                BackgroundColor3 = Library.Theme.OutlineColor,
                Position = UDim2.new(0, 0, 0, 21),
                Size = UDim2.new(1, 0, 0, 1),
                BorderSizePixel = 0,
                ZIndex = 2,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
            })
            
            local ContentArea = Create("Frame", {
                Parent = BoxBg,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 0, 0, 22),
                Size = UDim2.new(1, 0, 1, -22)
            })

            local SubTabs = {}

            local function UpdateTabBoxSize()
                local maxHeight = 0
                for _, tab in ipairs(SubTabs) do
                    if tab.Layout.AbsoluteContentSize.Y > maxHeight then
                        maxHeight = tab.Layout.AbsoluteContentSize.Y
                    end
                end
                BoxOutline.Size = UDim2.new(1, 0, 0, 22 + maxHeight + 12)
                TabContent.CanvasSize = UDim2.new(0, 0, 0, math.max(LeftLayout.AbsoluteContentSize.Y, RightLayout.AbsoluteContentSize.Y) + 20)
            end

            function TabBoxObj:AddTab(name)
                local SubTabObj = {}
                
                local TabBtn = Create("TextButton", {
                    Parent = TabButtonContainer,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 0, 1, 0),
                    Font = Library.Theme.Font,
                    Text = name,
                    TextColor3 = Library.Theme.TextMuted,
                    TextSize = 12,
ThemeMap = {TextColor3 = "TextMuted"}
                })

                local RightLine = Create("Frame", {
                    Parent = TabBtn,
                    BackgroundColor3 = Library.Theme.InlineColor,
                    Position = UDim2.new(1, -1, 0, 0),
                    Size = UDim2.new(0, 1, 1, 0),
                    BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "InlineColor"}
                })
                local RightShadow = Create("Frame", {
                    Parent = TabBtn,
                    BackgroundColor3 = Library.Theme.OutlineColor,
                    Position = UDim2.new(1, 0, 0, 0),
                    Size = UDim2.new(0, 1, 1, 0),
                    BorderSizePixel = 0,
ThemeMap = {BackgroundColor3 = "OutlineColor"}
                })

                local ActiveCover = Create("Frame", {
                    Parent = TabBtn,
                    BackgroundColor3 = Library.Theme.GroupBoxColor,
                    Position = UDim2.new(0, 0, 1, 0),
                    Size = UDim2.new(1, 0, 0, 2),
                    BorderSizePixel = 0,
                    Visible = false,
                    ZIndex = 3,
ThemeMap = {BackgroundColor3 = "GroupBoxColor"}
                })

                local AccentLine = Create("Frame", {
                    Parent = TabBtn,
                    BackgroundColor3 = Library.Theme.AccentColor,
                    Size = UDim2.new(1, 0, 0, 1),
                    BorderSizePixel = 0,
                    Visible = false,
                    ZIndex = 4,
ThemeMap = {BackgroundColor3 = "AccentColor"}
                })
                
                Create("UIGradient", {
                    Parent = AccentLine,
                    Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.new(0.2, 0.2, 0.2)),
                        ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
                        ColorSequenceKeypoint.new(1, Color3.new(0.2, 0.2, 0.2))
                    })
                })

                local ElementContainer = Create("Frame", {
                    Parent = ContentArea,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 1, 0),
                    Visible = false
                })
                
                local ContainerLayout = Create("UIListLayout", {
                    Parent = ElementContainer,
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 6)
                })
                
                Create("UIPadding", {
                    Parent = ElementContainer,
                    PaddingLeft = UDim.new(0, 8),
                    PaddingRight = UDim.new(0, 8),
                    PaddingTop = UDim.new(0, 6),
                    PaddingBottom = UDim.new(0, 8)
                })

                table.insert(SubTabs, {
                    Button = TabBtn,
                    Container = ElementContainer,
                    Cover = ActiveCover,
                    Accent = AccentLine,
                    RightLine = RightLine,
                    RightShadow = RightShadow,
                    Layout = ContainerLayout
                })

                local count = #SubTabs
                for i, tab in ipairs(SubTabs) do
                    tab.Button.Size = UDim2.new(1/count, i == count and 0 or -2, 1, 0)
                    tab.Button.Position = UDim2.new((i-1)/count, 0, 0, 0)
                    if i == count then
                        tab.RightLine.Visible = false
                        tab.RightShadow.Visible = false
                    else
                        tab.RightLine.Visible = true
                        tab.RightShadow.Visible = true
                    end
                end

                ContainerLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateTabBoxSize)
                LeftLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateTabBoxSize)
                RightLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateTabBoxSize)

                TabBtn.MouseButton1Click:Connect(function()
                    for _, tab in pairs(SubTabs) do
                        tab.Container.Visible = false
                        tab.Button.TextColor3 = Library.Theme.TextMuted
                        tab.Cover.Visible = false
                        tab.Accent.Visible = false
                    end
                    ElementContainer.Visible = true
                    TabBtn.TextColor3 = Library.Theme.TextColor
                    ActiveCover.Visible = true
                    AccentLine.Visible = true
                end)

                if #SubTabs == 1 then
                    ElementContainer.Visible = true
                    TabBtn.TextColor3 = Library.Theme.TextColor
                    ActiveCover.Visible = true
                    AccentLine.Visible = true
                end

                BindElementMethods(SubTabObj, ElementContainer, WindowObj)
                return SubTabObj
            end
            
            return TabBoxObj
        end
        
        return TabObj
    end

    -- =================================================================
    -- Custom cursor (own ScreenGui so it sits above every popup)
    -- =================================================================
    local CursorGui = Create("ScreenGui", {
        Name = "LinoriaLiteCursor",
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 2147483647
    })
    ProtectGui(CursorGui)
    Library.CursorGui = CursorGui
    Library.CursorEnabled = true

    local CursorRoot = Create("Frame", {
        Parent = CursorGui, BackgroundTransparency = 1,
        Size = UDim2.new(0, 0, 0, 0), ZIndex = 100000
    })
    -- =================================================================
    -- Cursor styles. Everything is Frames + UICorner/UIStroke (anti-aliased,
    -- no assets). Library.Cursor holds the live settings; the Settings tab
    -- edits it and UpdateCursor() applies it every frame.
    -- =================================================================
    local Cur = {
        Style = "Arrow", Size = 16, Color = Color3.fromRGB(255, 255, 255),
        UseAccent = true, Rainbow = false, Trail = false, Spin = false,
    }
    Library.Cursor = Cur
    local BLACK = Color3.new(0, 0, 0)

    local function Box(parent, z, round)
        local f = Create("Frame", {
            Parent = parent, BackgroundTransparency = 1, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 0, 0, 0), ZIndex = z
        })
        if round then Create("UICorner", {Parent = f, CornerRadius = UDim.new(1, 0)}) end
        return f
    end
    local function Outline(f, thickness, color, transparency)
        return Create("UIStroke", {
            Parent = f, Thickness = thickness, Color = color or BLACK,
            Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        })
    end
    local function Container(name)
        return Create("Frame", {
            Name = name, Parent = CursorRoot, BackgroundTransparency = 1,
            Size = UDim2.new(0, 0, 0, 0), Visible = false
        })
    end

    -- Arrow: Roblox's own pointer image (white fill, black outline), tinted with the
    -- UI colour so it reads as a normal cursor that matches the theme. The glyph's
    -- tip sits at the image centre, so centring the image on the mouse is the hotspot.
    local ArrowC = Container("Arrow")
    local ArrowImg = Create("ImageLabel", {
        Parent = ArrowC, BackgroundTransparency = 1, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(0, 48, 0, 48), ZIndex = 100001,
        Image = "rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png",
        ImageColor3 = Library.Theme.AccentColor,
    })

    -- Ring: halo + coloured ring + centre dot
    local RingC = Container("Ring")
    local RingHalo = Box(RingC, 100000, true);  Outline(RingHalo, 1, BLACK, 0.35)
    local RingRing = Box(RingC, 100001, true);  local RingStroke = Outline(RingRing, 2, Color3.new(1, 1, 1))
    local RingDotBg = Box(RingC, 100001, true); RingDotBg.BackgroundTransparency = 0; RingDotBg.BackgroundColor3 = BLACK
    local RingDot = Box(RingC, 100002, true);   RingDot.BackgroundTransparency = 0

    -- Crosshair: 4 arms with dark outline arms behind
    local CrossC = Container("Crosshair")
    local Arms, ArmsBack = {}, {}
    for n = 1, 4 do
        ArmsBack[n] = Box(CrossC, 100000); ArmsBack[n].BackgroundTransparency = 0.35; ArmsBack[n].BackgroundColor3 = BLACK
        Arms[n] = Box(CrossC, 100001);     Arms[n].BackgroundTransparency = 0
    end
    local CrossDot = Box(CrossC, 100002, true); CrossDot.BackgroundTransparency = 0

    -- Dot: solid disc with dark rim
    local DotC = Container("Dot")
    local DotDisc = Box(DotC, 100001, true); DotDisc.BackgroundTransparency = 0
    Outline(DotDisc, 1.5, BLACK, 0.1)

    -- Diamond: rotated square outline + centre dot
    local DiaC = Container("Diamond")
    local DiaHalo = Box(DiaC, 100000); DiaHalo.Rotation = 45; Outline(DiaHalo, 1, BLACK, 0.35)
    local DiaSq = Box(DiaC, 100001);   DiaSq.Rotation = 45; local DiaStroke = Outline(DiaSq, 2, Color3.new(1, 1, 1))
    local DiaDot = Box(DiaC, 100002, true); DiaDot.BackgroundTransparency = 0

    local Containers = {Arrow = ArrowC, Ring = RingC, Crosshair = CrossC, Dot = DotC, Diamond = DiaC}
    Library.CursorStyles = {"Arrow", "Ring", "Crosshair", "Dot", "Diamond"}

    -- Fading trail, parented to the cursor GUI in screen space.
    local TRAIL_N = 10
    local Trail, History = {}, {}
    for n = 1, TRAIL_N do
        local t = Box(CursorGui, 99990, true)
        t.BackgroundColor3 = Color3.new(1, 1, 1); t.Visible = false
        Trail[n] = t
    end

    local pressScale, angle, mouseDown = 1, 0, false
    table.insert(Library.Connections, UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then mouseDown = true end
    end))
    table.insert(Library.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then mouseDown = false end
    end))

    local function SetSize(f, w, h) f.Size = UDim2.new(0, w, 0, h or w) end

    local function UpdateCursor(dt, mouse)
        local color
        if Cur.Rainbow then color = Color3.fromHSV((os.clock() * 0.35) % 1, 0.75, 1)
        elseif Cur.UseAccent then color = Library.Theme.AccentColor
        else color = Cur.Color end

        pressScale = pressScale + ((mouseDown and 0.65 or 1) - pressScale) * math.min(1, dt * 22)
        local sz = Cur.Size * pressScale
        if Cur.Spin then angle = (angle + dt * 160) % 360 else angle = 0 end

        for name, c in pairs(Containers) do c.Visible = (name == Cur.Style) end

        if Cur.Style == "Arrow" then
            local px = math.max(16, math.floor(sz * 3))
            SetSize(ArrowImg, px)
            ArrowImg.ImageColor3 = color
            ArrowC.Rotation = angle
        elseif Cur.Style == "Ring" then
            SetSize(RingHalo, sz + 4); SetSize(RingRing, sz); SetSize(RingDotBg, 8); SetSize(RingDot, 4)
            RingStroke.Color = color; RingDot.BackgroundColor3 = color
            RingC.Rotation = angle
        elseif Cur.Style == "Crosshair" then
            local len, gap, th = math.max(3, sz * 0.45), math.max(2, sz * 0.2), 2
            local dirs = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
            for n, d in ipairs(dirs) do
                local off = gap + len / 2
                local w = d[1] ~= 0 and len or th
                local h = d[2] ~= 0 and len or th
                Arms[n].Size = UDim2.new(0, w, 0, h)
                Arms[n].BackgroundColor3 = color
                Arms[n].Position = UDim2.new(0, d[1] * off, 0, d[2] * off)
                ArmsBack[n].Size = UDim2.new(0, w + 2, 0, h + 2)
                ArmsBack[n].Position = Arms[n].Position
            end
            SetSize(CrossDot, 2); CrossDot.BackgroundColor3 = color
            CrossC.Rotation = angle
        elseif Cur.Style == "Dot" then
            SetSize(DotDisc, math.max(4, sz * 0.5)); DotDisc.BackgroundColor3 = color
        else -- Diamond
            SetSize(DiaHalo, sz * 0.8 + 4); SetSize(DiaSq, sz * 0.8); SetSize(DiaDot, 3)
            DiaStroke.Color = color; DiaDot.BackgroundColor3 = color
            DiaC.Rotation = angle
        end

        -- Trail
        if Cur.Trail then
            table.insert(History, 1, mouse)
            if #History > TRAIL_N then table.remove(History) end
            for n = 1, TRAIL_N do
                local pos, t = History[n], Trail[n]
                if pos then
                    t.Visible = true
                    t.Position = UDim2.new(0, pos.X, 0, pos.Y)
                    SetSize(t, math.max(2, (Cur.Size * 0.4) * (1 - n / (TRAIL_N + 2))))
                    t.BackgroundColor3 = color
                    t.BackgroundTransparency = 0.35 + 0.6 * (n / TRAIL_N)
                end
            end
        elseif #History > 0 then
            table.clear(History)
            for n = 1, TRAIL_N do Trail[n].Visible = false end
        end
    end

    -- =================================================================
    -- First-person shooter support. FPS games lock the mouse to the screen
    -- centre and steer the camera with it, which makes a menu unusable. While the
    -- menu is open: (1) a Modal button + MouseBehavior.Default free the mouse,
    -- (2) in first-person-like games the camera is held still. Everything is
    -- put back the moment the menu closes (or the UI unloads).
    -- =================================================================
    Library.MouseOptions = {Unlock = true, Freeze = true}
    local ModalBtn = Create("TextButton", {
        Parent = ScreenGui, BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 0),
        Text = "", Modal = false, ZIndex = 1
    })
    local fpsActive, savedBehavior, frozenCF, freezeOn = false, nil, nil, false
    local lastLockedAt = -math.huge   -- last time the game had the mouse locked
    -- Bound once (unique name) and gated by frozenCF; binding/unbinding on every
    -- open and close proved unreliable across executors.
    local FREEZE_NAME = "LL" .. RandomString(10)

    local function freezeStep()
        local cam = workspace.CurrentCamera
        if frozenCF and cam then cam.CFrame = frozenCF end
    end
    RunService:BindToRenderStep(FREEZE_NAME, Enum.RenderPriority.Last.Value + 1, freezeStep)

    -- Read-only view of the mouse/camera hold, for scripts and MCP probing.
    function Library:GetMouseState()
        return {Active = fpsActive, CameraFrozen = freezeOn, Saved = savedBehavior and savedBehavior.Name or nil}
    end

    local function FpsUpdate(menuOpen)
        local opt = Library.MouseOptions
        local want = menuOpen and opt.Unlock
        if not fpsActive and UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
            lastLockedAt = os.clock()
        end
        if want and not fpsActive then
            fpsActive = true
            savedBehavior = UserInputService.MouseBehavior
            ModalBtn.Modal = true
            -- First-person-like: the mouse is locked, or the camera sits at the head.
            local cam = workspace.CurrentCamera
            local firstPerson = savedBehavior ~= Enum.MouseBehavior.Default
                or os.clock() - lastLockedAt < 1
            if not firstPerson and cam then
                local head = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
                firstPerson = head ~= nil and (cam.CFrame.Position - head.Position).Magnitude < 1.5
            end
            freezeOn = firstPerson and opt.Freeze and cam ~= nil
            if freezeOn then frozenCF = cam.CFrame end
        elseif not want and fpsActive then
            fpsActive = false
            ModalBtn.Modal = false
            freezeOn = false
            frozenCF = nil
            -- Hand the mouse back to the game exactly as it was.
            if savedBehavior then UserInputService.MouseBehavior = savedBehavior end
        end
        if fpsActive then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
    end

    -- The UI counts as open only while the menu frame AND its ScreenGui are shown
    -- (scripts may hide it via ScreenGui.Enabled). While open the real cursor is
    -- forced off every frame (games re-enable it); on close the game's own
    -- MouseIconEnabled value, captured when the menu opened, is put back.
    local savedIcon = UserInputService.MouseIconEnabled
    local cursorActive = false
    local function UIOpen()
        return Library.CursorEnabled and ScreenGui.Parent ~= nil
            and ScreenGui.Enabled and MainFrame.Visible
    end
    local function RefreshCursor(dt)
        FpsUpdate(ScreenGui.Parent ~= nil and ScreenGui.Enabled and MainFrame.Visible)
        local open = UIOpen()
        if open and not cursorActive then
            savedIcon = UserInputService.MouseIconEnabled
            cursorActive = true
        elseif not open and cursorActive then
            cursorActive = false
            UserInputService.MouseIconEnabled = savedIcon
        end
        CursorRoot.Visible = open
        if open then
            UserInputService.MouseIconEnabled = false
            local m = UserInputService:GetMouseLocation()
            CursorRoot.Position = UDim2.new(0, m.X, 0, m.Y)
            UpdateCursor(dt or 0.016, m)
        else
            for n = 1, TRAIL_N do Trail[n].Visible = false end
            table.clear(History)
        end
    end
    table.insert(Library.Connections, RunService.RenderStepped:Connect(RefreshCursor))
    table.insert(Library.Connections, { Connected = true, Disconnect = function(self)
        self.Connected = false
        FpsUpdate(false)
        pcall(function() RunService:UnbindFromRenderStep(FREEZE_NAME) end)
        if cursorActive then UserInputService.MouseIconEnabled = savedIcon end
        if CursorGui then CursorGui:Destroy() end
    end })
    function WindowObj:SetCursorEnabled(v) Library.CursorEnabled = v and true or false; RefreshCursor() end
    RefreshCursor()

    -- =================================================================
    -- Built-in Settings tab (always last)
    -- =================================================================
    -- =================================================================
    -- Draggable HUD overlays (watermark, keybind list). Positions are kept in
    -- Library.Options.__OverlayPos so configs save and restore them.
    -- =================================================================
    local OverlayFrames, OverlayDefaults, OverlayPos = {}, {}, {}
    local OverlayObj = {
        Type = "Positions", Value = OverlayPos,
        Save = function(self) return OverlayPos end,
        Load = function(self, val)
            if type(val) ~= "table" then return end
            for k, v in pairs(val) do
                local f = OverlayFrames[k]
                if f and type(v) == "table" and tonumber(v[1]) and tonumber(v[2]) then
                    OverlayPos[k] = {v[1], v[2]}
                    f.Position = UDim2.new(0, v[1], 0, v[2])
                end
            end
        end,
    }
    OverlayObj.SetValue = function(self, v) self:Load(v) end
    Library.Options.__OverlayPos = OverlayObj

    -- Drag with the left mouse button while the menu is open.
    local function MakeOverlayDraggable(frame, key)
        OverlayFrames[key] = frame
        OverlayDefaults[key] = {frame.Position.X.Offset, frame.Position.Y.Offset}
        frame.Active = true
        local dragging, startMouse, startPos = false, nil, nil
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 and ScreenGui.Enabled and MainFrame.Visible then
                dragging = true
                startMouse = input.Position
                startPos = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)
            end
        end)
        TrackInput(UserInputService.InputChanged, function(input)
            if not dragging or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
            local d = input.Position - startMouse
            local maxX = math.max(0, HudGui.AbsoluteSize.X - frame.AbsoluteSize.X)
            local maxY = math.max(0, HudGui.AbsoluteSize.Y - frame.AbsoluteSize.Y)
            local nx = math.clamp(startPos.X + d.X, 0, maxX)
            local ny = math.clamp(startPos.Y + d.Y, 0, maxY)
            frame.Position = UDim2.new(0, nx, 0, ny)
            OverlayPos[key] = {nx, ny}
        end)
        TrackInput(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
    end

    function WindowObj:ResetOverlays()
        for k, d in pairs(OverlayDefaults) do
            OverlayFrames[k].Position = UDim2.new(0, d[1], 0, d[2])
        end
        table.clear(OverlayPos)
    end

    MakeOverlayDraggable(WatermarkOutline, "Watermark")

    do
        local SettingsTab = WindowObj:CreateTab("Settings", true)
        Library.Window = WindowObj
        Library.SettingsTab = SettingsTab    -- ThemeManager/SaveManager build into this

        local MenuGroup = SettingsTab:CreateGroupBox("Left", "Menu")
        Library.SettingsMenuGroup = MenuGroup
        MenuGroup:AddKeybind("Menu Toggle", Enum.KeyCode.Insert, nil, "__MenuKey")
        TrackInput(UserInputService.InputBegan, function(input, processed)
            if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            local bind = Library.Options.__MenuKey
            if bind and input.KeyCode.Name == bind.Value then
                ScreenGui.Enabled = not ScreenGui.Enabled
            end
        end)
        MenuGroup:AddToggle("Custom Cursor", true, function(v) WindowObj:SetCursorEnabled(v) end, "__CustomCursor")
        MenuGroup:AddToggle("Unlock Mouse (FPS)", true, function(v) Library.MouseOptions.Unlock = v end, "__UnlockMouse")
        MenuGroup:AddToggle("Freeze Camera (FPS)", true, function(v) Library.MouseOptions.Freeze = v end, "__FreezeCamera")
        MenuGroup:AddToggle("Show Watermark", true, function(v)
            WindowObj:SetWatermark(v and (Title .. " | Running") or "")
        end, "__ShowWatermark")
        MenuGroup:AddSlider("Menu Width", 400, 900, Size.X.Offset, function(v)
            MainFrame.Size = UDim2.new(0, v, 0, MainFrame.Size.Y.Offset)
        end, "__MenuWidth")
        MenuGroup:AddSlider("Menu Height", 300, 800, Size.Y.Offset, function(v)
            MainFrame.Size = UDim2.new(0, MainFrame.Size.X.Offset, 0, v)
        end, "__MenuHeight")
        MenuGroup:AddButton("Reset overlay positions", function() WindowObj:ResetOverlays() end)
        MenuGroup:AddButton("Unload script", function() Library:Unload() end)

        -- Live list of keybinds that are currently on / held.
        local KbOutline = Create("Frame", {
            Parent = HudGui, BackgroundColor3 = Library.Theme.OutlineColor,
            Position = UDim2.new(0, 15, 0, 45), Size = UDim2.new(0, 120, 0, 20),
            BorderSizePixel = 0, Visible = false, ZIndex = 50,
            ThemeMap = {BackgroundColor3 = "OutlineColor"}
        })
        local KbInline = Create("Frame", {
            Parent = KbOutline, BackgroundColor3 = Library.Theme.InlineColor,
            Position = UDim2.new(0, 1, 0, 1), Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0, ZIndex = 50, ThemeMap = {BackgroundColor3 = "InlineColor"}
        })
        local KbBg = Create("Frame", {
            Parent = KbInline, BackgroundColor3 = Library.Theme.BackgroundColor,
            Position = UDim2.new(0, 1, 0, 1), Size = UDim2.new(1, -2, 1, -2),
            BorderSizePixel = 0, ZIndex = 50, ThemeMap = {BackgroundColor3 = "BackgroundColor"}
        })
        Create("Frame", {
            Parent = KbBg, BackgroundColor3 = Library.Theme.AccentColor,
            Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, ZIndex = 51,
            ThemeMap = {BackgroundColor3 = "AccentColor"}
        })
        local KbText = Create("TextLabel", {
            Parent = KbBg, BackgroundTransparency = 1, Position = UDim2.new(0, 6, 0, 3),
            Size = UDim2.new(1, -12, 1, -3), Font = Library.Theme.Font, TextSize = 12,
            TextColor3 = Library.Theme.TextColor, TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top, Text = "", ZIndex = 52,
            ThemeMap = {TextColor3 = "TextColor"}
        })
        -- Keybind list: every bound key (standalone binds AND binds attached to
        -- toggles), active ones in the accent colour, others muted.
        MakeOverlayDraggable(KbOutline, "KeybindList")
        KbText.RichText = true
        local kbEnabled, kbTimer, kbLast = true, 0, ""
        MenuGroup:AddToggle("Keybind List", true, function(v)
            kbEnabled = v
            KbOutline.Visible = v
            kbLast = ""
        end, "__KeybindList")

        local function esc(t)
            t = tostring(t):gsub("&", "&amp;")
            t = t:gsub("<", "&lt;")
            return (t:gsub(">", "&gt;"))
        end
        local function hex(c)
            return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
        end

        local function RefreshKeybindList()
            local entries = {}
            for idx, k in pairs(Library.Keybinds) do
                if tostring(idx):sub(1, 2) ~= "__" then
                    local okKey, key = pcall(k.GetKey)
                    if okKey and key and key ~= Enum.KeyCode.Unknown then
                        local okA, active = pcall(k.IsActive)
                        entries[#entries + 1] = {
                            name = k.Name, key = GetBindName(key),
                            mode = k.GetMode(), active = okA and active or false
                        }
                    end
                end
            end
            table.sort(entries, function(a, b) return a.name < b.name end)

            local accent, muted = hex(Library.Theme.AccentColor), hex(Library.Theme.TextMuted)
            local rich, plain = {"Keybinds"}, {"Keybinds"}
            for _, e in ipairs(entries) do
                local line = string.format("[%s] %s (%s)", e.key, e.name, e.mode)
                plain[#plain + 1] = line
                rich[#rich + 1] = string.format('<font color="%s">%s</font>', e.active and accent or muted, esc(line))
            end
            if #entries == 0 then
                plain[#plain + 1] = "(no keybinds)"
                rich[#rich + 1] = string.format('<font color="%s">(no keybinds)</font>', muted)
            end

            local richText = table.concat(rich, "\n")
            if richText ~= kbLast then
                kbLast = richText
                KbText.Text = richText
                local bounds = GetTextBounds(table.concat(plain, "\n"), Library.Theme.Font, 12)
                KbOutline.Size = UDim2.new(0, math.max(110, bounds.X + 18), 0, bounds.Y + 10)
            end
        end

        TrackInput(RunService.Heartbeat, function(dt)
            if not kbEnabled then return end
            KbOutline.Visible = true
            kbTimer = kbTimer + dt
            if kbTimer < 0.1 then return end
            kbTimer = 0
            RefreshKeybindList()
        end)

        local AppGroup = SettingsTab:CreateGroupBox("Left", "Appearance")

        -- UI scale (UIScale on the window; popups keep their own size)
        local MainScale = Create("UIScale", {Parent = MainFrame, Scale = 1})
        AppGroup:AddSlider("UI Scale", 0.7, 1.4, 1, function(v) MainScale.Scale = v end, "__UIScale")

        -- Font: swaps every text element now, and new elements pick it up too.
        local FontNames = {"Code", "Gotham", "SourceSans", "Arial", "RobotoMono", "Ubuntu", "Fantasy", "Bangers"}
        AppGroup:AddDropdown("Font", FontNames, "Code", function(name)
            local font = Enum.Font[name]
            if not font then return end
            Library.Theme.Font = font
            for _, d in ipairs(ScreenGui:GetDescendants()) do
                if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                    d.Font = font
                end
            end
        end, "__UIFont")

        -- Rainbow accent: cycles Theme.AccentColor (throttled; UpdateTheme walks the theme map).
        local rainbowOn, rainbowSpeed, rainbowTimer = false, 0.25, 0
        local preRainbow
        AppGroup:AddToggle("Rainbow Accent", false, function(v)
            if v and not rainbowOn then preRainbow = Library.Theme.AccentColor end
            if not v and rainbowOn and preRainbow then Library:UpdateTheme("AccentColor", preRainbow) end
            rainbowOn = v
        end, "__RainbowAccent")
        AppGroup:AddSlider("Rainbow Speed", 0.05, 1, rainbowSpeed, function(v) rainbowSpeed = v end, "__RainbowSpeed")
        TrackInput(RunService.Heartbeat, function(dt)
            if not rainbowOn then return end
            rainbowTimer = rainbowTimer + dt
            if rainbowTimer < 1 / 20 then return end
            rainbowTimer = 0
            Library:UpdateTheme("AccentColor", Color3.fromHSV((os.clock() * rainbowSpeed) % 1, 0.8, 1))
        end)

        -- Notifications
        AppGroup:AddDropdown("Notify Position", {"Bottom Right", "Bottom Left", "Top Right", "Top Left"}, "Bottom Right", function(v)
            local top = v:find("Top") ~= nil
            local left = v:find("Left") ~= nil
            NotificationContainer.AnchorPoint = Vector2.new(left and 0 or 1, top and 0 or 1)
            NotificationContainer.Position = UDim2.new(left and 0 or 1, left and 15 or -15, top and 0 or 1, top and 15 or -15)
            NotifLayout.VerticalAlignment = top and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Bottom
        end, "__NotifyPosition")
        AppGroup:AddSlider("Notify Duration", 1, 10, 3, function(v) Library.NotifyDuration = v end, "__NotifyDuration")
        AppGroup:AddButton("Test Notification", function() WindowObj:Notify("Notification test", Library.NotifyDuration) end)

        local CursorGroup = SettingsTab:CreateGroupBox("Right", "Cursor")
        local CurCfg = Library.Cursor
        CursorGroup:AddDropdown("Cursor Style", Library.CursorStyles, CurCfg.Style, function(v) CurCfg.Style = v end, "__CursorStyle")
        CursorGroup:AddSlider("Cursor Size", 6, 40, CurCfg.Size, function(v) CurCfg.Size = v end, "__CursorSize")
        CursorGroup:AddToggle("Use Accent Color", true, function(v) CurCfg.UseAccent = v end, "__CursorAccent")
        CursorGroup:AddColorPicker("Cursor Color", CurCfg.Color, function(c) CurCfg.Color = c end, "__CursorColor")
        CursorGroup:AddToggle("Rainbow", false, function(v) CurCfg.Rainbow = v end, "__CursorRainbow")
        CursorGroup:AddToggle("Spin", false, function(v) CurCfg.Spin = v end, "__CursorSpin")
        CursorGroup:AddToggle("Trail", false, function(v) CurCfg.Trail = v end, "__CursorTrail")

        -- Themes + Configuration are part of the UI itself; nothing to wire up.
        Library:SetFolder(options.Folder or Title)
        ThemeManager:_BuildSection(SettingsTab)
        SaveManager:_BuildSection(SettingsTab)
        Library.NativeSettings = true
        if options.AutoLoad ~= false then
            -- Deferred so the script has finished adding its own options first.
            task.defer(function()
                if Library.Unloading or not Library.ScreenGui then return end
                ThemeManager:LoadDefaultTheme()
                SaveManager:LoadAutoloadConfig()
            end)
        end
    end

    -- Handy globals so an executor / MCP session can reach the UI after load.
    local env = (getgenv and getgenv()) or _G
    env.LinoriaLite, env.LinoriaWindow = Library, WindowObj

    return WindowObj
end

return Library
