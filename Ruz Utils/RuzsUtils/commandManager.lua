---@class CommandSet
---@field prefix string
---@field map table<string, table<string, function|table>>
---@field log string
---@field help function|nil

---@class CommandManager
---@field utils RuzUtilsAPI
---@field sets CommandSet[]
---@field instance CommandManager|nil
local CommandManager = { instance = nil }
CommandManager.__index = CommandManager

---Creates and initializes a new Command Manager.
---@param utils RuzUtilsAPI
---@return CommandManager
function CommandManager.new(utils)
    if CommandManager.instance then return CommandManager.instance end
    
    ---@type CommandManager
    local self = setmetatable({ 
        utils = utils, 
        sets = {} 
    }, CommandManager)

    events.chat_send_message:register(function(msg)
        for _, set in ipairs(self.sets) do
            if msg:sub(1, #set.prefix) == set.prefix then
                self:handle(set, msg)
                host:appendChatHistory(msg)
                return "" -- Block original message
            end
        end
        return msg
    end)

    CommandManager.instance = self
    return self
end

---Registers a new set of commands with the manager.
---@param config table The command configuration table.
---@param handlers table<string, function|table> A map of command keys to handlers.
---@param logPrefix string
function CommandManager:registerCommandSet(config, handlers, logPrefix)
    if not (config and config.PREFIX and handlers) then return end
    
    -- Build lookup table: [rootAlias][subAlias] -> handler
    local lookup = {}
    for _, root in ipairs(config.ROOT and config.ROOT.aliases or {}) do
        lookup[root] = {}
        for key, data in pairs(config.SUBCOMMANDS or {}) do
            if handlers[key] then
                for _, alias in ipairs(data.aliases or {key}) do
                    lookup[root][alias] = handlers[key]
                end
            end
        end
    end

    table.insert(self.sets, { 
        prefix = config.PREFIX, 
        map = lookup, 
        log = logPrefix, 
        help = handlers.help 
    })
end

---Internal handler for processing matched messages.
---@param set CommandSet
---@param msg string
function CommandManager:handle(set, msg)
    local args = {}
    for part in msg:sub(#set.prefix + 1):gmatch("%S+") do table.insert(args, part) end
    
    local root, sub = args[1], args[2]
    local rootGroup = set.map[root]

    -- If no root match or no subcommand match, try help
    if not rootGroup or not sub or not rootGroup[sub] then
        return set.help and set.help()
    end

    local handler = rootGroup[sub]
    local cmdArgs = { table.unpack(args, 3) } -- Args starting after subcommand

    -- Handle simple function
    if type(handler) == "function" then
        return handler(cmdArgs)
    end

    -- Handle nested table (Sub-sub commands)
    if type(handler) == "table" then
        local subKey = cmdArgs[1]
        local subFn = handler[subKey]
        
        if type(subFn) == "function" then
            return subFn({ table.unpack(cmdArgs, 2) })
        else
            -- Generate available keys for error message
            local keys = {}
            for k in pairs(handler) do table.insert(keys, k) end
            local errorMsg = #keys > 0 and ("Available: " .. table.concat(keys, ", ")) or ""
            self.utils.log("Invalid option for '" .. sub .. "'. " .. errorMsg, "red", set.log)
        end
    end
end

return CommandManager