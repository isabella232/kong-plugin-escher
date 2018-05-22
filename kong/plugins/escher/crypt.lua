local Object = require("classic")

local singletons = require "kong.singletons"

local load_key_from_file = function(path)
    local file = io.open(path, "r")

    if file == nil then
        error({msg = "Could not load encryption key."})
    end

    local encryption_key = file:read()

    file:close()

    return encryption_key
end

local load_key = function(path)
    local cache_key = "ENCRYPTION_KEY"

    local key, err = singletons.cache:get(cache_key, nil, load_key_from_file, path)

    return key
end

local encrypt_with_key = function(subject, key)
    return subject
end

local decrypt_with_key = function(subject, key)
    return subject
end

local _M = Object:extend()

function _M:new(encryption_key_path)
    self.encryption_key_path = encryption_key_path
end

function _M:encrypt(subject)
    local encryption_key = load_key(self.encryption_key_path)

    return encrypt_with_key(subject, encryption_key)
end

function _M:decrypt(subject)
    local encryption_key = load_key(self.encryption_key_path)

    return decrypt_with_key(subject, encryption_key)
end

return _M
