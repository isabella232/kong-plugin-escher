local utils = require "kong.tools.utils"
local Errors = require "kong.dao.errors"

local function check_user(anonymous)
  if anonymous == nil or utils.is_valid_uuid(anonymous) then
    return true
  end

  return false, "Anonymous must a valid uuid if specified"
end

local function file_exists(file_path)
  local file = io.open(file_path, "r")

  if file == nil then
    return false, "Encryption key file could not be found."
  end

  file:close()
  
  return true
end

local function ensure_file_exists(encryption_key_path)
  if encryption_key_path == nil then
    return true
  end

  return file_exists(encryption_key_path)
end

local function ensure_same_encryption_key_is_used(schema, config, dao, is_updating)
  local escher_plugins = dao:find_all({name = "escher"})

  for i, plugin in ipairs(escher_plugins) do
    if plugin.config.encryption_key_path ~= config.encryption_key_path then
      return false, Errors.schema("All Escher plugins must be configured to use the same encryption file.")
    end
  end

  return true
end

return {
  no_consumer = true,
  fields = {
    anonymous = {type = "string", default = nil, func = check_user},
    encryption_key_path = {type = "string", default = nil, func = ensure_file_exists}
  },
  self_check = ensure_same_encryption_key_is_used
}
