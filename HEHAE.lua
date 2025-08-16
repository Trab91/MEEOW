--[[ 
    @author MEOW 
    @description Grow a Garden auto-farm script 
    https://www.roblox.com/games/126884695634066 
]] 

--// Services 
local ReplicatedStorage = game:GetService("ReplicatedStorage") 
local InsertService = game:GetService("InsertService") 
local MarketplaceService = game:GetService("MarketplaceService") 
local Players = game:GetService("Players") 
local RunService = game:GetService("RunService") 

local LocalPlayer = Players.LocalPlayer 
local Leaderstats = LocalPlayer.leaderstats 
local Backpack = LocalPlayer.Backpack 
local PlayerGui = LocalPlayer.PlayerGui 

local ShecklesCount = Leaderstats.Sheckles 
local GameInfo = MarketplaceService:GetProductInfo(game.PlaceId) 

--// ReGui 
local ReGui = loadstring(game:HttpGet('https://raw.githubusercontent.com/depthso/Dear-ReGui/refs/heads/main/ReGui.lua'))() 
local PrefabsId = "rbxassetid://" .. ReGui.PrefabsId 

--// Folders 
local GameEvents = ReplicatedStorage.GameEvents 
local Farms = workspace.Farm 

local Accent = { 
    DarkBlue = Color3.fromRGB(0, 0, 139), 
    Blue = Color3.fromRGB(0, 191, 255), 
    LightBlue = Color3.fromRGB(173, 216, 230), 
} 

--// ReGui configuration (Ui library) 
ReGui:Init({ 
    Prefabs = InsertService:LoadLocalAsset(PrefabsId) 
}) 
ReGui:DefineTheme("GardenTheme", { 
    WindowBg = Accent.LightBlue, 
    TitleBarBg = Accent.DarkBlue, 
    TitleBarBgActive = Accent.Blue, 
    ResizeGrab = Accent.Blue, 
    FrameBg = Accent.LightBlue, 
    FrameBgActive = Accent.Blue, 
    CollapsingHeaderBg = Accent.Blue, 
    ButtonsBg = Accent.Blue, 
    CheckMark = Accent.Blue, 
    SliderGrab = Accent.Blue, 
}) 

--// Dicts 
local SeedStock = {} 
local OwnedSeeds = {} 
local HarvestIgnores = { 
    Normal = false, 
    Gold = false, 
    Rainbow = false 
} 

--// Globals 
local SelectedSeed, AutoPlantRandom, AutoPlant, AutoHarvest, AutoBuy, SellThreshold, NoClip, AutoWalkAllowRandom 

local function CreateWindow() 
    local Window = ReGui:Window({ 
        Title = `{GameInfo.Name} | MEOW`, 
        Theme = "GardenTheme", 
        Size = UDim2.fromOffset(300, 200) 
    }) 
    return Window 
end 

--// Interface functions 
local function Plant(Position: Vector3, Seed: string) 
    GameEvents.Plant_RE:FireServer(Position, Seed) 
    wait(.3) 
end 

local function GetFarms() 
    return Farms:GetChildren() 
end 

local function GetFarmOwner(Farm: Folder): string 
    local Important = Farm.Important 
    local Data = Important.Data 
    local Owner = Data.Owner 

    return Owner.Value 
end 

local function GetFarm(PlayerName: string): Folder? 
    local Farms = GetFarms() 
    for _, Farm in next, Farms do 
        local Owner = GetFarmOwner(Farm) 
        if Owner == PlayerName then 
            return Farm 
        end 
    end 
    return 
end 

local IsSelling = false 
local function SellInventory() 
    local Character = LocalPlayer.Character 
    local Previous = Character:GetPivot() 
    local PreviousSheckles = ShecklesCount.Value 

    --// Prevent conflict 
    if IsSelling then return end 
    IsSelling = true 

    Character:PivotTo(CFrame.new(62, 4, -26)) 
    while wait() do 
        if ShecklesCount.Value ~= PreviousSheckles then break end 
        GameEvents.Sell_Inventory:FireServer() 
    end 
    Character:PivotTo(Previous) 

    wait(0.2) 
    IsSelling = false 
end 

local function BuySeed(Seed: string) 
    GameEvents.BuySeedStock:FireServer(Seed) 
end 

local function BuyAllSelectedSeeds() 
    local Seed = SelectedSeedStock.Selected 
    local Stock = SeedStock[Seed] 

    if not Stock or Stock <= 0 then return end 

    for i = 1, Stock do 
        BuySeed(Seed) 
    end 
end 

local function GetSeedInfo(Seed: Tool): number? 
    local PlantName = Seed:FindFirstChild("Plant_Name") 
    local Count = Seed:FindFirstChild("Numbers") 
    if not PlantName then return end 

    return PlantName.Value, Count.Value 
end 

local function CollectSeedsFromParent(Parent, Seeds: table) 
    for _, Tool in next, Parent:GetChildren() do 
        local Name, Count = GetSeedInfo(Tool) 
        if not Name then continue end 

        Seeds[Name] = { 
            Count = Count, 
            Tool = Tool 
        } 
    end 
end 

local function CollectCropsFromParent(Parent, Crops: table) 
    for _, Tool in next, Parent:GetChildren() do 
        local Name = Tool:FindFirstChild("Item_String") 
        if not Name then continue end 

        table.insert(Crops, Tool) 
    end 
end 

local function GetOwnedSeeds(): table 
    local Character = LocalPlayer.Character 
    
    CollectSeedsFromParent(Backpack, OwnedSeeds) 
    CollectSeedsFromParent(Character, OwnedSeeds) 

    return OwnedSeeds 
end 

local function GetInvCrops(): table 
    local Character = LocalPlayer.Character 
    
    local Crops = {} 
    CollectCropsFromParent(Backpack, Crops) 
    CollectCropsFromParent(Character, Crops) 

    return Crops 
end 

local function GetArea(Base: BasePart) 
    local Center = Base:GetPivot() 
    local Size = Base.Size 

    --// Bottom left 
    local X1 = math.ceil(Center.X - (Size.X/2)) 
    local Z1 = math.ceil(Center.Z - (Size.Z/2)) 

    --// Top right 
    local X2 = math.floor(Center.X + (Size.X/2)) 
    local Z2 = math.floor(Center.Z + (Size.Z/2)) 

    return X1, Z1, X2, Z2 
end 

local function EquipCheck(Tool) 
    local Character = LocalPlayer.Character 
    local Humanoid = Character.Humanoid 

    if Tool.Parent ~= Backpack then return end 
    Humanoid:EquipTool(Tool) 
end 

--// Auto farm functions 
local MyFarm = GetFarm(LocalPlayer.Name) 
local MyImportant = MyFarm.Important 
local PlantLocations = MyImportant.Plant_Locations 
local PlantsPhysical = MyImportant.Plants_Physical 

local Dirt = PlantLocations:FindFirstChildOfClass("Part") 
local X1, Z1, X2, Z2 = GetArea(Dirt) 

local function GetRandomFarmPoint(): Vector3 
    local FarmLands = PlantLocations:GetChildren() 
    local FarmLand = FarmLands[math.random(1, #FarmLands)] 

    local X1, Z1, X2, Z2 = GetArea(FarmLand) 
    local X = math.random(X1, X2) 
    local Z = math.random(Z1, Z2) 

    return Vector3.new(X, 4, Z) 
end 

local function AutoPlantLoop() 
    local Seed = SelectedSeed.Selected 

    local SeedData = OwnedSeeds[Seed] 
    if not SeedData then return end 

    local Count = SeedData.Count 
    local Tool = SeedData.Tool 

    --// Check for stock 
    if Count <= 0 then return end 

    local Planted = 0 
    local Step = 1 

    --// Check if the client needs to equip the tool 
    EquipCheck(Tool) 

    --// Plant at random points 
    if AutoPlantRandom.Value then 
        for i = 1, Count do 
            local Point = GetRandomFarmPoint() 
            Plant(Point, Seed) 
        end 
    end 

    --// Plant on the farmland area 
    for X = X1, X2, Step do 
        for Z = Z1, Z2, Step do 
            if Planted > Count then break end 
            local Point = Vector3.new(X, 0.13, Z) 

            Planted += 1 
            Plant(Point, Seed) 
        end 
    end 
end 

local function HarvestPlant(Plant: Model) 
    local Prompt = Plant:FindFirstChild("ProximityPrompt", true) 

    --// Check if it can be harvested 
    if not Prompt then return end 
    fireproximityprompt(Prompt
