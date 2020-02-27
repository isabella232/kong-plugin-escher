local Access = require "kong.plugins.escher.access"
local BasePlugin = require "kong.plugins.base_plugin"
local InitWorker = require "kong.plugins.escher.init_worker"
local Logger = require "logger"
local PluginConfig = require "kong.plugins.escher.plugin_config"
local schema = require "kong.plugins.escher.schema"

local EscherHandler = BasePlugin:extend()

EscherHandler.PRIORITY = 1007

local function anonymous_passthrough_is_enabled(plugin_config)
    return plugin_config.anonymous ~= nil
end

local function already_authenticated_by_other_plugin(plugin_config, authenticated_credential)
    return anonymous_passthrough_is_enabled(plugin_config) and authenticated_credential ~= nil
end

function EscherHandler:new()
    EscherHandler.super.new(self, "escher")
end

function EscherHandler:init_worker()
    EscherHandler.super.init_worker(self)

    InitWorker.execute()
end

function EscherHandler:access(original_config)
    EscherHandler.super.access(self)

    local conf = PluginConfig(schema):merge_onto_defaults(original_config)

    if already_authenticated_by_other_plugin(conf, ngx.ctx.authenticated_credential) then
        return
    end

    local success, result = pcall(Access.execute, conf)

    if not success then
        Logger.getInstance(ngx):logError(result)

        return kong.response.exit(500, { message = "An unexpected error occurred." })
    end

    return result
end

return EscherHandler
