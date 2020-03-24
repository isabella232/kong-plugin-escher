local constants = require "kong.constants"
local plugin_handler = require "kong.plugins.escher.handler"
local ConsumerDb = require "kong.plugins.escher.consumer_db"
local EscherWrapper = require "kong.plugins.escher.escher_wrapper"

describe("escher plugin", function()
    local old_ngx = _G.ngx
    local old_kong = _G.kong
    local mock_config= {
        anonymous = "anonym123"
    }
    local handler

    local anonymous_consumer = {
        id = "anonym123",
        custom_id = "",
        username = "anonymous"
    }

    local test_consumer = {
        id = "test123",
        custom_id = "",
        username = "test"
    }

    local test_escher_key = {
        key = "test_key",
        secret = "test_secret",
        consumer_id = "0001-1234"
    }

    ConsumerDb.find_by_id = function(consumer_id)
        if consumer_id == "anonym123" then
            return anonymous_consumer
        else
            return test_consumer
        end
    end

    before_each(function()
        local stubbed_ngx = {
            ctx = {},
            log = function() end,
            var = {}
        }

        local kong_service_request_headers = {}

        local stubbed_kong = {
            service = {
                request = {
                    set_header = function(header_name, header_value)
                        kong_service_request_headers[header_name] = header_value
                    end,
                    clear_header =  function() end
                }
            },
            request = {
                get_path_with_query = function()
                    return "request_uri"
                end,
                get_method = function()
                    return "GET"
                end,
                get_headers = function()
                    return kong_service_request_headers
                end,
                get_body = function() end
            }
        }

        EscherWrapper.authenticate = function()
            return test_escher_key
        end

        _G.ngx = stubbed_ngx
        _G.kong = stubbed_kong

        handler = plugin_handler()
    end)

    after_each(function()
        _G.ngx = old_ngx
        _G.kong = old_kong
    end)

    describe("#access", function()

        it("set anonymous header to true when request not has x-ems-auth header", function()
            EscherWrapper.authenticate = function()
                return nil
            end

            handler:access(mock_config)

            assert.are.equal(true, kong.request.get_headers()[constants.HEADERS.ANONYMOUS])
        end)

        it("set anonymous header to nil when x-ems-auth header exists", function()
            kong.service.request.set_header("X-EMS-AUTH", "some escher header string")

            handler:access(mock_config)

            assert.is_nil(kong.request.get_headers()[constants.HEADERS.ANONYMOUS])
        end)

        it("set anonymous consumer on ngx context and not set credentials when X-EMS-AUTH header was not found", function()
            EscherWrapper.authenticate = function()
                return nil
            end

            handler:access(mock_config)

            assert.are.equal(anonymous_consumer, ngx.ctx.authenticated_consumer)
            assert.is_nil(ngx.ctx.authenticated_credential)
        end)

        it("set consumer specific request headers when authentication was successful", function()
            kong.service.request.set_header("X-EMS-AUTH", "some escher header string")

            handler:access(mock_config)

            assert.are.equal("test123", kong.request.get_headers()[constants.HEADERS.CONSUMER_ID])
            assert.are.equal("", kong.request.get_headers()[constants.HEADERS.CONSUMER_CUSTOM_ID])
            assert.are.equal("test", kong.request.get_headers()[constants.HEADERS.CONSUMER_USERNAME])
            assert.are.equal("test_key", kong.request.get_headers()[constants.HEADERS.CREDENTIAL_USERNAME])
            assert.is_nil(kong.request.get_headers()[constants.HEADERS.ANONYMOUS])
        end)

        it("set consumer specific ngx context variables when authentication was successful", function()
            kong.service.request.set_header("X-EMS-AUTH", "some escher header string")

            handler:access(mock_config)

            assert.are.equal(test_consumer, ngx.ctx.authenticated_consumer)
            assert.are.equal(test_escher_key, ngx.ctx.authenticated_credential)
        end)

    end)

end)