local Object = require "classic"

local RequestElements = Object:extend()

function RequestElements:new(kong)
    self.kong = kong
end

function RequestElements:collect()
    return {
        method = self.kong.request.get_method(),
        url = self.kong.request.get_path_with_query(),
        headers = self.kong.request.get_headers(),
        body = self.kong.request.get_raw_body()
    }
end

return RequestElements
