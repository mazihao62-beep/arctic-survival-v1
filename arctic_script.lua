--[[
    北极生存7天 - 自动收集物资 v2.4
    挖雪光环(Shovel+搜附近雪) | 砍树(Axe+ByteNet) | 拖动回家
--]]

print("[北极] v2.4 加载中...")

local P = game:GetService("Players")
local WS = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local C = game:GetService("CoreGui")

local LP = P.LocalPlayer
if not LP then return end
print("[北极] 玩家: " .. LP.Name)

for _, g in ipairs(C:GetChildren()) do
    if g:IsA("ScreenGui") and (g.Name:find("Arctic") or g.Name == "WindUI") then
        pcall(function() g:Destroy() end)
    end
end

print("[北极] 加载WindUI...")
local WI = nil
local function tryLoad()
    local ok1, s1 = pcall(function() return readfile("windui_source.lua") end)
    if ok1 and s1 and #s1 > 100 then
        local ok, m = pcall(loadstring, s1)
        if ok and m then local ok2, i = pcall(m); if ok2 and i then return i end end
    end
    for i = 1, 3 do
        local ok, s2 = pcall(function() return game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua") end)
        if ok and s2 and #s2 > 100 then
            local ok, m = pcall(loadstring, s2)
            if ok and m then local ok2, i = pcall(m); if ok2 and i then return i end end
        end
        if i < 3 then wait(1) end
    end
    return nil
end
WI = tryLoad()
print("[北极] WindUI=" .. (WI and "OK" or "NIL"))

local Rem = RS:FindFirstChild("Remotes")
local RD = Rem and Rem:FindFirstChild("RequestDrag")
local RL = Rem and Rem:FindFirstChild("ReleaseDrag")
local BNR = RS:FindFirstChild("ByteNetReliable")
local BM = pcall(function() return buffer.create end)
print("[北极] 事件: Drag=" .. (RD and "OK" or "NIL") .. " Release=" .. (RL and "OK" or "NIL") .. " ByteNet=" .. (BNR and "OK" or "NIL") .. " Buffer=" .. (BM and "OK" or "NIL"))

local sb = {39,108,84,138,63}
local tb = {41,3,0,65,120,101,8,0,65,120,101,83,119,105,110,103,20,1,42,197,127,191,99,221,42,61,220,52,242,59,69,171,14,68,253,170,165,66,172,8,26,68}
local function mkSB() local b=buffer.create(#sb); for i=1,#sb do buffer.writeu8(b,i-1,sb[i]) end; return b end
local function mkTB() local b=buffer.create(#tb); for i=1,#tb do buffer.writeu8(b,i-1,tb[i]) end; return b end

local homePos, WN, CT = nil, nil, {}
local S = {Snow=false, Wood=false, Drag=false, Range=60}
local KB = {Toggle="RightShift"}

local function getTool(kw)
    for _, src in ipairs({LP.Character, LP:FindFirstChild("Backpack")}) do
        if src then
            for _, t in ipairs(src:GetChildren()) do
                if t:IsA("Tool") then
                    local ln = t.Name:lower()
                    for _, k in ipairs(kw) do
                        if ln:find(k, 1, true) then return t end
                    end
                end
            end
        end
    end
    return nil
end

local function eq(t)
    if not t then return false end
    local c=LP.Character; if not c then return false end
    local h=c:FindFirstChildOfClass("Humanoid"); if not h then return false end
    if t.Parent~=c then h:EquipTool(t); wait(0.3) end; return true
end

local function hrp() local c=LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end

-- ===== 挖雪光环：搜附近所有Snow相关Part，逐个挖 =====
local function digSnowAura()
    if not S.Snow or not BNR or not BM then return end
    local shovel = getTool({"shovel","spade"})
    if not shovel then print("[光环] 无Shovel"); return end
    eq(shovel)
    local h = hrp(); if not h then return end
    local pos = h.Position
    
    -- 收集所有Snow目标
    local targets = {}
    local seen = {}
    
    -- 1. Things.DigHere / DigPoint (挖掘点)
    local things = WS:FindFirstChild("Things")
    if things then
        for _, name in ipairs({"DigHere", "DigPoint"}) do
            local p = things:FindFirstChild(name)
            if p and not seen[p] then
                local d = (p.Position - pos).Magnitude
                if d <= S.Range then
                    seen[p] = true
                    table.insert(targets, {P=p, D=d, Type="point"})
                end
            end
        end
    end
    
    -- 2. IcePlates → IceSlabs → Ice Parts
    local ip = things and things:FindFirstChild("IcePlates")
    if ip then
        for _, folder in ipairs(ip:GetChildren()) do
            if folder.Name:find("IceSlab") then
                for _, sub in ipairs(folder:GetChildren()) do
                    if sub:IsA("BasePart") and not seen[sub] then
                        local d = (sub.Position - pos).Magnitude
                        if d <= S.Range then
                            seen[sub] = true
                            table.insert(targets, {P=sub, D=d, Type="ice"})
                        end
                    end
                end
            end
        end
    end
    
    -- 3. SnowDebris (雪堆)
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj.Name == "SnowDebris" and obj:IsA("BasePart") and not seen[obj] then
            local d = (obj.Position - pos).Magnitude
            if d <= S.Range then
                seen[obj] = true
                table.insert(targets, {P=obj, D=d, Type="debris"})
            end
        end
    end
    
    -- 4. BlizzardSnowFX → SnowSlab
    local bsf = WS:FindFirstChild("BlizzardSnowFX")
    if bsf then
        for _, sub in ipairs(bsf:GetChildren()) do
            if sub.Name:find("Snow") and sub:IsA("BasePart") and not seen[sub] then
                local d = (sub.Position - pos).Magnitude
                if d <= S.Range then
                    seen[sub] = true
                    table.insert(targets, {P=sub, D=d, Type="slab"})
                end
            end
        end
    end
    
    table.sort(targets, function(a,b) return a.D < b.D end)
    
    if #targets == 0 then
        print("[光环] 附近无雪")
        return
    end
    
    print("[光环] 找到 " .. #targets .. " 个雪目标")
    local dug = 0
    for i, t in ipairs(targets) do
        local h2 = hrp()
        if not h2 then break end
        -- 传送过去
        local tp = t.P.Position
        h2.CFrame = CFrame.new(tp.X, tp.Y + 1, tp.Z)
        wait(0.2)
        local ok, err = pcall(function() BNR:FireServer(mkSB(), nil) end)
        if ok then
            dug = dug + 1
            print("[光环] #" .. i .. " " .. t.P.Name .. " @" .. string.format("%.0f", t.D) .. "m " .. (ok and "OK" or "失败"))
        end
        wait(0.2)
    end
    print("[光环] 完成: 挖了 " .. dug .. "/" .. #targets .. " 个")
end

-- ===== 砍树 =====
local function cutTree()
    if not S.Wood or not BNR or not BM then return end
    local axe = getTool({"axe","hatchet"})
    if not axe then print("[树] 无斧头"); return end
    eq(axe)
    local forest = WS:FindFirstChild("Forest")
    if not forest then print("[树] 无Forest"); return end
    local h = hrp(); if not h then return end
    local near = nil
    for _, c in ipairs(forest:GetChildren()) do
        if c:IsA("Model") then
            local t = c:FindFirstChild("Trunk")
            if t then local d = (t.Position-h.Position).Magnitude; if d<=S.Range+20 then near={M=c,P=t,D=d} end end
        end
    end
    if not near then print("[树] 无树"); return end
    print(string.format("[树] %s @%.1fm", near.M.Name, near.D))
    h.CFrame = near.P.CFrame * CFrame.new(0, 0, 4)
    wait(0.5)
    local ok, err = pcall(function() BNR:FireServer(mkTB(), {near.P}) end)
    if ok then
        print("[树] OK")
        if homePos then wait(0.5); local h2=hrp(); if h2 then h2.CFrame=CFrame.new(homePos) end end
    else
        print("[树] 失败:"..tostring(err))
    end
    wait(1)
end

-- ===== 拖动回家 =====
local function dragHome()
    if not S.Drag or not RD or not RL or not homePos then return end
    local h = hrp(); if not h then return end
    for _, obj in ipairs(CS:GetTagged("Draggable")) do
        local t = obj:IsA("BasePart") and obj or (obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart",true)))
        if t and (t.Position-h.Position).Magnitude <= S.Range then
            print("[拖] "..obj.Name.." @"..string.format("%.0f",(t.Position-h.Position).Magnitude).."m")
            h.CFrame = t.CFrame * CFrame.new(0,0,3); wait(0.4)
            local ok = pcall(function() RD:FireServer(obj) end)
            if ok then
                wait(0.3); h.CFrame = CFrame.new(homePos.X, homePos.Y+2, homePos.Z); wait(0.5)
                pcall(function() RL:FireServer() end)
                print("[拖] 到家")
            end
            break
        end
    end
    wait(0.5)
end

local function setHome()
    local h=hrp()
    if not h then if WI then WI:Notify({Title="错误",Content="找不到角色",Duration=2}) end; return end
    homePos=h.Position
    if WI then WI:Notify({Title="家点已设",Content="可拖动物品自动传回",Duration=3}) end
    print("[家] "..string.format("%.1f,%.1f,%.1f",homePos.X,homePos.Y,homePos.Z))
end

local PP=false
if WI then
    WI:Popup({Title="北极生存 v2.4", Content="挖雪光环(自动搜附近雪) | 砍树 | 拖动回家", Buttons={{Title="加载", Callback=function() PP=true end, Variant="Primary"},{Title="取消", Callback=function() return end}}})
end
while not PP do wait(0.1) end

if WI then
    WN = WI:CreateWindow({Title="北极生存 v2.4", Author="b站英吉利超入_", Icon="solar:snowflake-bold",
        Size=UDim2.fromOffset(750,520), ToggleKey=Enum.KeyCode.RightShift, Folder="arctic-script",
        Acrylic=true, Resizable=false, ScrollBarEnabled=true, HideSearchBar=true,
        OnClose=function() S.Snow=false; S.Wood=false; S.Drag=false end})
    spawn(function() wait(0.8) pcall(function() if WN and WN.Parent then WN.Parent.ClipsDescendants=true end end) end)
    local t1=WN:Tab({Title="主控", Icon="solar:slider-vertical-bold"})
    CT.Snow=t1:Toggle({Flag="SN", Title="挖雪光环(搜附近雪+Shovel)", Value=false, Callback=function(v) S.Snow=v; print("[开关] 挖雪光环="..tostring(v)) end})
    t1:Space()
    CT.Wood=t1:Toggle({Flag="WD", Title="砍树(Axe+ByteNet)", Value=false, Callback=function(v) S.Wood=v; print("[开关] 砍树="..tostring(v)) end})
    t1:Space()
    CT.Drag=t1:Toggle({Flag="DR", Title="拖动回家(RequestDrag)", Value=false, Callback=function(v) S.Drag=v; print("[开关] 拖动="..tostring(v)) end})
    t1:Divider()
    t1:Button({Title="设置家点", Icon="solar:home-bold", Justify="Center", Color=Color3.fromHex("#50C878"), Callback=setHome})
    t1:Space()
    CT.Range=t1:Slider({Flag="RG", Title="收集范围", Step=5, Value={Min=10,Max=150,Default=60}, Width=200, IsTextbox=true, Callback=function(v) S.Range=v end})
    local t2=WN:Tab({Title="快捷键", Icon="solar:settings-bold"})
    t2:Keybind({Flag="TK", Title="窗口开关", Value="RightShift", Callback=function(v) end})
    local t3=WN:Tab({Title="UI", Icon="solar:monitor-bold"})
    if WI.ToggleAcrylic then t3:Toggle({Flag="AC", Title="毛玻璃", Value=true, Callback=function(v) pcall(function() WI:ToggleAcrylic(v) end) end}) end
    local tns={"Dark","Light","Rose","Plant","Ocean","Sunset","Midnight","Forest","Lavender","Coral","Mint","Sky","Blood","Lemon","Cyber"}
    if WI.SetTheme then t3:Dropdown({Flag="TH", Title="主题", Values=tns, Value="Dark", Callback=function(v) pcall(function() WI:SetTheme(v) end) end}) end
    local t4=WN:Tab({Title="信息", Icon="solar:chart-bold"})
    local t5=WN:Tab({Title="关于", Icon="solar:info-square-bold"})
    t5:Paragraph({Title="北极生存 v2.4"}); t5:Divider()
    t5:Paragraph({Title="作者", Desc="b站英吉利超入_"})
    t5:Paragraph({Title="说明", Desc="挖雪光环:自动搜附近雪块逐个挖 | 砍树:Axe+ByteNet+{Trunk} | 拖动:RequestDrag回家"})
end

print("[北极] v2.4 开始运行")

spawn(function()
    while true do
        if S.Snow then pcall(digSnowAura) end; wait(0.8)
        if S.Wood then pcall(cutTree) end; wait(0.3)
        if S.Drag then pcall(dragHome) end; wait(0.3)
        wait(0.5)
    end
end
