local Object = require "classic"
local Escher = require "escher"
local KeyDb = require "kong.plugins.escher.key_db"

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

function EscherWrapper:new(ngx)
    self.ngx = ngx
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

    local api_key, err = escher:authenticate(request, KeyDb.find_secret_by_key, mandatory_headers_to_sign)

    if not api_key then
        return nil, err
    else
        return KeyDb.find_by_key(api_key)
    end

end

return EscherWrapper