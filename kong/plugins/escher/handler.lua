local constants = require "kong.constants"
local BasePlugin = require "kong.plugins.base_plugin"

local EscherHandler = BasePlugin:extend()

EscherHandler.PRIORITY = 2000

function EscherHandler:new()
    EscherHandler.super.new(self, "escher")
end

function EscherHandler:access(conf)
    EscherHandler.super.access(self)

    ngx.req.set_header(constants.HEADERS.ANONYMOUS, true)

end

return EscherHandler
