local Object = require "classic"

local EncryptionKeyPathRetriever = Object:extend()

function EncryptionKeyPathRetriever:new(plugins_dao)
    self.plugins_dao = plugins_dao
end

function EncryptionKeyPathRetriever:find_key_path()
    local escher_plugins = self.plugins_dao:find_page({ name = "escher" }, 0, 1)

    return escher_plugins[1].config
end

return EncryptionKeyPathRetriever