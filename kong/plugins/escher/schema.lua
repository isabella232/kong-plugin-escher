local cjson = require "cjson"
local Errors = require "kong.dao.errors"
local utils = require "kong.tools.utils"
local EncryptionKeyPathRetriever =  require "kong.plugins.escher.encryption_key_path_retriever"

local function ensure_valid_uuid_or_nil(anonymous)
    if anonymous == nil or utils.is_valid_uuid(anonymous) then
        return true
    end

    return false, "Anonymous must a valid uuid if specified"
end

local function ensure_file_exists(file_path)
    local file = io.open(file_path, "r")

    if file == nil then
        return false, "Encryption key file could not be found."
    end

    file:close()

    return true
end

local function ensure_same_encryption_key_is_used(schema, config, dao, is_updating)
    local path = EncryptionKeyPathRetriever(dao):find_key_path()

    if path and path ~= config.encryption_key_path then
        return false, Errors.schema("All Escher plugins must be configured to use the same encryption file.")
    end

    return true
end

local function decode_json(message_template)
    return cjson.decode(message_template)
end

local function is_object(message_template)
    local first_char = message_template:sub(1, 1)
    local last_char = message_template:sub(-1)
    return first_char == '{' and last_char == '}'
end

local function ensure_message_template_is_valid_json(message_template)
    local ok = pcall(decode_json, message_template)

    if not ok or not is_object(message_template) then
        return false, "message_template should be valid JSON object"
    end

    return true
end

local function validate_http_status_code(status_code)
    if status_code >= 100 and status_code < 600 then
        return true
    end

    return false, "status code is invalid"
end

return {
    no_consumer = true,
    fields = {
        anonymous = { type = "string", default = nil, func = ensure_valid_uuid_or_nil },
        encryption_key_path = { type = "string", required = true, func = ensure_file_exists },
        message_template = { type = "string", default = '{"message": "%s"}', func = ensure_message_template_is_valid_json },
        status_code = { type = "number", default = 401, func = validate_http_status_code }
    },
    self_check = ensure_same_encryption_key_is_used
}
