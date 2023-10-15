-----------------------------------------------------------------------
-- Sandbox
-- Custom dynamic game type controller
-----------------------------------------------------------------------
api_version = "1.12.0.0"

-- Lua libraries
local inspect = require "inspect"
local yml = require "tinyyaml"
local blam = require "blam"
local isNull = blam.isNull
local luna = require "luna"
local split = luna.string.split
local glue = require "glue"
local shift = glue.shift
local unpack = glue.unpack

---@class events
---@field starts string[]
---@field spawns string[]
---@field dies string[]

---@class subjects
---@field game events
---@field player events
---@field gametype events

---@class sandboxgametype
---@field name string
---@field description string
---@field version number
---@field like string
---@field when subjects

---@type sandboxgametype?
local sandboxGame
---@type tag[]
local usableWeaponTags = {}

-- Easier callback event dispatcher
local event = {
    tick = cb["EVENT_TICK"],
    playerSpawn = cb["EVENT_SPAWN"],
    playerKill = cb["EVENT_KILL"],
    die = cb["EVENT_DIE"],
    command = cb["EVENT_COMMAND"],
    objectSpawn = cb["EVENT_OBJECT_SPAWN"],
    weaponPickUp = cb["EVENT_WEAPON_PICKUP"],
    alive = cb["EVENT_ALIVE"],
    betray = cb["EVENT_BETRAY"],
    gameStart = cb["EVENT_GAME_START"],
    gameEnd = cb["EVENT_GAME_END"]
}

local gametypesPath = "gametypes/%s/%s.yml"

local queueFunctions = {}

------------------------ Sandbox setup ------------------------

--- Script initialization code
function OnScriptLoad()
    math.randomseed(os.time())
    -- We can set up our event callbacks, like OnTick callback
    register_callback(event.command, "OnCommand")
    register_callback(event.die, "OnPlayerDie")
    register_callback(event.playerSpawn, "OnPlayerSpawn")
    register_callback(event.playerKill, "OnPlayerKill")
    -- This event is kinda special, it is being used as queue processor
    register_callback(event.alive, "OnPlayerAlive")
    register_callback(event.betray, "OnPlayerBetray")
    register_callback(event.betray, "OnPlayerBetray")
    register_callback(event.gameStart, "OnGameStart")
    register_callback(event.gameEnd, "OnGameEnd")
    local sandboxCfg = luna.file.read("sandboxcfg.yml")
    if not sandboxCfg then
        cprint("Error at loading sandboxcfg.yml from sandbox.lua")
    else
        local cfg = yml.parse(sandboxCfg) or {}
        if cfg.game_type then
            loadGameType(cfg.game_type)
        end
    end
end

local ignoreWeaponWords = {"skull", "ball", "flag", "gravity", "powerup", "power up", "power-up"}

function OnGameStart()
    -- Find  weapon tags
    local weaponTags = blam.findTagsList("", blam.tagClasses.weapon)
    for _, tag in pairs(weaponTags) do
        local weaponTag = blam.weaponTag(tag.id)
        -- Check if weapon has a model and does not contain words, skull, flag, gravity, etc.
        if not isNull(weaponTag.model) then
            local skipWeapon = false
            for _, word in pairs(ignoreWeaponWords) do
                if tag.path:includes(word) then
                    skipWeapon = true
                    break
                end
            end
            if not skipWeapon then
                table.insert(usableWeaponTags, tag)
            end
        end
    end
end

function OnGameEnd()
    -- Clear weapon tags
    usableWeaponTags = {}
    -- execute_command("disable_all_objects 0 0")
end

--- Script cleanup
function OnScriptUnload()
end

--- Error logging catcher
function OnError(Message)
end

--- Global console print to every player in the game
function grprint(message)
    for playerIndex = 1, 16 do
        if player_present(playerIndex) then
            rprint(playerIndex, message)
        end
    end
end

------------------------ Event handlers ------------------------

function OnCommand(playerIndex, command, environment, rconPassword)
    local fullCommand = split(command, " ")
    local command = fullCommand[1]
    -- Erase main command from the list
    local commandArgs = shift(fullCommand, 1, -1)
    local sandboxCommand = SandboxCommands[command]
    if sandboxCommand then
        sandboxCommand(playerIndex, commandArgs)
        return false
    end
end

local function parseToyString(toystring)
    local functiondef = split(toystring, " -> ")
    return functiondef[1], shift(functiondef, 1, -1)
end

local function dispatchToy(event, playerIndex)
    for _, toystring in pairs(event) do
        local action, args = parseToyString(toystring)
        for toyname, toyfunc in pairs(SandboxToys) do
            if toyname == action then
                print(action)
                print(inspect(args))
                toyfunc(playerIndex, unpack(args))
            end
        end
    end
end

function OnPlayerDie(playerIndex, causer)
    local causer = tonumber(causer)
    -- Prevent some events from looping
    if causer > -1 then
        assert(sandboxGame, "Sandbox game type is not loaded!")
        dispatchToy(sandboxGame.when.player.dies, playerIndex)
    end
end

function OnPlayerSpawn(playerIndex)
    assert(sandboxGame, "Sandbox game type is not loaded!")
    dispatchToy(sandboxGame.when.player.spawns, playerIndex)
end

function OnPlayerKill(playerIndex)

end

function OnPlayerBetray(playerIndex)
    -- whenDispatcher(playerIndex, "player_betrays")
end

function OnPlayerAlive(playerIndex)
    local currentFunctions = queueFunctions[playerIndex]
    if currentFunctions then
        for actionIndex, action in pairs(currentFunctions) do
            action()
        end
        queueFunctions[playerIndex] = nil
    end
end

SandboxCommands = {
    load_gametype = function(playerIndex, commandArgs)
        local gameTypeName = commandArgs[1]
        if gameTypeName then
            loadGameType(gameTypeName)
        end
    end,
    unload_gametype = function(playerIndex, commandArgs)
        sandboxGame = nil
        say_all("Sandbox gametype was unloaded!")
    end
}
-- Aliases
SandboxCommands.lg = SandboxCommands.load_gametype
SandboxCommands.ug = SandboxCommands.unload_gametype

SandboxToys = {
    -- Team Actions
    ["swap team"] = function(playerIndex)
        local playerTeam = get_var(playerIndex, "$team")
        if (playerTeam == "red") then
            execute_command("st " .. playerIndex .. " blue")
        else
            execute_command("st " .. playerIndex .. " red")
        end
    end,
    ["switch team"] = function(playerIndex, team)
        execute_command("st " .. playerIndex .. " " .. team)
    end,
    -- Weapon Actions
    ["erase weapons"] = function(playerIndex)
        execute_command("wdel " .. playerIndex)
    end,
    ["add weapon"] = function(playerIndex, weaponTagPath)
        if weaponTagPath then
            local playerX = get_var(playerIndex, "$x")
            local playerY = get_var(playerIndex, "$y")
            local playerZ = get_var(playerIndex, "$z") + 1
            local weaponId = spawn_object("weap", weaponTagPath, playerX, playerY, playerZ)
            -- Check if this is the right way to chweck weapon spawn
            if not isNull(weaponId) then
                assign_weapon(weaponId, playerIndex)
            else
                local path = split(weaponTagPath, "\\")
                local inferedWeaponTagPath = weaponTagPath .. "\\" .. path[#path]
                weaponId = spawn_object("weap", inferedWeaponTagPath, playerX, playerY, playerZ)
                if (not isNull(weaponId)) then
                    assign_weapon(weaponId, playerIndex)
                else
                    error("Weapon \"" .. weaponTagPath .. "\" can not be spawned!")
                end
            end
        else
            error("add weapon is being executed with no params!")
        end
    end,
    ["add random weapon"] = function(playerIndex)
        local function abscoord(coord)
            return math.floor(math.abs(tonumber(get_var(playerIndex, "$" .. coord)) or 0))
        end
        local randomFactor = abscoord("x") + playerIndex + math.random(1, os.time())
        math.randomseed(os.time() + randomFactor)
        local weaponTagPath = usableWeaponTags[math.random(1, #usableWeaponTags)].path
        if weaponTagPath then
            local playerX = get_var(playerIndex, "$x")
            local playerY = get_var(playerIndex, "$y")
            local playerZ = get_var(playerIndex, "$z") + 1
            local weaponObjectId = spawn_object("weap", weaponTagPath, playerX, playerY, playerZ)
            -- Check if this is the right way to chweck weapon spawn
            if (not isNull(weaponObjectId)) then
                assign_weapon(weaponObjectId, playerIndex)
            else
                error("Weapon \"" .. weaponTagPath .. "\" can not be spawned!")
            end
        else
            error("add random weapon does not have any usable weapon tags!")
        end
    end,
    ["enter vehicle"] = function(playerIndex, vehicleTagPath, seat, overloadedSeat)
        if vehicleTagPath then
            local seat = tonumber(seat or "0")
            local playerX = get_var(playerIndex, "$x")
            local playerY = get_var(playerIndex, "$y")
            local playerZ = get_var(playerIndex, "$z") + 1
            local vehicleId = spawn_object("vehi", vehicleTagPath, playerX, playerY, playerZ)
            -- Check if this is the right way to check weapon spawn
            if not isNull(vehicleId) then
                enter_vehicle(vehicleId, playerIndex, seat)
                if overloadedSeat then
                    enter_vehicle(vehicleId, playerIndex, tonumber(overloadedSeat))
                end
            else
                local path = split(vehicleTagPath, "\\")
                local inferedVehicleTagPath = vehicleTagPath .. "\\" .. path[#path]
                vehicleId = spawn_object("vehi", inferedVehicleTagPath, playerX, playerY, playerZ)
                if not isNull(vehicleId) then
                    enter_vehicle(vehicleId, playerIndex, seat)
                    if (overloadedSeat) then
                        enter_vehicle(vehicleId, playerIndex, tonumber(overloadedSeat))
                    end
                else
                    error("Vehicle \"" .. vehicleTagPath .. "\" can not be spawned!")
                end
            end
        else
            error("enter vehicle is being executed with no params!")
        end
    end,
    ["set weapon battery"] = function(playerIndex, battery)
        if battery then
            execute_command("battery " .. playerIndex .. " " .. battery)
        else
            error("battery is being executed with no params!")
        end
    end,
    ["set weapon mag"] = function(playerIndex, mag)
        if mag then
            execute_command("mag " .. playerIndex .. " " .. mag)
        else
            error("set weapon mag is being executed with no params!")
        end
    end,

    ["set weapon ammo"] = function(playerIndex, ammo)
        if ammo then
            execute_command("ammo " .. playerIndex .. " " .. ammo)
            -- Set ammo as battery in case of a plasma/energy based weapon
            -- Check if is not causing conflicts with the weapons internal values
            -- execute_command("battery " .. playerIndex .. " " .. params.ammo)
        else
            error("set weapon ammo is being executed with no params!")
        end
    end,
    ["drop weapon"] = function(playerIndex)
        drop_weapon(playerIndex)
    end,
    -- Player properties
    ["set camo"] = function(playerIndex)
        execute_command("camo " .. playerIndex)
    end,
    ["set speed"] = function(playerIndex, speed)
        execute_command("s " .. playerIndex .. " " .. speed)
    end,
    ["set health"] = function(playerIndex, health)
        execute_command("hp " .. playerIndex .. " " .. health)
    end,
    ["set nades"] = function(playerIndex, fragmentation, plasma)
        execute_command("nades " .. playerIndex .. " " .. fragmentation .. " " .. plasma)
    end,
    -- Game actions
    ["disable objects"] = function(playerIndex, team)
        execute_command("disable_all_objects " .. team .. " 1")
    end,
    ["disable vehicles"] = function(playerIndex, team)
        execute_command("disable_all_vehicles " .. team .. " 1")
    end,
    ["say all"] = function(playerIndex, message)
        say_all(message)
    end,
    ["say"] = function(playerIndex, message)
        say(playerIndex, message)
    end
}

function loadGameType(gameTypeName)
    if gameTypeName then
        local gameTypeName = gameTypeName:gsub("\"", "")
        cprint("\nLoading gametype: " .. gameTypeName)

        local currentMapName = get_var(0, "$map"):gsub("_dev", "")
        cprint("Map: " .. currentMapName)

        local gametypeDefPath = gametypesPath:format(currentMapName, gameTypeName)
        if not glue.canopen(gametypeDefPath) then
            gametypeDefPath = gametypesPath:format("global", gameTypeName)
        end
        local ymlSand = luna.file.read(gametypeDefPath)
        if ymlSand then
            -- Replace forward slashes with backslashes (for compatibility with windows paths)
            ymlSand = ymlSand:replace("/", "\\")
            -- Load gametype locally
            sandboxGame = yml.parse(ymlSand)
            grprint("Gametype " .. gameTypeName .. " has been loaded!")

            -- Current stock gametype formalization
            local currentGametypeLike = get_var(0, "$mode"):lower():gsub(" ", "_")
            cprint("Gametype like: " .. currentGametypeLike .. "\n")

            -- Change stock gametype if sandbox gametype is based on another stock gametype
            local newGametypeLike = sandboxGame.like
            if sandboxGame.when.gametype then
                dispatchToy(sandboxGame.when.gametype.starts)
            end
            -- if (newGametypeLike and newGametypeLike ~= currentGametypeLike) then
            --    execute_command("sv_map \"" .. currentMapName .. "\" " .. newGametypeLike)
            -- else
            --    dispatchToy(sandboxGame.when.gametype.starts)
            --    execute_command("sv_map_reset")
            -- end
            return true
        else
            cprint("Desired gametype not found in gametypes folder!")
            return false
        end
    end
    return false
end
