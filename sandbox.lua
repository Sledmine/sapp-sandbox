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

-- Local variables to the script
local sandboxGameType

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

local queueFunctions = {}

------------------------ Sandbox setup ------------------------

--- Script initialization code
function OnScriptLoad()
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
function gprint(message)
    for playerIndex = 1, 16 do
        if (player_present(playerIndex)) then
            rprint(playerIndex, message)
        end
    end
end

------------------------ Event handlers ------------------------

function OnCommand(playerIndex, command, environment, rconPassword)
    local fullCommand = glue.string.split(command, " ")
    local command = fullCommand[1]
    -- Erase main command from the list
    local commandArgs = glue.shift(fullCommand, 1, -1)
    local sandboxCommand = availableCommands[command]
    if (sandboxCommand) then
        sandboxCommand(playerIndex, commandArgs)
        rprint(playerIndex, "Sandbox command executed.")
    end
end

function eventDispatcher(playerIndex, eventName)
    if (sandboxGameType) then
        local playerTeam = get_var(playerIndex, "$team")
        local eventData = sandboxGameType.events[eventName]
        if (eventData) then
            local eventGeneralVariant = eventData["general"]
            if (eventGeneralVariant) then
                generalActions = eventGeneralVariant.actions
                if (generalActions) then
                    for actionPriority, action in pairs(generalActions) do
                        local actionName = action.name
                        local actionParams = action.params
                        local eventAction = availableActions[actionName]
                        if (eventAction) then
                            eventAction(playerIndex, actionParams)
                        else
                            error("There is an event with no actions in the current gametype!")
                        end
                    end
                end
            end
            local eventTeamVariant = eventData[playerTeam]
            if (eventTeamVariant) then
                teamBasedActions = eventTeamVariant.actions
                if (teamBasedActions) then
                    for actionPriority, action in pairs(teamBasedActions) do
                        local actionName = action.name
                        local actionParams = action.params
                        local eventAction = availableActions[actionName]
                        if (eventAction) then
                            eventAction(playerIndex, actionParams)
                        else
                            error("There is an event with no actions in the current gametype!")
                        end
                    end
                end
            end
        end
    end
end

function OnPlayerDie(playerIndex, causer)
    local causer = tonumber(causer)
    -- Prevent some events from looping
    if (causer > -1) then
        eventDispatcher(playerIndex, "OnPlayerDie")
    end
end

function OnPlayerSpawn(playerIndex)
    eventDispatcher(playerIndex, "OnPlayerSpawn")
end

function OnPlayerKill(playerIndex)
    eventDispatcher(playerIndex, "OnPlayerKill")
end

function OnPlayerBetray(playerIndex)
    eventDispatcher(playerIndex, "OnPlayerBetray")
end

function OnPlayerAlive(playerIndex)
    eventDispatcher(playerIndex, "OnPlayerAlive")
    local currentFunctions = queueFunctions[playerIndex]
    if (currentFunctions) then
        for actionIndex, action in pairs(currentFunctions) do
            action()
        end
        queueFunctions[playerIndex] = nil
    end
end

------------------------ Sandbox functions ------------------------

availableCommands = {
    -- Load gametype command
    ["lg"] = function(playerIndex, commandArgs)
        local gameTypeName = commandArgs[1]
        if (gameTypeName) then
            loadGameType(gameTypeName)
        end
    end
}

availableActions = {
    -- Team Actions
    swapTeam = function(playerIndex)
        local playerTeam = get_var(playerIndex, "$team")
        if (playerTeam == "red") then
            execute_command("st " .. playerIndex .. " blue")
        else
            execute_command("st " .. playerIndex .. " red")
        end
    end,
    switchBlue = function(playerIndex)
        execute_command("st " .. playerIndex .. " blue")
    end,
    switchRed = function(playerIndex)
        execute_command("st " .. playerIndex .. " red")
    end,
    -- Weapon Actions
    eraseWeapons = function(playerIndex)
        execute_command("wdel " .. playerIndex)
    end,
    addPlayerWeapon = function(playerIndex, params)
        if (params) then
            local playerX = get_var(playerIndex, "$x")
            local playerY = get_var(playerIndex, "$y")
            local playerZ = get_var(playerIndex, "$z") + 1
            local weaponId = spawn_object("weap", params.weapon, playerX, playerY, playerZ)
            -- Check if this is the right way to check weapon spawn
            if (weaponId ~= 4294967295) then
                assign_weapon(weaponId, playerIndex)
                -- A timer is needed to set weapon ammo in the same function sentence
                -- Because the player does not have the weapon loaded at setting the ammo amount
                -- Timer function can not use full function refence so we need a wrapper
                queueFunctions[playerIndex] = {
                    function()
                        if (params.mag) then
                            availableActions.setPlayerWeaponMag(playerIndex, {
                                mag = params.mag
                            })
                        end
                        if (params.ammo) then
                            availableActions.setPlayerWeaponAmmo(playerIndex, {
                                ammo = params.ammo
                            })
                        elseif (params.battery) then
                            availableActions.setPlayerWeaponBattery(playerIndex,
                                                                    {
                                battery = params.battery
                            })
                        end
                    end
                }
            else
                error("Weapon \"" .. params.weapon .. "\" can not be spawned!")
            end
        else
            error("addPlayerWeapon is being executed with no params!")
        end
    end,
    addPlayerWeapons = function(playerIndex, params)
        if (params.weapons) then
            for weaponNumber, weaponRow in pairs(params.weapons) do

            end
        else
            error("addPlayerWeaponRandom does not have weapons specified for!")
        end
    end,
    setPlayerWeaponBattery = function(playerIndex, params)
        if (params and params.battery) then
            execute_command("battery " .. playerIndex .. " " .. params.battery)
        else
            error("setPlayerWeaponBattery is being executed with no params!")
        end
    end,
    setPlayerWeaponMag = function(playerIndex, params)
        if (params) then
            execute_command("mag " .. playerIndex .. " " .. params.mag)
        else
            error("setPlayerWeaponMag is being executed with no params!")
        end
    end,
    setPlayerWeaponAmmo = function(playerIndex, params)
        if (params) then
            print("Setting ammo to player: " .. playerIndex)
            execute_command("ammo " .. playerIndex .. " " .. params.ammo)
            -- Set ammo as battery in case of a plasma/energy based weapon
            -- Check if is not causing conflicts with the weapons internal values
            -- execute_command("battery " .. playerIndex .. " " .. params.ammo)
        else
            error("setPlayerWeaponAmmo is being executed with no params!")
        end
    end,
    dropPlayerWeapon = function(playerIndex)
        drop_weapon(playerIndex)
    end,
    -- Player properties
    setPlayerCamo = function(playerIndex, params)
        execute_command("camo " .. playerIndex)
    end,
    setPlayerSpeed = function(playerIndex, params)
        execute_command("s " .. playerIndex .. " " .. params.speed)
    end,
    setPlayerHealth = function(playerIndex, params)
        execute_command("hp " .. playerIndex .. " " .. params.health)
    end,
    setPlayerNades = function(playerIndex, params)
        execute_command("nades " .. playerIndex .. " " .. params.frag .. " " .. params.plasma)
    end,
    -- Game actions
    disableAllObjects = function(playerIndex, params)
        execute_command("disable_all_objects " .. params.team .. " 1")
    end,
    disableAllVehicles = function(playerIndex, params)
        execute_command("disable_all_vehicles " .. params.team .. " 1")
    end
}

function loadGameType(gameTypeName)
    if (gameTypeName) then
        local currentMapName =  get_var(0, "$map")
        print(currentMapName)
        local sandboxGameTypePath = "gametypes\\" .. currentMapName .. "\\" .. gameTypeName:gsub("\"", "") .. ".yml"
        local sandboxGameTypeContent = glue.readfile(sandboxGameTypePath, "t")

        if (sandboxGameTypeContent) then
            sandboxGameType = yml.parse(sandboxGameTypeContent)
            gprint("Sandbox Game Type: " .. gameTypeName .. " has been loaded!")
        
            local currentStockGameType = get_var(0, "$mode"):lower():gsub(" ", "_")
            print("Current Stock Game Type:" .. currentStockGameType)
            local newStockGameType = sandboxGameType.baseGameType
            if (newStockGameType and newStockGameType ~= currentStockGameType) then
                execute_command("sv_map \"" .. currentMapName .. "\" " .. newStockGameType)
            else
                execute_command("sv_map_reset")
            end
            print(inspect(sandboxGameType))
            return true
        else
            print("Desired gametype not found in gametypes folder!")
            return false
        end
    end
    return false
end
