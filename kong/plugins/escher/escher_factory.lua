local Escher = require "escher"

local EscherFactory = {}

EscherFactory.create = function()
    return Escher:new({
        ["vendorKey"] = "EMS",
        ["algoPrefix"] = "EMS",
        ["hashAlgo"] = "SHA256",
        ["credentialScope"] = "eu/suite/ems_request",
        ["authHeaderName"] = "X-Ems-Auth",
        ["dateHeaderName"] = "X-Ems-Date",
    })
end

return EscherFactory