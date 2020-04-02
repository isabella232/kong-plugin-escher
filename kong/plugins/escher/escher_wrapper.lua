local Object = require "classic"
local date = require "date"
local base64 = require "base64"
local EscherFactory = require "kong.plugins.escher.escher_factory"

local EscherWrapper = Object:extend()

local function parse_headers(ngx_headers)
    local headers = {}

    for key, value in pairs(ngx_headers) do
        table.insert(headers, {key, value})
    end

    return headers
end

local function key_retriever(key_db)
    return function(key)
        return key_db:find_secret_by_key(key)
    end
end

function EscherWrapper:new(key_db)
    self.key_db = key_db
end

function EscherWrapper:authenticate(request, mandatory_headers_to_sign)
    local escher = EscherFactory.create()
    local request_headers = request.headers
    local date_as_string = request_headers["x-ems-date"]
    local success = pcall(date, date_as_string)

    if date_as_string and not success then
        return nil, "Could not parse X-Ems-Date header"
    end

    local headers_as_array = parse_headers(request_headers)

    local transformed_request = {
        method = request.method,
        url = request.url,
        headers = headers_as_array,
        body = request.body
    }

    local api_key, err, debug_info = escher:authenticate(transformed_request, key_retriever(self.key_db), mandatory_headers_to_sign)

    if not api_key then
        if request_headers["x-ems-debug"] and debug_info then
            err = err .. " (Base64 encoded debug message: '" .. base64.encode(debug_info) .. "')"
        end

        return nil, err
    else
        return self.key_db:find_by_key(api_key)
    end

end

return EscherWrapper
