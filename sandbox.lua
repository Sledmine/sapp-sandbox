-----------------------------------------------------------------------
-- Sandbox
-- Version 1.0.0
-- Custom dynamic game type controller
-----------------------------------------------------------------------
-- Api version must be declared at the top
-- It helps lua-blam to detect if the script is made for SAPP or Chimera
api_version = "1.12.0.0"

-- Lua libraries
local inspect = require "inspect"
local yml = require "tinyyaml"
local glue = require "glue"
local split = glue.string.split
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

---@type sandboxgametype
local sandboxGame

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
    betray = cb["EVENT_BETRAY"]
}

local gametypesPath = "gametypes/%s/%s.yml"

local queueFunctions = {}

------------------------ Sandbox setup ------------------------

--- Get if a value equals a null value for game
---@return boolean
local function isNull(value)
    if (value == 0xFF or value == 0xFFFF or value == 0xFFFFFFFF or value == nil) then
        return true
    end
    return false
end

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
        if (player_present(playerIndex)) then
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
    if (sandboxCommand) then
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
    if (causer > -1) then
        dispatchToy(sandboxGame.when.player.dies, playerIndex)
    end
end

function OnPlayerSpawn(playerIndex)
    dispatchToy(sandboxGame.when.player.spawns, playerIndex)
end

function OnPlayerKill(playerIndex)

end

function OnPlayerBetray(playerIndex)
    -- whenDispatcher(playerIndex, "player_betrays")
end

function OnPlayerAlive(playerIndex)
    local currentFunctions = queueFunctions[playerIndex]
    if (currentFunctions) then
        for actionIndex, action in pairs(currentFunctions) do
            action()
        end
        queueFunctions[playerIndex] = nil
    end
end

SandboxCommands = {
    load_gametype = function(playerIndex, commandArgs)
        local gameTypeName = commandArgs[1]
        if (gameTypeName) then
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
        if (weaponTagPath) then
            local playerX = get_var(playerIndex, "$x")
            local playerY = get_var(playerIndex, "$y")
            local playerZ = get_var(playerIndex, "$z") + 1
            local weaponId = spawn_object("weap", weaponTagPath, playerX, playerY, playerZ)
            -- Check if this is the right way to chweck weapon spawn
            if (not isNull(weaponId)) then
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
    ["enter vehicle"] = function(playerIndex, vehicleTagPath, seat, overloadedSeat)
        if (vehicleTagPath) then
            local seat = tonumber(seat or "0")
            local playerX = get_var(playerIndex, "$x")
            local playerY = get_var(playerIndex, "$y")
            local playerZ = get_var(playerIndex, "$z") + 1
            local vehicleId = spawn_object("vehi", vehicleTagPath, playerX, playerY, playerZ)
            -- Check if this is the right way to check weapon spawn
            if (not isNull(vehicleId)) then
                enter_vehicle(vehicleId, playerIndex, seat)
                if (overloadedSeat) then
                    enter_vehicle(vehicleId, playerIndex, tonumber(overloadedSeat))
                end
            else
                local path = split(vehicleTagPath, "\\")
                local inferedVehicleTagPath = vehicleTagPath .. "\\" .. path[#path]
                vehicleId = spawn_object("vehi", inferedVehicleTagPath, playerX, playerY, playerZ)
                if (not isNull(vehicleId)) then
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
        if (battery) then
            execute_command("battery " .. playerIndex .. " " .. battery)
        else
            error("battery is being executed with no params!")
        end
    end,
    ["set weapon mag"] = function(playerIndex, mag)
        if (mag) then
            execute_command("mag " .. playerIndex .. " " .. mag)
        else
            error("set weapon mag is being executed with no params!")
        end
    end,
    
    ["set weapon ammo"] = function(playerIndex, ammo)
        if (ammo) then
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
    if (gameTypeName) then
        cprint("\nLoading gametype: " .. gameTypeName)
        local currentMapName = get_var(0, "$map")
        cprint("Map: " .. currentMapName)
        local gametypePath = gametypesPath:format(currentMapName:gsub("_dev", ""),
                                                  gameTypeName:gsub("\"", ""))
        local ymlSand = glue.readfile(gametypePath, "t")
        if (ymlSand) then
            -- Load gametype locally
            sandboxGame = yml.parse(ymlSand)
            grprint("Gametype " .. gameTypeName .. " has been loaded!")

            -- Current stock gametype formalization
            local currentGametypeLike = get_var(0, "$mode"):lower():gsub(" ", "_")
            cprint("Gametype like: " .. currentGametypeLike .. "\n")

            -- Change stock gametype if sandbox gametype is based on another stock gametype
            local newGametypeLike = sandboxGame.like
            if (newGametypeLike and newGametypeLike ~= currentGametypeLike) then
                execute_command("sv_map \"" .. currentMapName .. "\" " .. newGametypeLike)
            else
                execute_command("sv_map_reset")
            end
            return true
        else
            cprint("Desired gametype not found in gametypes folder!")
            return false
        end
    end
    return false
end
