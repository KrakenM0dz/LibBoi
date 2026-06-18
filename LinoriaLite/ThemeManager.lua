local HttpService = game:GetService("HttpService")

local ThemeManager = {}
ThemeManager.Folder = "LinoriaLiteSettings"
ThemeManager.Library = nil

ThemeManager.BuiltInThemes = {
    ["Default"] = {
        TextColor = Color3.fromHex("ffffff"),
        MainColor = Color3.fromHex("1c1c1c"),
        AccentColor = Color3.fromHex("0055ff"),
        BackgroundColor = Color3.fromHex("141414"),
        OutlineColor = Color3.fromHex("323232"),
    },
    ["BBot"] = {
        TextColor = Color3.fromHex("ffffff"),
        MainColor = Color3.fromHex("1e1e1e"),
        AccentColor = Color3.fromHex("7e48a3"),
        BackgroundColor = Color3.fromHex("232323"),
        OutlineColor = Color3.fromHex("141414"),
    },
    ["Fatality"] = {
        TextColor = Color3.fromHex("ffffff"),
        MainColor = Color3.fromHex("1e1842"),
        AccentColor = Color3.fromHex("c50754"),
        BackgroundColor = Color3.fromHex("191335"),
        OutlineColor = Color3.fromHex("3c355d"),
    },
    ["Jester"] = {
        TextColor = Color3.fromHex("ffffff"),
        MainColor = Color3.fromHex("242424"),
        AccentColor = Color3.fromHex("db4467"),
        BackgroundColor = Color3.fromHex("1c1c1c"),
        OutlineColor = Color3.fromHex("373737"),
    },
    ["Mint"] = {
        TextColor = Color3.fromHex("ffffff"),
        MainColor = Color3.fromHex("242424"),
        AccentColor = Color3.fromHex("3db488"),
        BackgroundColor = Color3.fromHex("1c1c1c"),
        OutlineColor = Color3.fromHex("373737"),
    },
    ["Tokyo Night"] = {
        TextColor = Color3.fromHex("ffffff"),
        MainColor = Color3.fromHex("191925"),
        AccentColor = Color3.fromHex("6759b3"),
        BackgroundColor = Color3.fromHex("16161f"),
        OutlineColor = Color3.fromHex("323232"),
    },
    ["Ubuntu"] = {
        TextColor = Color3.fromHex("ffffff"),
        MainColor = Color3.fromHex("3e3e3e"),
        AccentColor = Color3.fromHex("e2581e"),
        BackgroundColor = Color3.fromHex("323232"),
        OutlineColor = Color3.fromHex("191919"),
    },
    ["Quartz"] = {
        TextColor = Color3.fromHex("ffffff"),
        MainColor = Color3.fromHex("232330"),
        AccentColor = Color3.fromHex("426e87"),
        BackgroundColor = Color3.fromHex("1d1b26"),
        OutlineColor = Color3.fromHex("27232f"),
    },
}

function ThemeManager:SetLibrary(lib)
    self.Library = lib
end

function ThemeManager:SetFolder(folderName)
    self.Folder = folderName
    if isfolder and not isfolder(self.Folder) then
        makefolder(self.Folder)
    end
    if isfolder and not isfolder(self.Folder .. "/themes") then
        makefolder(self.Folder .. "/themes")
    end
end

function ThemeManager:ApplyTheme(themeData)
    for key, color in pairs(themeData) do
        if self.Library.Theme[key] then
            self.Library:UpdateTheme(key, color)
            
            -- update color pickers if they exist
            local picker = self.Library.Options["ThemeManager_" .. key]
            if picker then
                picker:SetValue(color)
            end
        end
    end
end

function ThemeManager:RefreshCustomThemes()
    local list = {}
    if listfiles and isfolder and isfolder(self.Folder .. "/themes") then
        for _, file in ipairs(listfiles(self.Folder .. "/themes")) do
            if file:sub(-5) == ".json" then
                local fileName = file:match("([^/\\]+)%.json$")
                if fileName then
                    table.insert(list, fileName)
                end
            end
        end
    end
    return list
end

function ThemeManager:SaveCustomTheme(name)
    if not writefile then return false end
    local themeData = {
        BackgroundColor = {R = self.Library.Theme.BackgroundColor.R, G = self.Library.Theme.BackgroundColor.G, B = self.Library.Theme.BackgroundColor.B},
        MainColor = {R = self.Library.Theme.MainColor.R, G = self.Library.Theme.MainColor.G, B = self.Library.Theme.MainColor.B},
        AccentColor = {R = self.Library.Theme.AccentColor.R, G = self.Library.Theme.AccentColor.G, B = self.Library.Theme.AccentColor.B},
        OutlineColor = {R = self.Library.Theme.OutlineColor.R, G = self.Library.Theme.OutlineColor.G, B = self.Library.Theme.OutlineColor.B},
        TextColor = {R = self.Library.Theme.TextColor.R, G = self.Library.Theme.TextColor.G, B = self.Library.Theme.TextColor.B},
    }
    local success, encoded = pcall(HttpService.JSONEncode, HttpService, themeData)
    if success then
        writefile(self.Folder .. "/themes/" .. name .. ".json", encoded)
        return true
    end
    return false
end

function ThemeManager:LoadCustomTheme(name)
    if not readfile then return false end
    local success, content = pcall(readfile, self.Folder .. "/themes/" .. name .. ".json")
    if not success then return false end
    
    local decodedSuccess, data = pcall(HttpService.JSONDecode, HttpService, content)
    if not decodedSuccess or type(data) ~= "table" then return false end
    
    local themeData = {}
    for k, v in pairs(data) do
        if type(v) == "table" and v.R then
            themeData[k] = Color3.new(v.R, v.G, v.B)
        end
    end
    self:ApplyTheme(themeData)
    return true
end

function ThemeManager:LoadDefaultTheme()
    if readfile then
        local success, content = pcall(readfile, self.Folder .. "/themes/default.txt")
        if success and content ~= "" then
            if self.BuiltInThemes[content] then
                self:ApplyTheme(self.BuiltInThemes[content])
                if self.Library.Options.ThemeManager_ThemeList then
                    self.Library.Options.ThemeManager_ThemeList:SetValue(content)
                end
            else
                self:LoadCustomTheme(content)
                if self.Library.Options.ThemeManager_CustomThemeList then
                    self.Library.Options.ThemeManager_CustomThemeList:SetValue(content)
                end
            end
        end
    end
end

function ThemeManager:BuildThemeSection(Tab)
    local ThemeGroup = Tab:CreateGroupBox("Left", "Themes")
    
    ThemeGroup:AddColorPicker("Background color", self.Library.Theme.BackgroundColor, function(color)
        self.Library:UpdateTheme("BackgroundColor", color)
    end, "ThemeManager_BackgroundColor")
    
    ThemeGroup:AddColorPicker("Main color", self.Library.Theme.MainColor, function(color)
        self.Library:UpdateTheme("MainColor", color)
    end, "ThemeManager_MainColor")
    
    ThemeGroup:AddColorPicker("Accent color", self.Library.Theme.AccentColor, function(color)
        self.Library:UpdateTheme("AccentColor", color)
    end, "ThemeManager_AccentColor")
    
    ThemeGroup:AddColorPicker("Outline color", self.Library.Theme.OutlineColor, function(color)
        self.Library:UpdateTheme("OutlineColor", color)
    end, "ThemeManager_OutlineColor")
    
    ThemeGroup:AddColorPicker("Font color", self.Library.Theme.TextColor, function(color)
        self.Library:UpdateTheme("TextColor", color)
    end, "ThemeManager_TextColor")
    
    local builtinList = {}
    for k, _ in pairs(self.BuiltInThemes) do table.insert(builtinList, k) end
    
    ThemeGroup:AddDropdown("Theme list", builtinList, "Default", function(theme)
        if self.BuiltInThemes[theme] then
            self:ApplyTheme(self.BuiltInThemes[theme])
        end
    end, "ThemeManager_ThemeList")
    
    ThemeGroup:AddButton("Set as default", function()
        local name = self.Library.Options.ThemeManager_ThemeList.Value
        if writefile then
            writefile(self.Folder .. "/themes/default.txt", name)
            self.Library:Notify("Set default theme to: " .. name)
        end
    end)
    
    ThemeGroup:AddInput("Custom theme name", "", function() end, "ThemeManager_CustomThemeName")
    local customList = ThemeGroup:AddDropdown("Custom themes", self:RefreshCustomThemes(), nil, function() end, "ThemeManager_CustomThemeList")
    
    ThemeGroup:AddButton("Save theme", function()
        local name = self.Library.Options.ThemeManager_CustomThemeName.Value
        if name and name ~= "" then
            self:SaveCustomTheme(name)
            customList:RefreshOptions(self:RefreshCustomThemes())
            customList:SetValue(name)
            self.Library:Notify("Saved custom theme: " .. name)
        end
    end)
    
    ThemeGroup:AddButton("Load theme", function()
        local name = customList.Value
        if name and name ~= "" then
            if self:LoadCustomTheme(name) then
                self.Library:Notify("Loaded custom theme: " .. name)
            else
                self.Library:Notify("Failed to load theme: " .. name)
            end
        end
    end)
    
    ThemeGroup:AddButton("Delete theme", function()
        local name = customList.Value
        if name and name ~= "" then
            local path = self.Folder .. "/themes/" .. name .. ".json"
            if isfile and isfile(path) and delfile then
                delfile(path)
                customList:RefreshOptions(self:RefreshCustomThemes())
                customList:SetValue(self:RefreshCustomThemes()[1] or "")
                self.Library:Notify("Deleted custom theme: " .. name)
            end
        end
    end)
    
    ThemeGroup:AddButton("Refresh list", function()
        customList:RefreshOptions(self:RefreshCustomThemes())
    end)
    
    ThemeGroup:AddButton("Set as default", function()
        local name = customList.Value
        if name and name ~= "" and writefile then
            writefile(self.Folder .. "/themes/default.txt", name)
            self.Library:Notify("Set default theme to: " .. name)
        end
    end)
end

return ThemeManager
