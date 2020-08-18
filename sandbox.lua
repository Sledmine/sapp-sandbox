-----------------------------------------------------------------------
-- Sandbox
-- Version 1.0
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
local currentGameType

-- Easier callback event dispatcher
local event = {
    tick = cb["EVENT_TICK"],
    playerSpawn = cb["EVENT_SPAWN"],
    die = cb["EVENT_DIE"],
    command = cb["EVENT_COMMAND"],
    objectSpawn = cb["EVENT_OBJECT_SPAWN"],
    weaponPickUp = cb["EVENT_WEAPON_PICKUP"],
    alive = cb["EVENT_ALIVE"],
}

local queueFunctions = {}

------------------------ Sandbox setup ------------------------

--- Script initialization code
function OnScriptLoad()
    -- We can set up our event callbacks, like OnTick callback
    register_callback(event.command, "OnCommand")
    register_callback(event.die, "OnDie")
    register_callback(event.playerSpawn, "OnPlayerSpawn")
    -- This event is kinda special, needs testing
    register_callback(event.alive, "OnAlive")
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
    if (currentGameType) then
        local playerTeam = get_var(playerIndex, "$team")
        local eventData = currentGameType.events[eventName]
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

function OnDie(playerIndex, causer)
    local causer = tonumber(causer)
    -- Prevent some events from looping
    if (causer > -1) then
        eventDispatcher(playerIndex, "OnDie")
    end
end

function OnPlayerSpawn(playerIndex)
    eventDispatcher(playerIndex, "OnPlayerSpawn")
end

function OnAlive(playerIndex)
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
    end,
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
            local weaponId = spawn_object("weap", params.weaponPath, playerX, playerY, playerZ)
            -- Check if this is the right way to check weapon spawn
            if (weaponId ~= 4294967295) then
                assign_weapon(weaponId, playerIndex)
                -- A timer is needed to set weapon ammo in the same function sentence
                -- Because the player does not have the weapon loaded at setting the ammo amount
                -- Timer function can not use full function refence so we need a wrapper
                queueFunctions[playerIndex] = {
                    function()
                        availableActions.setPlayerWeaponAmmo(playerIndex, {
                            ammo = params.ammo,
                        })
                    end,
                }
            else
                error("Weapon \"" .. params.weaponPath .. "\" can not be spawned!")
            end
        else
            error("addPlayerWeapon is being executed with no params!")
        end
    end,
    --[[setPlayerWeaponBattery = function(playerIndex, params)
        if (params) then
            execute_command("battery " .. playerIndex .. " " .. params.energy)
        else
            error("setPlayerWeaponBattery is being executed with no params!")
        end
    end]]
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
}

function loadGameType(gameTypeName)
    if (gameTypeName) then
        local gameTypeFileName = "gametypes\\" .. gameTypeName:gsub("\"", "") .. ".yml"
        local gameTypeFile = glue.readfile(gameTypeFileName, "t")
        if (gameTypeFile) then
            currentGameType = yml.parse(gameTypeFile)
            gprint("Game Type: " .. gameTypeName .. " has been loaded!")
            local actualBaseGameType = get_var(0, "$mode"):lower():gsub(" ", "_")
            print("ACTUAL:" .. actualBaseGameType)
            local newBaseGameType = currentGameType.baseGameType
            if (newBaseGameType and newBaseGameType ~= actualBaseGameType) then
                local currentMapName = get_var(0, "$map")
                execute_command("sv_map \"" .. currentMapName .. "\" " .. newBaseGameType)
            else
                execute_command("sv_map_reset")
            end
            print(inspect(currentGameType))
        else
            error("Desired gametype not found in gametypes folder!")
        end
    end
    return nil
end
