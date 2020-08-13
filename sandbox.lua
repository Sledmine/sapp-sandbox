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
local json = require "json"
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
}

------------------------ Sandbox setup ------------------------

--- Script initialization code
function OnScriptLoad()
    -- We can set up our event callbacks, like OnTick callback
    register_callback(event.command, "OnCommand")
    register_callback(event.die, "OnDie")
    register_callback(event.playerSpawn, "OnPlayerSpawn")
    -- register_callback(event.objectSpawn, "OnObjectSpawn")
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
    local fullCommand = glue.string.split(" ", command)
    local command = fullCommand[1]
    -- Erase main command from the list
    local commandArgs = glue.shift(fullCommand, 1, -1)
    local sandboxCommand = availableCommands[command]
    if (sandboxCommand) then
        sandboxCommand(playerIndex, commandArgs)
        rprint(playerIndex, "Sandbox command executed.")
    end
end

function eventDispatcher(playerIndex, eventName, args)
    if (currentGameType) then
        local playerTeam = get_var(playerIndex, "$team")
        local eventData = currentGameType.events[eventName]
        if (eventData) then
            local eventTeamVariant = eventData[playerTeam]
            if (eventTeamVariant) then
                teamBasedActions = eventTeamVariant.actions
                if (teamBasedActions) then
                    for actionPriority, action in pairs(teamBasedActions) do
                        local actionName = action.name
                        local eventAction = availableActions[actionName]
                        if (eventAction) then
                            return eventAction(playerIndex)
                        end
                    end
                end
            else
                local eventGeneralVariant = eventData["general"]
                if (eventGeneralVariant) then
                    generalActions = eventGeneralVariant.actions
                    if (generalActions) then
                        for actionPriority, action in pairs(generalActions) do
                            local actionName = action.name
                            local eventAction = availableActions[actionName]
                            if (eventAction) then
                                return eventAction(playerIndex)
                            end
                        end
                    end
                end
            end
        end
    end
end

function OnDie(playerIndex, causer)
    local causer = tonumber(causer)
    if (causer > -1) then
        eventDispatcher(playerIndex, "OnDie", {
            causer = causer,
        })
    end
end

function OnPlayerSpawn(playerIndex)
    eventDispatcher(playerIndex, "OnPlayerSpawn")
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
    ["swapTeam"] = function(playerIndex)
        local playerTeam = get_var(playerIndex, "$team")
        if (playerTeam == "red") then
            execute_command("st " .. playerIndex .. " blue")
        else
            execute_command("st " .. playerIndex .. " red")
        end
    end,
    ["switchBlue"] = function(playerIndex)
        execute_command("st " .. playerIndex .. " blue")
    end,
    ["switchRed"] = function(playerIndex)
        execute_command("st " .. playerIndex .. " red")
    end,

    -- Weapon Actions
    ["eraseWeapons"] = function(playerIndex)
        execute_command("wdel " .. playerIndex)
    end,
}

function loadGameType(gameTypeName)
    if (gameTypeName) then
        local gameTypeFileName = "gametypes\\" .. gameTypeName:gsub("\"", "") .. ".json"
        local gameTypeFile = glue.readfile(gameTypeFileName, "t")
        if (gameTypeFile) then
            currentGameType = json.decode(gameTypeFile)
            gprint("Game Type: " .. gameTypeName .. " has been loaded!")
            local actualBaseGameType = get_var(0, "$gt")
            local newBaseGameType = currentGameType.baseGameType
            if (newBaseGameType and newBaseGameType ~= actualBaseGameType) then
                local currentMapName = get_var(0, "$map")
                print("ACTUAL:" .. currentMapName)
                execute_command("sv_map \"" .. currentMapName .. "\" " .. newBaseGameType)
            end
            print(inspect(currentGameType))
        else
            error("Desired gametype not found in gametypes folder!")
        end
    end
    return nil
end
