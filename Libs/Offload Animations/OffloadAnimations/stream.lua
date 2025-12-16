---@class AnimationStreamModule
local StreamManager = {}

---@type CodecModule
local Codec 
---@type OAConfig
local LocalConfig

local SEND_INTERVAL = 20
local MAX_PING_SIZE = 1024 
local MAX_BYTES_PER_SECOND 

local INTERP = { LINEAR = 1, CATMULL = 2, BEZIER = 3 }
local CHANNEL_IDS = { "position", "rotation", "scale" }

local sendQueue = {} 
local PartIDToName = {}

local function read_vec3(data, cursor)
    local v = {0, 0, 0}
    local raw_val
    for i = 1, 3 do
        raw_val, cursor = Codec.read_varint(data, cursor)
        v[i] = raw_val / LocalConfig.PRECISION
    end
    return v, cursor
end

local function read_catmull_coeffs(data, cursor)
    local c = {}
    local v

    v, cursor = Codec.read_varint(data, cursor); c.a = v / 100.0
    v, cursor = Codec.read_varint(data, cursor); c.b = v / 100.0
    v, cursor = Codec.read_varint(data, cursor); c.c = v / 100.0
    v, cursor = Codec.read_varint(data, cursor); c.d = v / 100.0
    return c, cursor
end

local function read_segment(data, cursor, context)
    if cursor > #data then return nil, cursor end

    local flag = string.byte(data, cursor)
    cursor = cursor + 1

    local isNewContext = (flag % 2) == 1
    local isInheritVal = (math.floor(flag / 2) % 2) == 1
    local isZeroDelta  = (math.floor(flag / 4) % 2) == 1
    local interpBits   = math.floor(flag / 8) % 4 

    if isNewContext then
        if cursor > #data then return nil, cursor end
        local packed = string.byte(data, cursor)
        cursor = cursor + 1
        context.lastPartId = bit32.rshift(packed, 3)
        context.lastChId = bit32.band(packed, 0x07)
        context.lastTime = 0
        context.expectedVal = {0, 0, 0}
    end

    local seg = { value = {0,0,0}, delta = {0,0,0} }
    local dt; dt, cursor = Codec.read_varint(data, cursor)
    seg.time = context.lastTime + dt
    context.lastTime = seg.time

    local dur; dur, cursor = Codec.read_varint(data, cursor)
    seg.duration = dur
    seg.invDuration = dur > 0 and (1 / dur) or 0

    seg.interp = (interpBits == 1 and INTERP.CATMULL) 
             or (interpBits == 2 and INTERP.BEZIER) 
             or INTERP.LINEAR

    if isInheritVal then
        seg.value = { table.unpack(context.expectedVal) }
    else
        seg.value, cursor = read_vec3(data, cursor)
    end

    if not isZeroDelta then
        seg.delta, cursor = read_vec3(data, cursor)
    end

    for i=1,3 do context.expectedVal[i] = seg.value[i] + seg.delta[i] end

    if seg.interp == INTERP.CATMULL then
        seg.coeffX, cursor = read_catmull_coeffs(data, cursor)
        seg.coeffY, cursor = read_catmull_coeffs(data, cursor)
        seg.coeffZ, cursor = read_catmull_coeffs(data, cursor)
    elseif seg.interp == INTERP.BEZIER then
        seg.bezier = { leftTime={}, rightTime={}, leftVal={}, rightVal={} }
        for i = 1, 3 do
            local lt, rt, lv, rv
            lt, cursor = Codec.read_u8(data, cursor)
            rt, cursor = Codec.read_u8(data, cursor)
            lv, cursor = Codec.read_varint(data, cursor)
            rv, cursor = Codec.read_varint(data, cursor)
            seg.bezier.leftTime[i]  = lt / 255.0
            seg.bezier.rightTime[i] = rt / 255.0
            seg.bezier.leftVal[i]   = lv / 10000.0
            seg.bezier.rightVal[i]  = rv / 10000.0   
        end
    end

    return seg, cursor, context.lastPartId, context.lastChId
end

--- @param codec CodecModule
--- @param localConfig OAConfig
function StreamManager.init(codec, localConfig)
    Codec = codec
    LocalConfig = localConfig
    MAX_BYTES_PER_SECOND = LocalConfig.MAX_BYTES_PER_SECOND
end

--- Takes the ID map from the manifest and ensures StreamManager knows which ID maps to which part name.
--- @param manifestIDs table Key: PartName (string), Value: ID (number)
function StreamManager.updatePartMap(manifestIDs)
    if not manifestIDs then return end
    PartIDToName = {}
    
    for partName, id in pairs(manifestIDs) do
        PartIDToName[id] = partName
    end
end

--- Adjusts the upload speed limit.
--- @param bytesPerSecond number The maximum bytes allowed per second.
function StreamManager.setBandwidthLimit(bytesPerSecond)
    MAX_BYTES_PER_SECOND = bytesPerSecond
end

--- Prepares and queues an animation for streaming.
--- @param animationData table The animation object containing chunks.
--- @param speed number The playback speed multiplier.
--- @param overrideVanilla boolean Whether to hide vanilla model parts.
--- @param initiator string The name of the initiator of the animation
--- @return number playStartTime The future world time tick when playback should start.
function StreamManager.sendAnimation(animationData, speed, overrideVanilla, initiator)
    local chunks = animationData.chunks
    if not chunks or #chunks == 0 then return nil end

    local rawChunks = {}
    local totalBytes = 0
    for i, b64 in ipairs(chunks) do
        local raw = Codec.base64_decode(b64)
        rawChunks[i] = raw
        totalBytes = totalBytes + #raw
    end

    local ticksNeeded = math.ceil(totalBytes / MAX_BYTES_PER_SECOND) * 20
    --- @diagnostic disable-next-line
    local playStartTime = world:getTime() + ticksNeeded + 20

    sendQueue[animationData.hash] = { 
        chunks = rawChunks, 
        nextChunk = 1, 
        timer = 0 
    }

    pings.anim_header(playStartTime, overrideVanilla, speed, animationData.duration, initiator)
    return playStartTime
end

--- Updates the streaming queue, sending chunks in batches respecting bandwidth limits.
--- @param delta number The time delta since last tick.
function StreamManager.update(delta)
    for hash, queue in pairs(sendQueue) do
        queue.timer = queue.timer + delta

        if queue.timer >= SEND_INTERVAL then
            queue.timer = 0 
            local batchBuffer = {}
            local currentBatchSize = 0
            local allowedBytes = math.min(MAX_BYTES_PER_SECOND, MAX_PING_SIZE)
            
            while queue.nextChunk <= #queue.chunks do
                local nextData = queue.chunks[queue.nextChunk]
                if currentBatchSize > 0 and (currentBatchSize + #nextData > allowedBytes) then
                    break -- Batch full
                end
                
                batchBuffer[#batchBuffer+1] = nextData
                currentBatchSize = currentBatchSize + #nextData
                queue.nextChunk = queue.nextChunk + 1
            end

            if #batchBuffer > 0 then
                pings.anim_chunk(table.concat(batchBuffer))
            end

            if queue.nextChunk > #queue.chunks then
                sendQueue[hash] = nil
            end
        end
    end
end

--- Stops all active transfers and clears the queue.
function StreamManager.stop()
    sendQueue = {}
end

--- Decodes a received binary chunk and appends the keyframes to the animation state.
--- @param data string The raw binary chunk data.
--- @param animationState table The active animation state object to populate.
function StreamManager.decodeChunkIntoState(data, animationState)
    local cursor = 1
    local ctx = animationState.readContext or {
        lastPartId = -1, lastChId = -1, lastTime = 0, expectedVal = {0,0,0}
    }
    
    if not animationState.hasReadHeader then
        cursor = 5
        animationState.hasReadHeader = true
    end

    while cursor <= #data do
        local segment, newCursor, pId, cId = read_segment(data, cursor, ctx)
        if not segment then break end
        cursor = newCursor

        local partName = PartIDToName[pId]

        if partName and CHANNEL_IDS[cId] then
            if LocalConfig.data.modelParts[partName] then
                local channel = CHANNEL_IDS[cId]
                local tfs = animationState.transforms
                
                local partTfs = tfs[partName] or {}
                tfs[partName] = partTfs
                
                local list = partTfs[channel] or {}
                partTfs[channel] = list
                
                list[#list+1] = segment
            end
        end
    end
    animationState.readContext = ctx 
end

return StreamManager