local Escher = require "escher"
local EscherFactory = require "kong.plugins.escher.escher_factory"

describe("escher factory", function()

    describe("#create", function()
        it("should create a new Escher instance with default parameters", function()
            local escher = Escher:new({
                ["vendorKey"] = "EMS",
                ["algoPrefix"] = "EMS",
                ["hashAlgo"] = "SHA256",
                ["credentialScope"] = "eu/suite/ems_request",
                ["authHeaderName"] = "X-Ems-Auth",
                ["dateHeaderName"] = "X-Ems-Date",
            })

            assert.are.same(EscherFactory.create(), escher)
        end)
    end)
end)