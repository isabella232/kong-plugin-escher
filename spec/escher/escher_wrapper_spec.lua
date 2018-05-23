local EscherWrapper =  require "kong.plugins.escher.escher_wrapper"
local Escher = require "escher"
local KeyDb = require "kong.plugins.escher.key_db"

describe("escher wrapper", function()

    local ngx_req_headers = {}
    local set_headers = function(headers)
        ngx_req_headers = headers
    end
    local ngx_mock = {
        req = {
            get_method = function()
               return "GET"
            end,
            get_body_data = function()
                return ''
            end,
            get_headers = function()
                return ngx_req_headers
            end,
            read_body = function() end
        },
        var = {
            request_uri = "request_uri"
        },

    }

    KeyDb.find_secret_by_key = function(self, key_name)
        if key_name == 'test_key' then
            return "test_secret"
        end
    end

    local test_escher_key = {
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
    local escher_wrapper = EscherWrapper(ngx_mock, key_db)

    local current_date = os.date("!%Y%m%dT%H%M%SZ")
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

    local ems_auth_header = escher:generateHeader(request, {})

    describe("#authenticate", function()

        it("returns nil when escher authentication was not successful", function()
            set_headers({})
            assert.are.equal(nil, escher_wrapper:authenticate())
        end)

        it("should call escher lib authenticate method", function()
            set_headers({})
            spy.on(Escher, "authenticate")
            escher_wrapper:authenticate()

            assert.spy(Escher.authenticate).was.called()
        end)

        it("should call escher lib authenticate method with proper headers", function()

            local headers = {
                ["X-Ems-Date"] = current_date,
                ["X-Ems-Auth"] = ems_auth_header,
                ["Host"] = '',
            }

            local expected_request_headers = {
                { "X-Ems-Date", current_date },
                { "Host", "" },
                { "X-Ems-Auth", ems_auth_header },
            }

            local expected_request = {
                ["method"] = "GET",
                ["headers"] = expected_request_headers ,
                ["body"] = '',
                ["url"] = "request_uri"
            }

            local mandatory_headers_to_sign = {}

            set_headers(headers)
            spy.on(Escher, "authenticate")
            escher_wrapper:authenticate()

            assert.spy(Escher.authenticate).was.called_with(match._, match.is_same(expected_request), match.is_function(), mandatory_headers_to_sign)
        end)

        it("should call ngx.req.read_body() when authenticate", function()
            local escher_auth_func = Escher.authenticate
            Escher.authenticate = function() end

            spy.on(ngx_mock.req, "read_body")
            escher_wrapper:authenticate()

            assert.spy(ngx_mock.req.read_body).was.called()

            Escher.authenticate = escher_auth_func
        end)

        it("should return with api_key when escher authentication was successful", function()
            local headers = {
                ["X-Ems-Date"] = current_date,
                ["X-Ems-Auth"] = ems_auth_header,
                ["Host"] = '',
            }

            set_headers(headers)
            local api_key, err = escher_wrapper:authenticate()
            assert.are.equal(test_escher_key, api_key)
        end)

    end)

end)