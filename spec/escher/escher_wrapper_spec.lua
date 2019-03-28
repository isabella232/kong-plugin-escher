local EscherWrapper =  require "kong.plugins.escher.escher_wrapper"
local Escher = require "escher"
local KeyDb = require "kong.plugins.escher.key_db"

describe("escher wrapper", function()

    local ems_auth_header
    local escher_wrapper
    local current_date
    local test_escher_key

    before_each(function()
        KeyDb.find_secret_by_key = function(self, key_name)
            if key_name == 'test_key' then
                return "test_secret"
            end
        end

        test_escher_key = {
            key = 'test_key',
            secret = 'test_secret',
            consumer_id = '0001-1234'
        }

        KeyDb.find_by_key = function(self, key_name)
            if key_name == 'test_key' then
                return test_escher_key
            end
        end

        local key_db = KeyDb()

        escher_wrapper = EscherWrapper(key_db)

        current_date = os.date("!%Y%m%dT%H%M%SZ")

        local config = {
            algoPrefix      = 'EMS',
            vendorKey       = 'EMS',
            credentialScope = 'eu/suite/ems_request',
            authHeaderName  = 'X-Ems-Auth',
            dateHeaderName  = 'X-Ems-Date',
            accessKeyId     = 'test_key',
            apiSecret       = 'test_secret',
            date            = current_date,
        }

        local request_headers = {
            { "X-Ems-Date", current_date },
            { "Host", "" }
        }

        local request = {
            ["method"] = "GET",
            ["headers"] = request_headers,
            ["body"] = '',
            ["url"] = "request_uri"
        }

        local escher = Escher:new(config)

        ems_auth_header = escher:generateHeader(request, {})
    end)

    describe("#authenticate", function()

        it("returns nil when escher authentication was not successful", function()
            local request = {
                ["method"] = "GET",
                ["headers"] = {},
                ["body"] = '',
                ["url"] = "request_uri"
            }

            assert.are.equal(nil, escher_wrapper:authenticate(request))
        end)

        it("should call escher lib authenticate method", function()
            local request = {
                ["method"] = "GET",
                ["headers"] = {},
                ["body"] = '',
                ["url"] = "request_uri"
            }

            spy.on(Escher, "authenticate")
            escher_wrapper:authenticate(request)

            assert.spy(Escher.authenticate).was.called()
        end)

        it("should call escher lib authenticate method with proper headers", function()
            local headers = {
                ["x-ems-auth"] = ems_auth_header,
                ["x-ems-date"] = current_date,
                ["host"] = '',
            }

            local expected_request_headers = {
                { "x-ems-auth", ems_auth_header },
                { "x-ems-date", current_date },
                { "host", "" },
            }

            local expected_request = {
                ["method"] = "GET",
                ["headers"] = expected_request_headers,
                ["body"] = '',
                ["url"] = "request_uri"
            }

            local request = {
                ["method"] = "GET",
                ["headers"] = headers,
                ["body"] = '',
                ["url"] = "request_uri"
            }

            local mandatory_headers_to_sign = {}

            spy.on(Escher, "authenticate")
            escher_wrapper:authenticate(request, mandatory_headers_to_sign)

            assert.spy(Escher.authenticate).was.called_with(match._, expected_request, match.is_function(), mandatory_headers_to_sign)
        end)

        it("should return with api_key when escher authentication was successful", function()
            local headers = {
                ["X-Ems-Date"] = current_date,
                ["X-Ems-Auth"] = ems_auth_header,
                ["Host"] = '',
            }

            local request = {
                ["method"] = "GET",
                ["headers"] = headers,
                ["body"] = '',
                ["url"] = "request_uri"
            }

            local api_key, err = escher_wrapper:authenticate(request)
            assert.are.equal(test_escher_key, api_key)
        end)

    end)

end)