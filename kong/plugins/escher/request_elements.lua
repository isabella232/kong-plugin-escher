local Object = require "classic"

local RequestElements = Object:extend()

function RequestElements:new(kong)
    self.kong = kong
end

function RequestElements:collect()
    return {
        ["method"] = self.kong.request.get_method(),
        ["url"] = self.kong.request.get_path(),
        ["headers"] = self.kong.request.get_headers(),
        ["body"] = self.kong.request.get_body("application/json")
    }
end

return RequestElements