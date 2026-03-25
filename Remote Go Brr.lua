-- Remote Go Brr v0.1.0
-- // Cleanup
if shared.AEH_Cleanup then pcall(shared.AEH_Cleanup) end
shared.AEH_Running = true

-- // Services
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local LocalPlayer       = Players.LocalPlayer

-- // Rayfield
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- // State
local Config = {
    Enabled        = false,
    FireIntervalMs = 100,
    GlobalKeybinds = true,
    MinIntervalMs  = nil,
    MaxIntervalMs  = nil,
    AntiAFK        = false,
    ShowNonFirable = false,
}

local Connections    = {}
local Hooked         = {}
local HookedCount    = 0
local TotalFireCount = 0
local IsLogging      = false
local RemoteLog      = {}
local ExcludeList    = {}
local SpyHookActive  = shared.AEH_SpyHookActive or false
local BrowseResults  = {}
local SavePrefix     = "RemoteGoBrr_" .. game.PlaceId .. "_"
local OldSavePrefix  = "RemoteHooker_" .. game.PlaceId .. "_"
local HookedDirty    = true
local LastStatsText  = ""
local SessionStart   = tick()
local ScanPath       = "ReplicatedStorage.remotes"

-- // Utility
local function formatNumber(n)
    if n >= 1000000 then return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then return string.format("%.1fK", n / 1000) end
    return tostring(n)
end

local function fullPath(inst)
    local parts = {}
    local cur = inst
    while cur and cur ~= game do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(parts, ".")
end

local function parseArgs(argStr)
    if not argStr or argStr == "" then return {n = 0} end
    local fn_str = "local function p(...) local t = {...}; t.n = select('#', ...); return t end return p(" .. argStr .. ")"
    local fn = loadstring(fn_str)
    if fn then
        local env = setmetatable({
            LocalPlayer = LocalPlayer, Player = LocalPlayer,
            workspace = workspace, game = game,
        }, { __index = getfenv() })
        setfenv(fn, env)
        local ok, result = pcall(fn)
        if ok and type(result) == "table" then return result end
    end
    return {n = 0}
end

local function isFirable(inst)
    return inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent")
end

local function shortClass(inst)
    if inst:IsA("UnreliableRemoteEvent") then return "Unreliable"
    elseif inst:IsA("RemoteEvent")       then return "Remote"
    elseif inst:IsA("RemoteFunction")    then return "Function"
    elseif inst:IsA("BindableEvent")     then return "Bindable"
    elseif inst:IsA("Folder")            then return "Folder"
    else return inst.ClassName end
end

local function shortClassFromName(className)
    if className == "UnreliableRemoteEvent" then return "Unreliable"
    elseif className == "RemoteEvent" then return "Remote"
    elseif className == "RemoteFunction" then return "Function"
    elseif className == "BindableEvent" then return "Bindable"
    else return className end
end

local function isUIVisible()
    local ok, visible = pcall(function() return Rayfield:IsVisible() end)
    return ok and visible
end

-- // Save / Load
local function saveHookedRemotes()
    if not writefile then return end
    local data = {}
    for remote, hookData in pairs(Hooked) do
        if remote and remote.Parent then
            table.insert(data, {
                path       = fullPath(remote),
                argString  = hookData.argString or "",
                intervalMs = hookData.intervalMs,
                burstLimit = hookData.burstLimit,
            })
        end
    end
    pcall(writefile, SavePrefix .. "hooked.json", HttpService:JSONEncode(data))
end

local function saveExcludeList()
    if not writefile then return end
    local names = {}
    for name in pairs(ExcludeList) do table.insert(names, name) end
    pcall(writefile, SavePrefix .. "exclude.json", HttpService:JSONEncode(names))
end

-- // Forward Declarations
local hookRemote, unhookRemote, clearAll
local refreshHookedList, refreshStatus
local refreshExcludeList
local doScanRemotes, doStartSpy, doStopSpy, toggleSpy, doCopyResults

-- // Load Functions
local function loadHookedRemotes()
    if not readfile then return end
    local ok, raw = pcall(readfile, SavePrefix .. "hooked.json")
    if not ok or not raw or raw == "" then
        ok, raw = pcall(readfile, OldSavePrefix .. "hooked.json")
        if not ok or not raw or raw == "" then return end
        task.defer(saveHookedRemotes)
    end
    local decoded
    local ok2 = pcall(function() decoded = HttpService:JSONDecode(raw) end)
    if not ok2 or not decoded then return end

    local loaded = 0
    local failed = {}
    for _, entry in ipairs(decoded) do
        local parts = string.split(entry.path, ".")
        local current = game
        local valid = true
        for _, name in ipairs(parts) do
            local child = current:FindFirstChild(name)
            if not child then valid = false; break end
            current = child
        end
        if valid and isFirable(current) and not Hooked[current] then
            hookRemote(current, entry.argString or "")
            if entry.intervalMs then Hooked[current].intervalMs = entry.intervalMs end
            if entry.burstLimit then Hooked[current].burstLimit = entry.burstLimit end
            loaded = loaded + 1
        else
            table.insert(failed, { path = entry.path, argString = entry.argString or "", intervalMs = entry.intervalMs, burstLimit = entry.burstLimit })
        end
    end

    if #failed > 0 then
        task.delay(5, function()
            local retryLoaded = 0
            for _, entry in ipairs(failed) do
                local parts = string.split(entry.path, ".")
                local current = game
                local valid = true
                for _, name in ipairs(parts) do
                    local child = current:FindFirstChild(name)
                    if not child then valid = false; break end
                    current = child
                end
                if valid and isFirable(current) and not Hooked[current] then
                    hookRemote(current, entry.argString)
                    if entry.intervalMs then Hooked[current].intervalMs = entry.intervalMs end
                    if entry.burstLimit then Hooked[current].burstLimit = entry.burstLimit end
                    retryLoaded = retryLoaded + 1
                end
            end
            if retryLoaded > 0 then
                HookedDirty = true
                if refreshHookedList then refreshHookedList() end
                Rayfield:Notify({ Title = "Retry loaded " .. retryLoaded, Content = "Late-spawning remotes restored.", Duration = 3 })
            end
        end)
    end

    if loaded > 0 then
        Rayfield:Notify({
            Title   = "Loaded " .. loaded .. " remote(s)",
            Content = #failed > 0 and (#failed .. " pending retry...") or "All restored.",
            Duration = 4,
        })
    end
end

local function loadExcludeList()
    if not readfile then return end
    local ok, raw = pcall(readfile, SavePrefix .. "exclude.json")
    if not ok or not raw or raw == "" then
        ok, raw = pcall(readfile, OldSavePrefix .. "exclude.json")
        if not ok or not raw or raw == "" then return end
        task.defer(saveExcludeList)
    end
    local ok2, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok2 or not decoded then return end
    for _, name in ipairs(decoded) do ExcludeList[name] = true end
    if refreshExcludeList then refreshExcludeList() end
end

local function resolveHookedRemote(text)
    local idx = tonumber(text)
    if idx then
        local i = 0
        for remote, data in pairs(Hooked) do
            i = i + 1
            if i == idx then return remote, data end
        end
        return nil, nil
    end
    for remote, data in pairs(Hooked) do
        if remote.Name == text then return remote, data end
    end
    return nil, nil
end

-- // Window
local Window = Rayfield:CreateWindow({
    Name            = "Remote Go Brr v0.1.0",
    Icon            = 0,
    LoadingTitle    = "Remote Go Brr",
    LoadingSubtitle = "v0.1.0",
    Theme           = "Default",
    ToggleUIKeybind = Enum.KeyCode.LeftControl,
    ConfigurationSaving = { Enabled = false },
})

-- // Tab 1 - Main
local MainTab = Window:CreateTab("Main", "zap")

MainTab:CreateSection("Status")

local StatusLabel = MainTab:CreateParagraph({ Title = "Engine", Content = "OFF  |  0 hooked" })
local StatsLabel = MainTab:CreateParagraph({ Title = "Stats", Content = "Total: 0  |  0/sec" })

local AutoToggle = MainTab:CreateToggle({
    Name = "Enable Auto-Fire  [F]",
    CurrentValue = false,
    Flag = "RH_Enabled",
    Callback = function(val)
        Config.Enabled = val
        if refreshStatus then refreshStatus() end
        Rayfield:Notify({
            Title   = val and "Auto-Fire ON" or "Auto-Fire OFF",
            Content = val and (HookedCount .. " remote(s)") or "Stopped",
            Duration = 2,
        })
    end,
})

MainTab:CreateSection("Hooked Remotes")

local HookedParagraph = MainTab:CreateParagraph({ Title = "Hooked (0)", Content = "None yet. Use Browse or Spy tab." })

MainTab:CreateButton({ Name = "Clear All  [X]", Callback = function() if clearAll then clearAll() end end })

MainTab:CreateSection("Remote Actions")

MainTab:CreateInput({
    Name = "Unhook by name or index",
    CurrentValue = "",
    PlaceholderText = "name or index number",
    RemoveTextAfterFocusLost = true,
    Callback = function(text)
        if text == "" then return end
        local remote = resolveHookedRemote(text)
        if remote then
            unhookRemote(remote)
        else
            Rayfield:Notify({ Title = "Not hooked", Content = text, Duration = 2 })
        end
    end,
})

MainTab:CreateInput({
    Name = "Pause/Resume by name or index",
    CurrentValue = "",
    PlaceholderText = "name or index number",
    RemoveTextAfterFocusLost = true,
    Callback = function(text)
        if text == "" then return end
        local remote, data = resolveHookedRemote(text)
        if remote and data then
            data.paused = not data.paused
            HookedDirty = true
            if refreshHookedList then refreshHookedList() end
            Rayfield:Notify({ Title = data.paused and "Paused" or "Resumed", Content = remote.Name, Duration = 2 })
        else
            Rayfield:Notify({ Title = "Not hooked", Content = text, Duration = 2 })
        end
    end,
})

-- // Tab 2 - Browse
local BrowseTab = Window:CreateTab("Browse", "folder")

BrowseTab:CreateSection("Scan")

BrowseTab:CreateInput({
    Name = "Scan Path",
    CurrentValue = "ReplicatedStorage.remotes",
    PlaceholderText = "ReplicatedStorage.remotes",
    RemoveTextAfterFocusLost = false,
    Callback = function(text)
        if text == "" then ScanPath = "ReplicatedStorage.remotes"; return end
        ScanPath = text
    end,
})

local BrowseParagraph = BrowseTab:CreateParagraph({ Title = "Scan Results", Content = "Scan to populate." })

doScanRemotes = function(fullGame)
    local target
    if fullGame then
        target = game
    else
        target = game
        for _, part in ipairs(string.split(ScanPath, ".")) do
            if part ~= "" then
                target = target:FindFirstChild(part)
                if not target then
                    BrowseParagraph:Set({ Title = "Error", Content = "Path not found: " .. ScanPath })
                    return
                end
            end
        end
    end

    BrowseResults = {}
    local lines = {}
    local idx = 0

    for _, desc in ipairs(target:GetDescendants()) do
        if isFirable(desc) then
            idx = idx + 1
            if idx > 1500 then break end
            table.insert(BrowseResults, desc)
            local hooked = Hooked[desc] and " [HOOKED]" or ""
            table.insert(lines,
                idx .. ".  " .. desc.Name ..
                "  (" .. shortClass(desc) .. ")" .. hooked ..
                (fullGame and ("\n      " .. fullPath(desc)) or ""))
        end
    end

    if Config.ShowNonFirable and not fullGame then
        table.insert(lines, "")
        table.insert(lines, "-- Non-firable --")
        local nfc = 0
        for _, desc in ipairs(target:GetDescendants()) do
            if not isFirable(desc) and #desc:GetChildren() == 0 then
                nfc = nfc + 1
                if nfc > 500 then break end
                table.insert(lines, "    " .. desc.Name .. "  (" .. shortClass(desc) .. ")")
            end
        end
    end

    BrowseParagraph:Set({
        Title   = idx .. " firable" .. (fullGame and " (game-wide)" or ""),
        Content = #lines > 0 and table.concat(lines, "\n") or "None found.",
    })
end

BrowseTab:CreateButton({ Name = "Scan Path  [G]", Callback = function() if doScanRemotes then doScanRemotes(false) end end })
BrowseTab:CreateButton({ Name = "Full Game Scan", Callback = function() if doScanRemotes then doScanRemotes(true) end end })

BrowseTab:CreateSection("Hook from List")

BrowseTab:CreateInput({
    Name = "Hook by index",
    CurrentValue = "",
    PlaceholderText = "1  or  1,3  or  all",
    RemoveTextAfterFocusLost = true,
    Callback = function(text)
        if #BrowseResults == 0 then Rayfield:Notify({ Title = "Scan first", Duration = 2 }); return end
        text = string.lower(string.gsub(text, "%s+", ""))
        local toHook = {}
        if text == "all" then
            for i = 1, #BrowseResults do table.insert(toHook, i) end
        else
            for part in string.gmatch(text, "[^,]+") do
                local num = tonumber(part)
                if num and BrowseResults[num] then table.insert(toHook, num) end
            end
        end
        if #toHook == 0 then return end
        local names = {}
        for _, i in ipairs(toHook) do
            local r = BrowseResults[i]
            if r and not Hooked[r] then
                hookRemote(r, "")
                table.insert(names, r.Name .. " (" .. shortClass(r) .. ")")
            end
        end
        Rayfield:Notify({ Title = "Hooked " .. #names, Content = table.concat(names, "\n"), Duration = 3 })
    end,
})

BrowseTab:CreateSection("Quick Actions")

local QuickActionType = "Hook"
BrowseTab:CreateDropdown({
    Name = "Action Type",
    Options = {"Hook", "Copy Code"},
    CurrentOption = {"Hook"},
    MultipleOptions = false,
    Flag = "BrowseActionType",
    Callback = function(Options) QuickActionType = Options[1] or Options end,
})

BrowseTab:CreateInput({
    Name = "Remote Name",
    CurrentValue = "",
    PlaceholderText = "e.g. click_xp",
    RemoveTextAfterFocusLost = true,
    Callback = function(text)
        if text == "" then return end
        local remote = ReplicatedStorage:FindFirstChild(text, true) or game:FindFirstChild(text, true)
        if not remote or not isFirable(remote) then
            Rayfield:Notify({ Title = "Not found or not firable", Content = text, Duration = 2 })
            return
        end
        if QuickActionType == "Copy Code" then
            local path = fullPath(remote)
            local args = Hooked[remote] and Hooked[remote].argString or ""
            local method = remote:IsA("RemoteFunction") and "InvokeServer" or "FireServer"
            local code = "game." .. path .. ":" .. method .. "(" .. args .. ")"
            if setclipboard then
                setclipboard(code)
                Rayfield:Notify({ Title = "Copied Code", Content = code, Duration = 3 })
            end
        else
            if Hooked[remote] then Rayfield:Notify({ Title = "Already hooked", Duration = 2 }); return end
            hookRemote(remote, "")
            Rayfield:Notify({ Title = "Hooked", Content = remote.Name .. " (" .. shortClass(remote) .. ")", Duration = 3 })
        end
    end,
})

-- // Tab 3 - Spy
local SpyTab = Window:CreateTab("Spy", "search")

SpyTab:CreateSection("Controls")

local SpyStatusLabel = SpyTab:CreateParagraph({ Title = "Spy Status", Content = "Idle" })

local LogParagraph = SpyTab:CreateParagraph({ Title = "Captured", Content = "--" })

doStartSpy = function()
    if IsLogging then Rayfield:Notify({ Title = "Already running", Duration = 2 }); return end
    if not hookmetamethod then Rayfield:Notify({ Title = "Error", Content = "hookmetamethod not available", Duration = 3 }); return end

    RemoteLog = {}
    IsLogging = true
    SpyStatusLabel:Set({ Title = "Spy Status", Content = "RUNNING - click things in-game" })

    if not SpyHookActive then
        SpyHookActive = true
        shared.AEH_SpyHookActive = true
        local oldNc
        oldNc = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if IsLogging then
                local isFire   = (method == "FireServer" and (self:IsA("RemoteEvent") or self:IsA("UnreliableRemoteEvent")))
                local isInvoke = (method == "InvokeServer" and self:IsA("RemoteFunction"))
                if (isFire or isInvoke) and not ExcludeList[self.Name] then
                    local already = false
                    for _, entry in ipairs(RemoteLog) do
                        if entry.name == self.Name then already = true; break end
                    end
                    if not already then
                        local argStrs = {}
                        for _, arg in ipairs({...}) do
                            local t = typeof(arg)
                            if t == "string" then table.insert(argStrs, '"' .. tostring(arg) .. '"')
                            elseif t == "Instance" then table.insert(argStrs, fullPath(arg))
                            else table.insert(argStrs, tostring(arg)) end
                        end
                        table.insert(RemoteLog, {
                            remote = self, name = self.Name, class = self.ClassName,
                            path = fullPath(self), argStrs = argStrs,
                        })
                    end
                end
            end
            return oldNc(self, ...)
        end)
    end

    Rayfield:Notify({ Title = "Spy Started", Content = "Click buttons in-game, then Stop.", Duration = 3 })
end

SpyTab:CreateButton({ Name = "Start Spy  [H]", Callback = function() if doStartSpy then doStartSpy() end end })

doStopSpy = function()
    if not IsLogging then Rayfield:Notify({ Title = "Not running", Duration = 2 }); return end
    IsLogging = false
    SpyStatusLabel:Set({ Title = "Spy Status", Content = "Stopped  (" .. #RemoteLog .. " captured)" })
    Rayfield:Notify({ Title = "Spy Stopped", Content = #RemoteLog .. " remote(s) captured.", Duration = 3 })

    if #RemoteLog == 0 then
        LogParagraph:Set({ Title = "Nothing Captured", Content = "No remotes fired. Check exclude list." })
        return
    end

    local lines = {}
    for i, entry in ipairs(RemoteLog) do
        local cls = shortClassFromName(entry.class)
        local args = #entry.argStrs > 0 and table.concat(entry.argStrs, ", ") or "(no args)"
        lines[i] = i .. ".  " .. entry.name .. "  (" .. cls .. ")" ..
                   "\n     " .. entry.path ..
                   "\n     Args: " .. args
    end
    LogParagraph:Set({ Title = "Captured " .. #RemoteLog, Content = table.concat(lines, "\n\n") })
end

SpyTab:CreateButton({ Name = "Stop and Show  [H]", Callback = function() if doStopSpy then doStopSpy() end end })

toggleSpy = function()
    if IsLogging then doStopSpy() else doStartSpy() end
end

doCopyResults = function()
    if #RemoteLog == 0 then Rayfield:Notify({ Title = "Nothing to copy", Content = "Run spy first.", Duration = 2 }); return end
    local lines = {}
    for i, entry in ipairs(RemoteLog) do
        local args = #entry.argStrs > 0 and table.concat(entry.argStrs, ", ") or "(no args)"
        lines[i] = i .. ". " .. entry.name .. " - " .. entry.path .. " - Args: " .. args
    end
    if setclipboard then
        setclipboard(table.concat(lines, "\n"))
        Rayfield:Notify({ Title = "Copied", Content = #RemoteLog .. " remote(s)", Duration = 2 })
    else
        Rayfield:Notify({ Title = "Error", Content = "setclipboard not available", Duration = 3 })
    end
end

SpyTab:CreateButton({ Name = "Copy Results  [C]", Callback = function() if doCopyResults then doCopyResults() end end })

SpyTab:CreateSection("Hook from Spy Results")

SpyTab:CreateInput({
    Name = "Hook from results",
    CurrentValue = "",
    PlaceholderText = "1  or  1,3  or  all",
    RemoveTextAfterFocusLost = true,
    Callback = function(text)
        if #RemoteLog == 0 then Rayfield:Notify({ Title = "Run spy first", Duration = 2 }); return end
        text = string.lower(string.gsub(text, "%s+", ""))
        local toHook = {}
        if text == "all" then
            for i = 1, #RemoteLog do table.insert(toHook, i) end
        else
            for part in string.gmatch(text, "[^,]+") do
                local num = tonumber(part)
                if num and RemoteLog[num] then table.insert(toHook, num) end
            end
        end
        if #toHook == 0 then Rayfield:Notify({ Title = "Invalid input", Duration = 2 }); return end
        local names = {}
        for _, idx in ipairs(toHook) do
            local entry = RemoteLog[idx]
            if entry and not Hooked[entry.remote] then
                hookRemote(entry.remote, "")
                table.insert(names, entry.name)
            end
        end
        Rayfield:Notify({ Title = "Hooked " .. #names, Content = table.concat(names, "\n"), Duration = 3 })
    end,
})

SpyTab:CreateSection("Exclude List")

local ExcludeParagraph = SpyTab:CreateParagraph({ Title = "Excluded (0)", Content = "Add names to filter from spy." })

refreshExcludeList = function()
    local names = {}
    for name in pairs(ExcludeList) do table.insert(names, "- " .. name) end
    ExcludeParagraph:Set({
        Title   = "Excluded (" .. #names .. ")",
        Content = #names > 0 and table.concat(names, "\n") or "None.",
    })
end

SpyTab:CreateInput({
    Name = "Add to exclude", CurrentValue = "", PlaceholderText = "e.g. Received",
    RemoveTextAfterFocusLost = true,
    Callback = function(text)
        if text == "" then return end
        ExcludeList[text] = true
        refreshExcludeList()
        saveExcludeList()
    end,
})

SpyTab:CreateInput({
    Name = "Remove from exclude", CurrentValue = "", PlaceholderText = "e.g. Received",
    RemoveTextAfterFocusLost = true,
    Callback = function(text)
        if text == "" then return end
        if ExcludeList[text] then
            ExcludeList[text] = nil
            refreshExcludeList()
            saveExcludeList()
        end
    end,
})

-- // Tab 4 - Settings
local SettingsTab = Window:CreateTab("Settings", "settings")

SettingsTab:CreateSection("Fire Configuration")

SettingsTab:CreateInput({
    Name = "Fire Interval (ms)",
    CurrentValue = "100",
    PlaceholderText = "100",
    RemoveTextAfterFocusLost = false,
    Flag = "IntervalInput",
    Callback = function(text)
        local num = tonumber(text)
        if not num then Rayfield:Notify({ Title = "Error", Content = "Enter a number", Duration = 2 }); return end
        num = math.floor(math.max(1, num))
        Config.FireIntervalMs = num
        Rayfield:Notify({ Title = num .. "ms  (~" .. string.format("%.0f", 1000/num) .. "/sec)", Duration = 2 })
    end,
})

SettingsTab:CreateInput({
    Name = "Min Interval (ms)",
    CurrentValue = "",
    PlaceholderText = "Leave blank to use Fire Interval",
    RemoveTextAfterFocusLost = false,
    Flag = "MinIntervalInput",
    Callback = function(text)
        if text == "" then Config.MinIntervalMs = nil; Rayfield:Notify({ Title = "Min Interval cleared", Duration = 2 }); return end
        local num = tonumber(text)
        if not num then Rayfield:Notify({ Title = "Error", Content = "Enter a number", Duration = 2 }); return end
        num = math.floor(math.max(1, num))
        Config.MinIntervalMs = num
        Rayfield:Notify({ Title = "Min Interval: " .. num .. "ms", Duration = 2 })
    end,
})

SettingsTab:CreateInput({
    Name = "Max Interval (ms)",
    CurrentValue = "",
    PlaceholderText = "Leave blank to use Fire Interval",
    RemoveTextAfterFocusLost = false,
    Flag = "MaxIntervalInput",
    Callback = function(text)
        if text == "" then Config.MaxIntervalMs = nil; Rayfield:Notify({ Title = "Max Interval cleared", Duration = 2 }); return end
        local num = tonumber(text)
        if not num then Rayfield:Notify({ Title = "Error", Content = "Enter a number", Duration = 2 }); return end
        num = math.floor(math.max(1, num))
        Config.MaxIntervalMs = num
        Rayfield:Notify({ Title = "Max Interval: " .. num .. "ms", Duration = 2 })
    end,
})

SettingsTab:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = false,
    Flag = "RGB_AntiAFK",
    Callback = function(val)
        Config.AntiAFK = val
        if val then
            local vu = game:GetService("VirtualUser")
            if not vu then return end
            local conn
            conn = Players.LocalPlayer.Idled:Connect(function()
                if not shared.AEH_Running or not Config.AntiAFK then
                    if conn then conn:Disconnect() end
                    return
                end
                vu:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                task.wait(0.1)
                vu:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            end)
            table.insert(Connections, conn)
            Rayfield:Notify({ Title = "Anti-AFK enabled", Duration = 2 })
        end
    end,
})

SettingsTab:CreateSection("Keybinds")

SettingsTab:CreateKeybind({
    Name = "Toggle Auto-Fire",
    CurrentKeybind = "F",
    HoldToInteract = false,
    Flag = "RH_ToggleKey",
    Callback = function()
        Config.Enabled = not Config.Enabled
        AutoToggle:Set(Config.Enabled)
        if refreshStatus then refreshStatus() end
    end,
})

SettingsTab:CreateKeybind({
    Name = "Scan Remotes",
    CurrentKeybind = "G",
    HoldToInteract = false,
    Flag = "RGB_Key_Scan",
    Callback = function()
        if not Config.GlobalKeybinds and not isUIVisible() then return end
        if doScanRemotes then doScanRemotes(false) end
    end,
})

SettingsTab:CreateKeybind({
    Name = "Start/Stop Spy",
    CurrentKeybind = "H",
    HoldToInteract = false,
    Flag = "RGB_Key_Spy",
    Callback = function()
        if not Config.GlobalKeybinds and not isUIVisible() then return end
        if toggleSpy then toggleSpy() end
    end,
})

SettingsTab:CreateKeybind({
    Name = "Clear All",
    CurrentKeybind = "X",
    HoldToInteract = false,
    Flag = "RGB_Key_ClearAll",
    Callback = function()
        if not Config.GlobalKeybinds and not isUIVisible() then return end
        if clearAll then clearAll() end
    end,
})

SettingsTab:CreateKeybind({
    Name = "Copy Spy Results",
    CurrentKeybind = "C",
    HoldToInteract = false,
    Flag = "RGB_Key_CopySpy",
    Callback = function()
        if not Config.GlobalKeybinds and not isUIVisible() then return end
        if doCopyResults then doCopyResults() end
    end,
})

SettingsTab:CreateToggle({
    Name = "Global Keybinds",
    CurrentValue = true,
    Flag = "RGB_GlobalKeybinds",
    Callback = function(val) Config.GlobalKeybinds = val end,
})

SettingsTab:CreateSection("Browse Settings")

SettingsTab:CreateToggle({
    Name = "Show non-firable remotes in scan",
    CurrentValue = false,
    Flag = "RGB_ShowNonFirable",
    Callback = function(val) Config.ShowNonFirable = val end,
})

SettingsTab:CreateSection("Per-Remote Tuning")

local TuneRemoteField = ""
local TuneActionType = "Set Arguments"

SettingsTab:CreateInput({
    Name = "Target Remote (name or index)",
    CurrentValue = "",
    PlaceholderText = "name or index number",
    RemoveTextAfterFocusLost = false,
    Callback = function(text) TuneRemoteField = text end,
})

SettingsTab:CreateDropdown({
    Name = "Setting to Change",
    Options = {"Set Arguments", "Set Interval (ms)", "Set Burst Limit"},
    CurrentOption = {"Set Arguments"},
    MultipleOptions = false,
    Flag = "TuneActionDropdown",
    Callback = function(Options) TuneActionType = Options[1] or Options end,
})

SettingsTab:CreateInput({
    Name = "Value",
    CurrentValue = "",
    PlaceholderText = "e.g. 33 or false,1",
    RemoveTextAfterFocusLost = true,
    Callback = function(text)
        if TuneRemoteField == "" then
            Rayfield:Notify({ Title = "Error", Content = "Set target remote first.", Duration = 2 })
            return
        end
        local targetRemote, _ = resolveHookedRemote(TuneRemoteField)
        if not targetRemote then
            Rayfield:Notify({ Title = "Not hooked", Content = TuneRemoteField, Duration = 2 })
            return
        end
        local data = Hooked[targetRemote]
        if TuneActionType == "Set Arguments" then
            data.argString = text
            data.args = parseArgs(text)
            HookedDirty = true
            saveHookedRemotes()
            Rayfield:Notify({ Title = "Args set", Content = targetRemote.Name .. " = " .. (text == "" and "(none)" or text), Duration = 2 })
        elseif TuneActionType == "Set Interval (ms)" then
            local ms = tonumber(text)
            if ms then
                data.intervalMs = ms
                HookedDirty = true
                saveHookedRemotes()
                Rayfield:Notify({ Title = "Interval set", Content = targetRemote.Name .. " @ " .. ms .. "ms", Duration = 2 })
            else
                Rayfield:Notify({ Title = "Error", Content = "Must be a number", Duration = 2 })
            end
        elseif TuneActionType == "Set Burst Limit" then
            local limit = tonumber(text)
            if limit then
                data.burstLimit = limit
                data.burstNotified = false
                data.fireCount = 0
                HookedDirty = true
                saveHookedRemotes()
                Rayfield:Notify({ Title = "Burst set", Content = targetRemote.Name .. " limit " .. limit, Duration = 2 })
            else
                Rayfield:Notify({ Title = "Error", Content = "Must be a number", Duration = 2 })
            end
        end
    end,
})

SettingsTab:CreateSection("Profiles")

local ProfileActionType = "Load"

SettingsTab:CreateDropdown({
    Name = "Profile Action",
    Options = {"Load", "Save"},
    CurrentOption = {"Load"},
    MultipleOptions = false,
    Flag = "ProfileActionDropdown",
    Callback = function(Options) ProfileActionType = Options[1] or Options end,
})

SettingsTab:CreateInput({
    Name = "Profile Name",
    CurrentValue = "",
    PlaceholderText = "e.g. xp_farm",
    RemoveTextAfterFocusLost = true,
    Callback = function(name)
        if name == "" then return end
        if ProfileActionType == "Save" then
            local data = {}
            for remote, hookData in pairs(Hooked) do
                if remote and remote.Parent then
                    table.insert(data, {
                        path = fullPath(remote), argString = hookData.argString or "",
                        intervalMs = hookData.intervalMs, burstLimit = hookData.burstLimit,
                    })
                end
            end
            pcall(writefile, SavePrefix .. "profile_" .. name .. ".json", HttpService:JSONEncode(data))
            Rayfield:Notify({ Title = "Profile Saved", Content = name .. " (" .. #data .. " remotes)", Duration = 3 })
        else
            local ok, raw = pcall(readfile, SavePrefix .. "profile_" .. name .. ".json")
            if not ok or not raw then Rayfield:Notify({ Title = "Not found", Content = name, Duration = 2 }); return end
            if clearAll then clearAll() end
            local decoded
            pcall(function() decoded = HttpService:JSONDecode(raw) end)
            if type(decoded) ~= "table" then return end
            local loaded = 0
            for _, entry in ipairs(decoded) do
                local parts = string.split(entry.path, ".")
                local current = game
                for _, p in ipairs(parts) do
                    current = current:FindFirstChild(p)
                    if not current then break end
                end
                if current and isFirable(current) then
                    hookRemote(current, entry.argString or "")
                    if entry.intervalMs then Hooked[current].intervalMs = entry.intervalMs end
                    if entry.burstLimit then Hooked[current].burstLimit = entry.burstLimit end
                    loaded = loaded + 1
                end
            end
            Rayfield:Notify({ Title = "Profile Loaded", Content = name .. " - " .. loaded .. " remote(s)", Duration = 3 })
        end
    end,
})

-- // Hook / Unhook
refreshStatus = function()
    local state = Config.Enabled and "ON" or "OFF"
    local rate  = string.format("%.1f", 1000 / Config.FireIntervalMs)
    StatusLabel:Set({ Title = "Engine", Content = state .. "  |  " .. HookedCount .. " hooked  |  " .. rate .. "/sec" })
end

refreshHookedList = function()
    if HookedCount == 0 then
        HookedParagraph:Set({ Title = "Hooked (0)", Content = "None yet. Use Browse or Spy tab." })
    else
        local lines = {}
        local i = 0
        for remote, data in pairs(Hooked) do
            if remote and remote.Parent then
                i = i + 1
                local cls   = shortClass(remote)
                local args  = data.argString ~= "" and ("  -> " .. data.argString) or ""
                local fires = data.fireCount > 0 and ("  x" .. formatNumber(data.fireCount)) or ""
                local stat  = data.paused and " [PAUSED]" or ""
                local intv  = data.intervalMs and (" @" .. data.intervalMs .. "ms") or ""
                local burst = data.burstLimit and (" [" .. data.fireCount .. "/" .. data.burstLimit .. "]") or ""
                table.insert(lines, i .. ". " .. remote.Name .. "  (" .. cls .. ")" .. args .. intv .. burst .. fires .. stat)
            end
        end
        HookedParagraph:Set({ Title = "Hooked (" .. HookedCount .. ")", Content = table.concat(lines, "\n") })
    end
    refreshStatus()
    HookedDirty = false
end

hookRemote = function(remote, argString)
    if Hooked[remote] then return end
    local conn = remote.AncestryChanged:Connect(function(_, parent)
        if not parent then unhookRemote(remote) end
    end)
    table.insert(Connections, conn)
    Hooked[remote] = {
        conn = conn, args = parseArgs(argString or ""), argString = argString or "",
        fireCount = 0, intervalMs = nil, burstLimit = nil, burstNotified = false,
        lastFired = 0, nextFireTime = 0, errorCount = 0, paused = false,
    }
    HookedCount = HookedCount + 1
    HookedDirty = true
    refreshHookedList()
    saveHookedRemotes()
end

unhookRemote = function(remote)
    local data = Hooked[remote]
    if not data then return end
    if data.conn then
        data.conn:Disconnect()
        for i, c in ipairs(Connections) do
            if c == data.conn then table.remove(Connections, i); break end
        end
    end
    local name  = remote.Name
    local fires = data.fireCount
    Hooked[remote] = nil
    HookedCount = HookedCount - 1
    HookedDirty = true
    refreshHookedList()
    Rayfield:Notify({ Title = "Unhooked: " .. name, Content = "Fired " .. formatNumber(fires) .. " times", Duration = 2 })
    saveHookedRemotes()
end

clearAll = function()
    local n = HookedCount
    for _, data in pairs(Hooked) do
        if data.conn then data.conn:Disconnect() end
    end
    Hooked = {}
    Connections = {}
    HookedCount = 0
    TotalFireCount = 0
    HookedDirty = true
    refreshHookedList()
    Rayfield:Notify({ Title = "Cleared " .. n .. " remote(s)", Duration = 2 })
    saveHookedRemotes()
end

-- // Live Stats
task.spawn(function()
    local lastCount = 0
    local lastTime  = tick()

    while shared.AEH_Running do
        task.wait(1)
        local now   = tick()
        local delta = math.max(0, TotalFireCount - lastCount)
        local rate  = (now - lastTime) > 0 and (delta / (now - lastTime)) or 0
        local elapsed = now - SessionStart
        local timeStr = string.format("%dm %02ds", math.floor(elapsed / 60), math.floor(elapsed % 60))

        local newStats = "Total: " .. formatNumber(TotalFireCount) ..
                         "  |  " .. string.format("%.1f", rate) .. "/sec" ..
                         "  |  " .. timeStr

        if newStats ~= LastStatsText then
            StatsLabel:Set({ Title = "Stats", Content = newStats })
            LastStatsText = newStats
        end

        if HookedDirty then refreshHookedList() end

        lastCount = TotalFireCount
        lastTime  = now
    end
end)

-- // Auto-Fire Engine
task.spawn(function()
    while shared.AEH_Running do
        if Config.Enabled and HookedCount > 0 then
            local now = tick()
            for remote, data in pairs(Hooked) do
                if data.paused then continue end
                if now < data.nextFireTime then continue end
                if data.burstLimit and data.fireCount >= data.burstLimit then
                    if not data.burstNotified then
                        data.burstNotified = true
                        task.defer(function()
                            Rayfield:Notify({ Title = "Burst done", Content = remote.Name .. " - " .. data.burstLimit .. " fires", Duration = 3 })
                            unhookRemote(remote)
                        end)
                    end
                    continue
                end
                if not remote or not remote.Parent then task.defer(unhookRemote, remote); continue end

                local ok, err = pcall(function()
                    if data.args and data.args.n and data.args.n > 0 then
                        remote:FireServer(unpack(data.args, 1, data.args.n))
                    else
                        remote:FireServer()
                    end
                end)

                if ok then
                    data.lastFired = now
                    local perRemoteInt = data.intervalMs
                    local minMs = Config.MinIntervalMs or (perRemoteInt or Config.FireIntervalMs)
                    local maxMs = Config.MaxIntervalMs or (perRemoteInt or Config.FireIntervalMs)
                    if perRemoteInt then
                        minMs = perRemoteInt
                        maxMs = perRemoteInt
                    end
                    if minMs > maxMs then minMs, maxMs = maxMs, minMs end
                    local intervalSec
                    if minMs == maxMs then
                        intervalSec = minMs / 1000
                    else
                        intervalSec = (minMs + math.random() * (maxMs - minMs)) / 1000
                    end
                    data.nextFireTime = now + math.max(0.001, intervalSec)
                    data.fireCount = data.fireCount + 1
                    TotalFireCount = TotalFireCount + 1
                    data.errorCount = 0
                    if data.fireCount % 100 == 0 then HookedDirty = true end
                else
                    data.errorCount = (data.errorCount or 0) + 1
                    if data.errorCount >= 10 then
                        data.paused = true
                        HookedDirty = true
                        Rayfield:Notify({ Title = "Auto-paused", Content = remote.Name .. " - " .. data.errorCount .. " errors", Duration = 5 })
                    end
                    warn("[RGB] " .. remote.Name .. " (" .. data.errorCount .. "): " .. tostring(err))
                end
            end
        end
        task.wait(0.001)
    end
end)

-- // Cleanup
shared.AEH_Cleanup = function()
    shared.AEH_Running = false
    IsLogging = false
    shared.AEH_SpyHookActive = nil
    for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
    for _, data in pairs(Hooked) do if data.conn then pcall(function() data.conn:Disconnect() end) end end
    if #RemoteLog > 0 and setclipboard then
        local lines = {}
        for i, entry in ipairs(RemoteLog) do
            local args = #entry.argStrs > 0 and table.concat(entry.argStrs, ", ") or "(no args)"
            lines[i] = i .. ". " .. entry.name .. " - Args: " .. args
        end
        pcall(setclipboard, table.concat(lines, "\n"))
    end
    pcall(function() Rayfield:Destroy() end)
    shared.AEH_Cleanup = nil
    shared.AEH_Running = nil
end

-- // Init
refreshStatus()
refreshHookedList()
loadExcludeList()
refreshExcludeList()
loadHookedRemotes()

Rayfield:Notify({ Title = "Remote Go Brr v0.1.0", Content = "Loaded successfully.", Duration = 3 })