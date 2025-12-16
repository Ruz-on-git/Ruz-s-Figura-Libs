---@class CodecModule
local Codec = {}

local PRECISION = 100.0

-- Base64 Lookup Table
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64map = {}
for i = 1, 64 do
    b64map[string.byte(b64chars, i)] = i - 1
end

--- Decodes a Base64 encoded string into its raw binary representation.
--- @param data string The Base64 encoded string to decode.
--- @return string result The decoded binary string.
function Codec.base64_decode(data)
    data = string.gsub(data, '[^'..b64chars..'=]', '')
    local output = {}
    local len = #data
    
    for i = 1, len, 4 do
        local a = b64map[string.byte(data, i)]
        local b = b64map[string.byte(data, i+1)]
        local c = b64map[string.byte(data, i+2)]
        local d = b64map[string.byte(data, i+3)]

        if not a or not b then break end

        local buffer = bit32.lshift(a, 18) + bit32.lshift(b, 12)
        local bytes_to_write = 1

        if c then buffer = buffer + bit32.lshift(c, 6); bytes_to_write = 2 end
        if d then buffer = buffer + d; bytes_to_write = 3 end

        table.insert(output, string.char(bit32.band(bit32.rshift(buffer, 16), 0xFF)))
        if bytes_to_write >= 2 then
            table.insert(output, string.char(bit32.band(bit32.rshift(buffer, 8), 0xFF)))
        end
        if bytes_to_write >= 3 then
            table.insert(output, string.char(bit32.band(buffer, 0xFF)))
        end
    end
    return table.concat(output)
end

--- Encodes a number as a 16-bit signed integer with fixed-point precision (x100).
--- @param value number The floating-point number to encode.
--- @return string result A 2-byte binary string representing the encoded value (Big Endian).
function Codec.write_i16(value)
    local int_val = math.floor(value * PRECISION + 0.5)
    if int_val < 0 then int_val = int_val + 65536 end

    -- Write Big Endian
    local b1 = bit32.band(bit32.rshift(int_val, 8), 255)
    local b2 = bit32.band(int_val, 255)
    return string.char(b1) .. string.char(b2)
end

--- Reads a 16-bit signed integer from a binary string and converts it back to a floating-point number.
--- @param data string The binary data string.
--- @param index number The current cursor position (1-based index) to read from.
--- @return number value The decoded floating-point number.
--- @return number newIndex The updated cursor position after reading 2 bytes.
function Codec.read_i16(data, index)
    local b1 = string.byte(data, index)
    local b2 = string.byte(data, index + 1)
    
    if not b1 or not b2 then return 0, index + 2 end

    local int_val = (b1 * 256) + b2
    if int_val >= 32768 then int_val = int_val - 65536 end

    return (int_val / PRECISION), index + 2
end

--- Reads a single unsigned 8-bit integer (byte) from the data stream.
--- @param data string The binary data string.
--- @param index number The current cursor position to read from.
--- @return number value The unsigned integer value (0-255).
--- @return number newIndex The updated cursor position after reading 1 byte.
function Codec.read_u8(data, index)
    return string.byte(data, index) or 0, index + 1
end

--- Writes a single unsigned 8-bit integer to a character string.
--- @param value number The integer value (0-255) to write.
--- @return string result A single-character string representing the byte.
function Codec.write_u8(value)
    return string.char(value)
end

--- Reads a variable-length integer (VarInt) with ZigZag decoding from the data stream.
--- @param data string The binary data string.
--- @param cursor number The current cursor position to start reading from.
--- @return number value The decoded signed integer.
--- @return number newCursor The updated cursor position after reading the VarInt.
function Codec.read_varint(data, cursor)
    local result = 0
    local shift = 0
    local b
    repeat
        if cursor > #data then return 0, cursor end
        b = string.byte(data, cursor)
        cursor = cursor + 1
        result = bit32.bor(result, bit32.lshift(bit32.band(b, 0x7F), shift))
        shift = shift + 7
    until bit32.band(b, 0x80) == 0
    
    local decoded = bit32.bxor(bit32.rshift(result, 1), -bit32.band(result, 1))
    if decoded >= 2147483648 then decoded = decoded - 4294967296 end
    return decoded, cursor
end

return Codec