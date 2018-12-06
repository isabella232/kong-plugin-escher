local Object = require "classic"
local date = require "date"
local EscherFactory = require "kong.plugins.escher.escher_factory"

local EscherWrapper = Object:extend()

local function parse_headers(ngx_headers)
    local headers = {}
    local mandatoryHeadersToSign = {}
    for key, value in pairs(ngx_headers) do
        table.insert(headers, {key, value})
        if key == 'x-suite-customerid' then
            table.insert(mandatoryHeadersToSign, key)
        end
    end

    return headers, mandatoryHeadersToSign
end

local function key_retriever(key_db)
    return function(key)
        return key_db:find_secret_by_key(key)
    end
end

function EscherWrapper:new(ngx, key_db)
    self.ngx = ngx
    self.key_db = key_db
end

function EscherWrapper:authenticate()
    local escher = EscherFactory.create()

    local request_headers = self.ngx.req.get_headers()
    local date_as_string = request_headers['x_ems_date']
    local success = pcall(date, date_as_string)

    if date_as_string and not success then
        return nil, "Could not parse X-Ems-Date header"
    end

    local headers_as_array, mandatory_headers_to_sign = parse_headers(request_headers)

    self.ngx.req.read_body()

    local request = {
        ["method"] = self.ngx.req.get_method(),
        ["url"] = self.ngx.var.request_uri,
        ["headers"] = headers_as_array,
        ["body"] = self.ngx.req.get_body_data()
    }

    local api_key, err = escher:authenticate(request, key_retriever(self.key_db), mandatory_headers_to_sign)

    if not api_key then
        return nil, err
    else
        return self.key_db:find_by_key(api_key)
    end

end

return EscherWrapper
