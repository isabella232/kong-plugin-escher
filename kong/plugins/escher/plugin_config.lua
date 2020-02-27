local Object = require "classic"
local Schema = require("kong.db.schema")
local utils = require "kong.tools.utils"

local function collect_defaults(plugin_schema)
    local defaults = {}

    local config_field
    for _, field in ipairs(plugin_schema.fields) do
        if field.config then
            config_field = field.config
        end
    end

    if config_field then
       local schema = assert(Schema.new(config_field))
        for name, field in schema:each_field() do
            defaults[name] = field.default
        end
    end

    return defaults
end

local PluginConfig = Object:extend()

function PluginConfig:new(plugin_schema)
    self.plugin_schema = plugin_schema
end

function PluginConfig:merge_onto_defaults(actual_config)
    local config_defaults = collect_defaults(self.plugin_schema)
    return utils.table_merge(config_defaults, actual_config)
end

return PluginConfig
