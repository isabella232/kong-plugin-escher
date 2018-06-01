local EasyCrypto = require "resty.easy-crypto"
local Object = require "classic"
local singletons = require "kong.singletons"

local load_key_from_file = function(path)
    local file = io.open(path, "r")

    if file == nil then
        error({msg = "Could not load encryption key."})
    end

    local encryption_key = file:read("*all")

    file:close()

    return encryption_key
end

local load_key = function(path)
    local cache_key = "ENCRYPTION_KEY"

    local key, err = singletons.cache:get(cache_key, nil, load_key_from_file, path)

    return key
end

local encryption_engine = function()
    return EasyCrypto:new({
        saltSize = 12,
        ivSize = 16,
        iterationCount = 10000
    })
end

local encrypter = function(encryption_key_path, subject)
    if encryption_key_path == nil then
        return subject
    else
        local encryption_key = load_key(encryption_key_path)
        return encryption_engine():encrypt(encryption_key, subject)
    end
end

local decrypter = function(encryption_key_path, subject)
    if encryption_key_path == nil then
        return subject
    else
        local encryption_key = load_key(encryption_key_path)
        return encryption_engine():decrypt(encryption_key, subject)
    end
end

local _M = Object:extend()

function _M:new(encryption_key_path)
    self.encryption_key_path = encryption_key_path
end

function _M:encrypt(subject)
    return encrypter(self.encryption_key_path, subject)
end

function _M:decrypt(subject)
    return decrypter(self.encryption_key_path, subject)
end

return _M
