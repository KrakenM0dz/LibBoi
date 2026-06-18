local HttpService = game:GetService("HttpService")

local SaveManager = {}
SaveManager.Folder = "LinoriaLiteSettings"
SaveManager.Library = nil
SaveManager.Ignore = {}

function SaveManager:SetLibrary(lib)
    self.Library = lib
end

function SaveManager:SetFolder(folderName)
    self.Folder = folderName
    if isfolder and not isfolder(self.Folder) then
        makefolder(self.Folder)
    end
end

function SaveManager:SetIgnoreIndexes(list)
    for _, idx in ipairs(list) do
        self.Ignore[idx] = true
    end
end

function SaveManager:IgnoreThemeSettings()
    self:SetIgnoreIndexes({
        "ThemeManager_BackgroundColor", "ThemeManager_MainColor", "ThemeManager_AccentColor",
        "ThemeManager_OutlineColor", "ThemeManager_TextColor", "ThemeManager_ThemeList",
        "ThemeManager_CustomThemeName", "ThemeManager_CustomThemeList",
        "SaveManager_ConfigName", "SaveManager_ConfigList"
    })
end

function SaveManager:CheckFolder()
    if isfolder and not isfolder(self.Folder) then
        makefolder(self.Folder)
    end
    if isfolder and not isfolder(self.Folder .. "/themes") then
        makefolder(self.Folder .. "/themes")
    end
end

function SaveManager:Save(name)
    if not writefile then return false end
    self:CheckFolder()
    
    local data = {}
    for idx, obj in pairs(self.Library.Options) do
        if not self.Ignore[idx] then
            if type(obj.Save) == "function" then
                data[idx] = { Type = obj.Type, Value = obj:Save() }
            end
        end
    end
    
    local success, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if success then
        writefile(self.Folder .. "/" .. name .. ".json", encoded)
        return true
    end
    return false
end

function SaveManager:Load(name)
    if not readfile then return false end
    local path = self.Folder .. "/" .. name .. ".json"
    
    local success, content = pcall(readfile, path)
    if not success then return false end
    
    local decodedSuccess, data = pcall(HttpService.JSONDecode, HttpService, content)
    if not decodedSuccess or type(data) ~= "table" then return false end
    
    for idx, savedObj in pairs(data) do
        local obj = self.Library.Options[idx]
        if obj and obj.Type == savedObj.Type and not self.Ignore[idx] then
            if type(obj.Load) == "function" then
                obj:Load(savedObj.Value)
            end
        end
    end
    return true
end

function SaveManager:RefreshConfigList()
    local list = {}
    if listfiles and isfolder and isfolder(self.Folder) then
        for _, file in ipairs(listfiles(self.Folder)) do
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

function SaveManager:LoadAutoloadConfig()
    if readfile then
        local success, content = pcall(readfile, self.Folder .. "/autoload.txt")
        if success and content ~= "" then
            self:Load(content)
        end
    end
end

function SaveManager:BuildConfigSection(Tab)
    local ConfigGroup = Tab:CreateGroupBox("Right", "Configuration")
    
    local cfgName = ConfigGroup:AddInput("Config name", "", function() end, "SaveManager_ConfigName")
    local cfgList = ConfigGroup:AddDropdown("Config list", self:RefreshConfigList(), nil, function() end, "SaveManager_ConfigList")
    
    ConfigGroup:AddButton("Create config", function()
        local name = cfgName.Value
        if name and name ~= "" then
            self:Save(name)
            cfgList:RefreshOptions(self:RefreshConfigList())
            cfgList:SetValue(name)
            self.Library:Notify("Created config: " .. name)
        end
    end)
    
    ConfigGroup:AddButton("Load config", function()
        local name = cfgList.Value
        if name and name ~= "" then
            if self:Load(name) then
                self.Library:Notify("Loaded config: " .. name)
            else
                self.Library:Notify("Failed to load: " .. name)
            end
        end
    end)
    
    ConfigGroup:AddButton("Overwrite config", function()
        local name = cfgList.Value
        if name and name ~= "" then
            self:Save(name)
            self.Library:Notify("Overwrote config: " .. name)
        end
    end)
    
    ConfigGroup:AddButton("Delete config", function()
        local name = cfgList.Value
        if name and name ~= "" then
            local path = self.Folder .. "/" .. name .. ".json"
            if isfile and isfile(path) and delfile then
                delfile(path)
                cfgList:RefreshOptions(self:RefreshConfigList())
                cfgList:SetValue(self:RefreshConfigList()[1] or "")
                self.Library:Notify("Deleted config: " .. name)
            end
        end
    end)
    
    ConfigGroup:AddButton("Refresh list", function()
        cfgList:RefreshOptions(self:RefreshConfigList())
    end)
    
    local autoLabel = ConfigGroup:AddLabel("Current autoload config: none")
    if readfile then
        local success, content = pcall(readfile, self.Folder .. "/autoload.txt")
        if success and content ~= "" then
            autoLabel:SetText("Current autoload config: " .. content)
        end
    end
    
    ConfigGroup:AddButton("Set as autoload", function()
        local name = cfgList.Value
        if name and name ~= "" and writefile then
            writefile(self.Folder .. "/autoload.txt", name)
            autoLabel:SetText("Current autoload config: " .. name)
            self.Library:Notify("Set autoload config to: " .. name)
        end
    end)
end

return SaveManager
