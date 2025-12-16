if not host:isHost() then return end

---@class SimpleWheels
local SimpleWheels = {}

local mainPage = action_wheel:newPage()
local history = {}

local function goBack()
    local last = table.remove(history)

    action_wheel:setPage(last and last.page or mainPage)
    action_wheel.rightClick = last and last.rightClick or nil
end

local function navigateTo(page)
    history[#history + 1] = {
        page = action_wheel:getCurrentPage(),
        rightClick = action_wheel.rightClick
    }

    action_wheel:setPage(page)
    action_wheel.rightClick = goBack
end

function SimpleWheels:init()
    action_wheel:setPage(mainPage)
    action_wheel.rightClick = nil
end

--- Creates a new action wheel page
--- @param cfg {title?:string, item?:string, color?:Vector3, parent?:Page}
--- @return Page
function SimpleWheels:createPage(cfg)
    cfg = cfg or {}

    local page = action_wheel:newPage()
    local parent = cfg.parent or mainPage

    parent:newAction()
        :title(cfg.title or "Untitled")
        :item(cfg.item or "minecraft:stone")
        :color(cfg.color or vec(0,0,0))
        :onLeftClick(function()
            navigateTo(page)
        end)

    page:newAction()
        :title("Back")
        :item("minecraft:arrow")
        :onLeftClick(goBack)

    return page
end

--- Adds an action to a page
--- @param page Page
--- @param cfg {title?:string, item?:string, color?:Vector3, onLeftClick?:function, onToggle?:function}
function SimpleWheels:addAction(page, cfg)
    cfg = cfg or {}

    local action = page:newAction()
        :title(cfg.title or "Action")
        :item(cfg.item or "minecraft:stone")
        :color(cfg.color or vec(1,1,1))

    if cfg.onLeftClick then action:onLeftClick(cfg.onLeftClick) end
    if cfg.onToggle then action:onToggle(cfg.onToggle) end
end

SimpleWheels:init()
return SimpleWheels
