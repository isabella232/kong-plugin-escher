local utils = require "kong.tools.utils"

local function check_user(anonymous)
  if anonymous == nil or utils.is_valid_uuid(anonymous) then
    return true
  end

  return false, "the anonymous user must be nil or a valid uuid"
end

local function ensure_file_exists(encryption_key_path)
  local file = io.open(encryption_key_path, "r")

  if file == nil then
    return false, "Encryption key file could not be found."
  end

  file:close()
  
  return true
end

return {
  no_consumer = true,
  fields = {
    anonymous = {type = "string", default = nil, func = check_user},
    encryption_key_path = {type = "string", func = ensure_file_exists}
  }
}
