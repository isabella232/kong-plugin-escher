local constants = require "kong.constants"
local plugin_handler = require "kong.plugins.escher.handler"
local ConsumerDb = require "kong.plugins.escher.consumer_db"
local KeyDb = require "kong.plugins.escher.key_db"
local EscherWrapper = require "kong.plugins.escher.escher_wrapper"

describe("escher plugin", function()
    local old_ngx = _G.ngx
    local mock_config= {
        anonymous = 'anonym123'
    }
    local handler

    local anonymous_consumer = {
        id = 'anonym123',
        custom_id = '',
        username = 'anonymous'
    }

    local test_consumer = {
        id = 'test123',
        custom_id = '',
        username = 'test'
    }

    local test_escher_key = {
        key = 'test_key',
        secret = 'test_secret',
        consumer_id = '0001-1234'
    }

    ConsumerDb.find_by_id = function(consumer_id, anonymous)
        if consumer_id == 'anonym123' then
            return anonymous_consumer
        else
            return test_consumer
        end
    end

    EscherWrapper.authenticate = function()
        return test_escher_key
    end

    before_each(function()
        local ngx_req_headers = {}
        local stubbed_ngx = {
            req = {
                get_headers = function()
                    return ngx_req_headers
                end,
                set_header = function(header_name, header_value)
                    ngx_req_headers[header_name] = header_value
                end,
                read_body = function() end,
                get_method = function() end,
                get_body_data = function() end,
            },
            ctx = {},
            header = {},
            log = function(...) end,
            say = function(...) end,
            exit = function(...) end,
            var = {
                request_id = 123,
                request_uri = "request_uri",
            }
        }

        _G.ngx = stubbed_ngx
        stub(stubbed_ngx, "say")
        stub(stubbed_ngx, "exit")
        stub(stubbed_ngx, "log")

        handler = plugin_handler()
    end)

    after_each(function()
        _G.ngx = old_ngx
    end)

    describe("#access", function()

        it("set anonymous header to true when request not has x-ems-auth header", function()
            handler:access(mock_config)
            assert.are.equal(true, ngx.req.get_headers()[constants.HEADERS.ANONYMOUS])
        end)

        it("set anonymous header to nil when x-ems-auth header exists", function()
            ngx.req.set_header("X-EMS-AUTH", "some escher header string")
            handler:access(mock_config)
            assert.are.equal(nil, ngx.req.get_headers()[constants.HEADERS.ANONYMOUS])
        end)

        it("set anonymous consumer on ngx context and not set credentials when X-EMS-AUTH header was not found", function()
            handler:access(mock_config)
            assert.are.equal(anonymous_consumer, ngx.ctx.authenticated_consumer)
            assert.are.equal(nil, ngx.ctx.authenticated_credential)
        end)

        it("set consumer specific request headers when authentication was successful", function()
            ngx.req.set_header("X-EMS-AUTH", "some escher header string")
            handler:access(mock_config)
            assert.are.equal('test123', ngx.req.get_headers()[constants.HEADERS.CONSUMER_ID])
            assert.are.equal('', ngx.req.get_headers()[constants.HEADERS.CONSUMER_CUSTOM_ID])
            assert.are.equal('test', ngx.req.get_headers()[constants.HEADERS.CONSUMER_USERNAME])
            assert.are.equal('test_key', ngx.req.get_headers()[constants.HEADERS.CREDENTIAL_USERNAME])
        end)

        it("set consumer specific ngx context variables when authentication was successful", function()
            ngx.req.set_header("X-EMS-AUTH", "some escher header string")
            handler:access(mock_config)
            assert.are.equal(test_consumer, ngx.ctx.authenticated_consumer)
            assert.are.equal(test_escher_key, ngx.ctx.authenticated_credential)
        end)

    end)

end)