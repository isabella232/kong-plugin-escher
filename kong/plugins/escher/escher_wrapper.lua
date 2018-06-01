local Escher = require "escher"
local Object = require "classic"

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
    local escher = Escher:new({
        ["vendorKey"] = "EMS",
        ["algoPrefix"] = "EMS",
        ["hashAlgo"] = "SHA256",
        ["credentialScope"] = "eu/suite/ems_request",
        ["authHeaderName"] = "X-Ems-Auth",
        ["dateHeaderName"] = "X-Ems-Date",
    })

    local headers, mandatory_headers_to_sign = parse_headers(self.ngx.req.get_headers())

    self.ngx.req.read_body()

    local request = {
        ["method"] = self.ngx.req.get_method(),
        ["url"] = self.ngx.var.request_uri,
        ["headers"] = headers,
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
