local Object = require "classic"

local function collect_defaults(plugin_schema)
    local result = {}

    for key, value in pairs(plugin_schema.fields or {}) do
        result[key] = value.default
    end

    return result
end

local PluginConfig = Object:extend()

function PluginConfig:new(plugin_schema)
    self.plugin_schema = plugin_schema
end

function PluginConfig:merge_onto_defaults(config)
    local config_with_defaults = collect_defaults(self.plugin_schema)

    for field, value in pairs(config) do
        config_with_defaults[field] = value
    end

    return config_with_defaults
end

return PluginConfig
