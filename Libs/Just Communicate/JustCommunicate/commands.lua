---@class JustCommunicateCommands
local Commands = {}

---Initializes and registers JustCommunicate commands.
---@param config table The main configuration table.
---@param utils RuzUtilsAPI The utilities API.
---@param whitelist WhitelistInstance The whitelist API instance.
function Commands.init(config, utils, whitelist)
    local CM = utils.CommandManager.instance
    local PREFIX = config.LOG_PREFIX_JSON
    local TYPES = config.LOGTYPES

    ---Logs a standard result object {success: boolean, message: string}
    local function logResult(result)
        local color = result.success and TYPES.LOG or TYPES.WARNING
        utils.log(result.message, color, PREFIX)
    end

    ---Handles adding/removing players by name/UUID string.
    local function modifyList(action, args)
        if not args[1] then
            return utils.log("Usage: wl " .. action .. " <player1,player2>", TYPES.ERROR, PREFIX)
        end

        local func = action == "add" and whitelist.addToWhitelist or whitelist.removeFromWhitelist
        for id in args[1]:gmatch("([^,]+)") do
            logResult(func(whitelist, id))
        end
    end

    ---Handles adding/removing the entity the player is looking at.
    local function modifyLooking(action)
        local entity = utils.getLookingAtEntity(20)
        if not entity or not utils.isValidUUID(entity:getUUID()) then
            return utils.log("You are not looking at a valid player.", TYPES.ERROR, PREFIX)
        end

        local func = action == "add" and whitelist.addToWhitelist or whitelist.removeFromWhitelist
        logResult(func(whitelist, entity:getUUID()))
    end

    ---Generates the dynamic help menu based on config.
    local function showHelp()
        printJson('[{"text":" --- JustCommunicate Commands ---\\n","color":"gold"}]')
        
        local root = config.COMMANDS.ROOT
        local aliases = table.concat(root.aliases, ", ")
        printJson(string.format('[{"text":"Prefixes: ","color":"yellow"},{"text":"%s\\n","color":"white"}]', aliases))

        for _, data in pairs(config.COMMANDS.SUBCOMMANDS) do
            local name = data.aliases[1]
            if data.subcommands then
                for subName, subData in pairs(data.subcommands) do
                    printJson(string.format(
                        '[{"text":"  %s %s","color":"aqua"},{"text":" | %s %s\\n","color":"white"}]',
                        name, subName, subData.desc or "", subData.usage or ""
                    ))
                end
            else
                printJson(string.format(
                    '[{"text":"  %s","color":"aqua"},{"text":" | %s\\n","color":"white"}]',
                    name, data.desc or ""
                ))
            end
        end
    end

    local handlers = {
        help = showHelp,

        whitelist = {
            add = function(args) modifyList("add", args) end,
            remove = function(args) modifyList("remove", args) end,
            
            set = function(args)
                if not args[1] then return utils.log("Usage: wl set <*|all|none>", TYPES.ERROR, PREFIX) end
                logResult(whitelist:setWhitelistMode(args[1]:lower()))
            end,

            list = function()
                local list = whitelist:getWhitelisted()
                local msg = #list == 0 and "No players in whitelist." or "Whitelisted: " .. table.concat(list, ", ")
                utils.log(msg, TYPES.LOG, PREFIX)
            end
        },

        whitelistLooking = {
            add = function() modifyLooking("add") end,
            remove = function() modifyLooking("remove") end
        }
    }

    CM:registerCommandSet(config.COMMANDS, handlers, PREFIX)
end

return Commands