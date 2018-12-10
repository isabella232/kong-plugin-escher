local Object = require "classic"

local RequestElements = Object:extend()

function RequestElements:new(nginx)
    self.ngx = nginx
end

function RequestElements:collect()
    self.ngx.req.read_body()

    return {
        ["method"] = self.ngx.req.get_method(),
        ["url"] = self.ngx.var.request_uri,
        ["headers"] = self.ngx.req.get_headers(),
        ["body"] = self.ngx.req.get_body_data()
    }
end

return RequestElements