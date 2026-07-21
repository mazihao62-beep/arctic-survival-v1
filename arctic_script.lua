--[[
    北极生存7天 - 自动收集物资 v1.2
    WindUI 模板 + 可勾选资源类型 + 自动挖雪
    全中文界面
    Github: https://github.com/mazihao62-beep/arctic-survival-v1
--]]

print("[北极] 加载中...")

local P = game:GetService("Players")
local WS = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local C = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")

local LP = P.LocalPlayer
if not LP then return end

for _, g in ipairs(C:GetChildren()) do
    if g:IsA("ScreenGui") then
        local n = g.Name
        if n == "A" or n:find("Arctic") or n == "WindUI" then
            pcall(function() g:Destroy() end)
        end
    end
end

local WI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
if not WI then print("[北极] WindUI 失败"); return end
print("[北极] WindUI OK")

local Net
pcall(function() Net = require(RS.Shared.Net) end)

local Remotes = RS:FindFirstChild("Remotes")
local RequestDrag = Remotes and Remotes:FindFirstChild("RequestDrag")
local ReleaseDrag = Remotes and Remotes:FindFirstChild("ReleaseDrag")

local ByteNetReliable = RS:FindFirstChild("ByteNetReliable")

local snowBytes = {39, 108, 84, 138, 63}
local function makeSnowBuffer()
    local b = buffer.create(#snowBytes)
    for i = 1, #snowBytes do
        buffer.writeu8(b, i - 1, snowBytes[i])
    end
    return b
end

local S = {
    AutoCollect = false, CollectWood = true, CollectStone = true,
    CollectFood = false, CollectDrag = true, AutoSnow = false,
    SnowRange = 8, SnowAngle = 60, Range = 50,
    Particles = true, Acrylic = true, Transparent = false,
    ParticleColor = Color3.fromRGB(80, 170, 255)
}
local KB = { Toggle = "RightShift" }
local WN, CT = nil, {}
local PR, PS, PC = false, {}, nil

local function gT(kw)
    local c = LP.Character
    if c then
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") then
                local ln = t.Name:lower()
                for _, k in ipairs(kw) do
                    if ln:find(k, 1, true) then return t end
                end
            end
        end
    end
    local bp = LP:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then
                local ln = t.Name:lower()
                for _, k in ipairs(kw) do
                    if ln:find(k, 1, true) then return t end
                end
            end
        end
    end
    return nil
end

local function eq(t)
    if not t then return false end
    local c = LP.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h then return false end
    if t.Parent ~= c then h:EquipTool(t) wait(0.15) end
    return true
end

local function gSnow()
    local snows = {}
    local c = LP.Character
    if not c then return snows end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return snows end
    local pos = hrp.Position
    local look = hrp.CFrame.LookVector
    local cutoff = math.cos(math.rad(S.SnowAngle))
    local things = WS:FindFirstChild("Things")
    local snowFolder = things and things:FindFirstChild("Snow")
    if snowFolder then
        for _, m in ipairs(snowFolder:GetChildren()) do
            if m:IsA("Model") then
                local bp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
                if bp then
                    local d = (bp.Position - pos).Magnitude
                    if d <= S.SnowRange then
                        local dir = (bp.Position - pos).Unit
                        local dot = look:Dot(dir)
                        if dot >= cutoff then
                            table.insert(snows, {P=bp, D=d, Dot=dot})
                        end
                    end
                end
            end
        end
    end
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:lower():find("snow", 1, true) then
            local d = (obj.Position - pos).Magnitude
            if d <= S.SnowRange then
                local dir = (obj.Position - pos).Unit
                local dot = look:Dot(dir)
                if dot >= cutoff then
                    table.insert(snows, {P=obj, D=d, Dot=dot})
                end
            end
        end
    end
    table.sort(snows, function(a, b) return a.D < b.D end)
    return snows
end

local function cSnow()
    if not S.AutoSnow or not ByteNetReliable then return end
    local snows = gSnow()
    if #snows == 0 then return end
    local snow = snows[1]
    local c = LP.Character
    if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local dir = (snow.P.Position - hrp.Position).Unit
    hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + dir)
    wait(0.1)
    local ok, err = pcall(function()
        ByteNetReliable:FireServer(makeSnowBuffer(), nil)
    end)
    if ok then
        print("[挖雪] " .. snow.P.Name .. " @" .. string.format("%.1f", snow.D) .. "m")
        wait(0.5)
    end
end

local function gDrag()
    local items = {}
    for _, obj in ipairs(CS:GetTagged("Draggable")) do
        if obj:IsA("BasePart") or obj:IsA("Model") then
            local c = LP.Character
            local hrp = c and c:FindFirstChild("HumanoidRootPart")
            local pos = hrp and hrp.Position
            local target = obj:IsA("BasePart") and obj or (obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)))
            if target and pos then
                local d = (target.Position - pos).Magnitude
                if d <= S.Range + 10 then
                    table.insert(items, {M=obj, P=target, D=d})
                end
            end
        end
    end
    table.sort(items, function(a, b) return a.D < b.D end)
    return items
end

local function gTrees()
    local trees = {}
    local c = LP.Character
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    local pos = hrp and hrp.Position
    if not pos then return trees end
    local things = WS:FindFirstChild("Things")
    local f = things and things:FindFirstChild("Trees")
    if f then
        for _, m in ipairs(f:GetChildren()) do
            if m:IsA("Model") then
                local bp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
                if bp and (bp.Position - pos).Magnitude <= S.Range + 10 then
                    table.insert(trees, {M=m, P=bp, D=(bp.Position - pos).Magnitude})
                end
            end
        end
    end
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("Model") and (obj.Name:lower():find("tree") or obj.Name:lower():find("stump") or obj.Name:lower():find("log")) then
            local bp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
            if bp and (bp.Position - pos).Magnitude <= S.Range + 10 then
                table.insert(trees, {M=obj, P=bp, D=(bp.Position - pos).Magnitude})
            end
        end
    end
    table.sort(trees, function(a, b) return a.D < b.D end)
    return trees
end

local function gStones()
    local stones = {}
    local c = LP.Character
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    local pos = hrp and hrp.Position
    if not pos then return stones end
    local things = WS:FindFirstChild("Things")
    local f = things and things:FindFirstChild("Rocks")
    if f then
        for _, m in ipairs(f:GetChildren()) do
            if m:IsA("Model") then
                local bp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
                if bp and (bp.Position - pos).Magnitude <= S.Range + 10 then
                    table.insert(stones, {M=m, P=bp, D=(bp.Position - pos).Magnitude})
                end
            end
        end
    end
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("Model") and (obj.Name:lower():find("rock") or obj.Name:lower():find("stone") or obj.Name:lower():find("ore")) then
            local bp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
            if bp and (bp.Position - pos).Magnitude <= S.Range + 10 then
                table.insert(stones, {M=obj, P=bp, D=(bp.Position - pos).Magnitude})
            end
        end
    end
    table.sort(stones, function(a, b) return a.D < b.D end)
    return stones
end

local function gFood()
    local foods = {}
    local c = LP.Character
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    local pos = hrp and hrp.Position
    if not pos then return foods end
    for _, obj in ipairs(CS:GetTagged("Edible")) do
        local target = obj:IsA("BasePart") and obj or (obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)))
        if target and (target.Position - pos).Magnitude <= S.Range + 10 then
            table.insert(foods, {M=obj, P=target, D=(target.Position - pos).Magnitude})
        end
    end
    table.sort(foods, function(a, b) return a.D < b.D end)
    return foods
end

local function cDrag()
    if not S.CollectDrag or not RequestDrag or not ReleaseDrag then return end
    local items = gDrag(); if #items == 0 then return end
    local item = items[1]
    local c = LP.Character; if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    hrp.CFrame = item.P.CFrame * CFrame.new(0, 0, 3); wait(0.3)
    pcall(function() RequestDrag:FireServer(item.M) end); wait(0.2)
    pcall(function() ReleaseDrag:FireServer() end)
end

local function cWood()
    if not S.CollectWood then return end
    local trees = gTrees(); if #trees == 0 then return end
    local tool = gT({"axe", "hatchet"}); if not tool then return end
    eq(tool)
    local tree = trees[1]
    local c = LP.Character; if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    hrp.CFrame = tree.P.CFrame * CFrame.new(0, 0, 5); wait(0.3)
    if Net and Net.axeCut then Net.axeCut.send({part=tree.P, pos=tree.P.Position, normal=Vector3.new(0,0,1)}) end
end

local function cStone()
    if not S.CollectStone then return end
    local stones = gStones(); if #stones == 0 then return end
    local tool = gT({"shovel", "pickaxe"}); if not tool then return end
    eq(tool)
    local stone = stones[1]
    local c = LP.Character; if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    hrp.CFrame = stone.P.CFrame * CFrame.new(0, 0, 4); wait(0.3)
    if Net and Net.dig then Net.dig.send({tool=tool.Name, pos=stone.P.Position, dir=Vector3.new(0,-1,0)}) end
end

local function cFood()
    if not S.CollectFood then return end
    local foods = gFood(); if #foods == 0 then return end
    local food = foods[1]
    local c = LP.Character; if not c then return end
    local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    hrp.CFrame = food.P.CFrame * CFrame.new(0, 0, 2); wait(0.2)
    if RequestDrag then pcall(function() RequestDrag:FireServer(food.M) end) end
end

local function sP()
    if PR then return end
    if PC then pcall(function() local p=PC.Parent; if p then p:Destroy() end end) PC=nil end
    PS={}; wait(0.3)
    local sg=Instance.new("ScreenGui"); sg.Name="AP"; sg.ResetOnSpawn=false; sg.DisplayOrder=999999; sg.IgnoreGuiInset=true; sg.Parent=C
    PC=Instance.new("Frame"); PC.Size=UDim2.new(1,0,1,0); PC.BackgroundTransparency=1; PC.BorderSizePixel=0; PC.Parent=sg
    for i=1,50 do
        local d=Instance.new("Frame"); local sz=math.random(5,10)
        d.Size=UDim2.new(0,sz,0,sz); d.Position=UDim2.new(0.2+math.random()*0.6,0,0.2+math.random()*0.6,0)
        d.BackgroundColor3=S.ParticleColor; d.BackgroundTransparency=0.3+math.random()*0.5; d.BorderSizePixel=0; d.Parent=PC
        Instance.new("UICorner",d).CornerRadius=UDim.new(0,10)
        local a=math.random()*6.28; local sp=0.0008+math.random()*0.002
        table.insert(PS,{F=d,Sx=d.Position.X.Scale,Sy=d.Position.Y.Scale,Vx=math.cos(a)*sp,Vy=math.sin(a)*sp,Ph=math.random()*6.28,Sz=sz})
    end
    PR=true
    spawn(function() local t=0; while PR and PC do t=t+0.03
        pcall(function() local c=S.ParticleColor; for _,p in ipairs(PS) do if p.F and p.F.Parent then
            local sx=math.max(0.05,math.min(0.95,p.Sx+p.Vx)); local sy=math.max(0.05,math.min(0.95,p.Sy+p.Vy))
            if sx>=0.95 or sx<=0.05 then p.Vx=-p.Vx end; if sy>=0.95 or sy<=0.05 then p.Vy=-p.Vy end
            p.Sx=sx; p.Sy=sy; p.F.Position=UDim2.new(sx,0,sy,0); p.F.BackgroundColor3=c
            p.F.BackgroundTransparency=0.3+math.sin(t*0.8+p.Ph)*0.4
            p.F.Size=UDim2.new(0,math.max(2,p.Sz+math.sin(t+p.Ph)*1.5),0,math.max(2,p.Sz+math.sin(t+p.Ph)*1.5))
    end end end) wait(0.03) end end)
end
local function xP() PR=false; if PC then pcall(function() local p=PC.Parent; if p then p:Destroy() end end) PC=nil end; PS={} end

local tc
tc = function(n)
    local t = {Dark=Color3.fromRGB(80,170,255),Light=Color3.fromRGB(60,130,210),Rose=Color3.fromRGB(255,130,170),Plant=Color3.fromRGB(70,210,130),Ocean=Color3.fromRGB(60,190,240),Sunset=Color3.fromRGB(255,160,70),Midnight=Color3.fromRGB(130,100,240),Forest=Color3.fromRGB(60,180,90),Lavender=Color3.fromRGB(190,140,255),Coral=Color3.fromRGB(255,140,90),Mint=Color3.fromRGB(80,230,190),Sky=Color3.fromRGB(100,190,255),Blood=Color3.fromRGB(230,90,80),Lemon=Color3.fromRGB(230,210,70),Cyber=Color3.fromRGB(0,235,210)}
    return t[n] or Color3.fromRGB(80,170,255)
end

local function mW()
    WN = WI:CreateWindow({Title="北极生存", Author="b站英吉利超入_", Icon="solar:snowflake-bold", Size=UDim2.fromOffset(750,560), ToggleKey=Enum.KeyCode.RightShift, Folder="arctic-script", Acrylic=true, Resizable=false, ScrollBarEnabled=true, HideSearchBar=true, OnClose=function() xP();S.AutoCollect=false;S.AutoSnow=false;for _,ct in pairs(CT) do if ct and type(ct.Set)=="function" then pcall(function() ct:Set(false) end) end end end, OnOpen=function() if S.Particles then sP() end end})
    spawn(function() wait(0.8) pcall(function() if WN and WN.Parent then WN.Parent.ClipsDescendants=true end end) end)

    local t1=WN:Tab({Title="主控面板", Icon="solar:slider-vertical-bold"})
    CT.AutoCollect=t1:Toggle({Flag="AutoCollect", Title="自动收集", Value=false, Callback=function(v) S.AutoCollect=v end})
    t1:Divider()
    CT.AutoSnow=t1:Toggle({Flag="AutoSnow", Title="自动挖雪(面前)", Value=false, Callback=function(v) S.AutoSnow=v end})
    t1:Space()
    CT.CollectWood=t1:Toggle({Flag="CollectWood", Title="木头(斧头)", Value=true, Callback=function(v) S.CollectWood=v end})
    CT.CollectStone=t1:Toggle({Flag="CollectStone", Title="石头(铲子)", Value=true, Callback=function(v) S.CollectStone=v end})
    CT.CollectFood=t1:Toggle({Flag="CollectFood", Title="食物(浆果)", Value=false, Callback=function(v) S.CollectFood=v end})
    CT.CollectDrag=t1:Toggle({Flag="CollectDrag", Title="可拖动物品", Value=true, Callback=function(v) S.CollectDrag=v end})
    t1:Divider()
    CT.Range=t1:Slider({Flag="Range", Title="收集范围", Step=5, Value={Min=10,Max=150,Default=50}, Width=200, IsTextbox=true, Callback=function(v) S.Range=v end})

    local t2=WN:Tab({Title="快捷键", Icon="solar:settings-bold"})
    t2:Keybind({Flag="ToggleKey", Title="窗口开关", Value="RightShift", Callback=function(v) KB.Toggle=v end})

    local t3=WN:Tab({Title="UI设置", Icon="solar:monitor-bold"})
    CT.Particles=t3:Toggle({Flag="Particles", Title="粒子背景", Value=true, Callback=function(v) S.Particles=v; if v then sP() else xP() end end})
    t3:Toggle({Flag="Acrylic", Title="毛玻璃", Value=true, Callback=function(v) S.Acrylic=v; pcall(function() WI:ToggleAcrylic(v) end) end})
    t3:Toggle({Flag="Transparent", Title="透明", Value=false, Callback=function(v) S.Transparent=v; pcall(function() WN:ToggleTransparency(v) end) end})
    local tns={"Dark","Light","Rose","Plant","Ocean","Sunset","Midnight","Forest","Lavender","Coral","Mint","Sky","Blood","Lemon","Cyber"}
    t3:Dropdown({Flag="Theme", Title="主题", Values=tns, Value="Dark", Callback=function(v) pcall(function() WI:SetTheme(v) end); S.ParticleColor=tc(v) end})

    local t4=WN:Tab({Title="信息统计", Icon="solar:chart-bold"})
    local sWood=t4:Paragraph({Title="树木: 0"}); local sStone=t4:Paragraph({Title="石头: 0"})
    local sFood=t4:Paragraph({Title="食物: 0"}); local sDrag=t4:Paragraph({Title="拖动物品: 0"})

    local t5=WN:Tab({Title="配置管理", Icon="solar:diskette-bold"})
    pcall(function()
        local CM=WN.ConfigManager; if not CM then return end
        local cni=t5:Input({Flag="CN", Title="配置名称", Value="default", Icon="solar:file-text-bold", Callback=function(v) end})
        t5:Space(); local AC={}; pcall(function() AC=CM:AllConfigs() end)
        local DV=nil; for _,v in ipairs(AC) do if v=="default" then DV="default"; break end end
        local ACD=t5:Dropdown({Title="已有配置", Values=AC, Value=DV, Callback=function(v) if v then pcall(function() cni:Set(v) end) end end})
        t5:Space()
        t5:Button({Title="保存", Icon="solar:check-circle-bold", Justify="Center", Color=Color3.fromHex("#305dff"), Callback=function() if not CM then return end; local c=CM:Config("default"); if c and c:Save() then WI:Notify({Title="已保存", Content="OK", Duration=3, Icon="solar:check-circle-bold"}); pcall(function() ACD:Refresh(CM:AllConfigs()) end) end end})
        t5:Space()
        t5:Button({Title="加载", Icon="solar:refresh-circle-bold", Justify="Center", Color=Color3.fromHex("#10C550"), Callback=function() if not CM then return end; local c=CM:CreateConfig("default",false); if c and c:Load() then WI:Notify({Title="已加载", Content="OK", Duration=3, Icon="solar:refresh-circle-bold"}) end end})
        t5:Space()
        t5:Button({Title="删除", Icon="solar:trash-bin-trash-bold", Justify="Center", Color=Color3.fromHex("#ff3040"), Callback=function() if not CM then return end; local c=CM:Config("default"); if c and c:Delete() then WI:Notify({Title="已删除", Content="OK", Duration=3, Icon="solar:trash-bin-trash-bold"}); pcall(function() ACD:Refresh(CM:AllConfigs()) end) end end})
        spawn(function() wait(1) pcall(function() CM:CreateConfig("default",true) end) end)
    end)

    local t6=WN:Tab({Title="关于", Icon="solar:info-square-bold"})
    t6:Paragraph({Title="北极生存 v1.2"}); t6:Divider()
    t6:Paragraph({Title="作者", Desc="b站英吉利超入_"})
    t6:Paragraph({Title="说明", Desc="自动收集物资 + 自动挖雪"})
    return sWood, sStone, sFood, sDrag
end

pcall(function() WI:SetTheme("Dark") end); S.ParticleColor=tc("Dark")
local PP=false
WI:Popup({Title="北极生存 v1.2", Content="自动收集物资 + 自动挖雪。木头/石头/食物/可拖动物品。", Buttons={{Title="加载", Callback=function() PP=true end, Variant="Primary"}, {Title="取消", Callback=function() return end}}})
while not PP do wait(0.1) end

spawn(function()
    local sWood, sStone, sFood, sDrag = mW()
    print("[北极] OK")
    local start=os.clock()
    while true do
        if S.AutoSnow then pcall(function() cSnow() end) wait(0.2) end
        if S.AutoCollect then
            pcall(function() cWood() end) wait(0.5)
            pcall(function() cStone() end) wait(0.5)
            pcall(function() cFood() end) wait(0.5)
            pcall(function() cDrag() end) wait(0.5)
        end
        wait(0.3)
        local now=os.clock()
        if now-start>3 then start=now
            if sWood then pcall(function() sWood:SetTitle("树木: "..#gTrees()) end) end
            if sStone then pcall(function() sStone:SetTitle("石头: "..#gStones()) end) end
            if sFood then pcall(function() sFood:SetTitle("食物: "..#gFood()) end) end
            if sDrag then pcall(function() sDrag:SetTitle("拖动物品: "..#gDrag()) end) end
        end
    end
end)