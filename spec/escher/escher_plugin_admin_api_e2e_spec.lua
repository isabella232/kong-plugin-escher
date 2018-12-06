local helpers = require "spec.helpers"
local cjson = require "cjson"
local TestHelper = require "spec.test_helper"

local function get_response_body(response)
    local body = assert.res_status(201, response)
    return cjson.decode(body)
end

local function setup_test_env()
    helpers.dao:truncate_tables()

    local service = get_response_body(TestHelper.setup_service())
    local route = get_response_body(TestHelper.setup_route_for_service(service.id))
    local plugin = get_response_body(TestHelper.setup_plugin_for_service(service.id, 'escher', { encryption_key_path = "/secret.txt" }))
    local consumer = get_response_body(TestHelper.setup_consumer('test'))

    return plugin, consumer
end

describe("Plugin: escher #e2e Admin API", function()
    setup(function()
        helpers.start_kong({ custom_plugins = 'escher' })
    end)

    teardown(function()
        helpers.stop_kong(nil)
    end)

    local plugin, consumer

    before_each(function()
        plugin, consumer = setup_test_env()
    end)

    it("registered the plugin globally", function()
        local res = assert(helpers.admin_client():send {
            method = "GET",
            path = "/plugins/" .. plugin.id,
        })

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.is_table(json)
        assert.is_not.falsy(json.enabled)
    end)

    it("registered the plugin for the api", function()
        local res = assert(helpers.admin_client():send {
            method = "GET",
            path = "/plugins/" ..plugin.id,
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_equal(api_id, json.api_id)
    end)

    it("should create a new escher key for the given consumer", function()
      local res = assert(helpers.admin_client():send {
            method = "POST",
            path = "/consumers/" .. consumer.id .. "/escher_key/",
            body = {
                key = 'test_key',
                secret = 'test_secret'
            },
            headers = {
                ["Content-Type"] = "application/json"
            }
      })

      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      assert.is_equal('test_key', json.key)
    end)

    it("should create a new escher key with encrypted secret using encryption key from file", function()
        local ecrypto = TestHelper.get_easy_crypto()

        local secret = 'test_secret'
        local res = assert(helpers.admin_client():send {
            method = "POST",
            path = "/consumers/" .. consumer.id .. "/escher_key/",
            body = {
                key = 'test_key_v2',
                secret = secret
            },
            headers = {
                ["Content-Type"] = "application/json"
            }
        })

        local body = assert.res_status(201, res)
        local json = cjson.decode(body)

        assert.is_equal('test_key_v2', json.key)
        assert.are_not.equals(secret, json.secret)

        local encryption_key = TestHelper.load_encryption_key_from_file(plugin.config.encryption_key_path)

        assert.is_equal(secret, ecrypto:decrypt(encryption_key, json.secret))
    end)

    it("should be able to retrieve an escher key", function()
        local create_call = assert(helpers.admin_client():send {
            method = "POST",
            path = "/consumers/" .. consumer.id .. "/escher_key/",
            body = {
                key = 'another_test_key',
                secret = 'test_secret'
            },
            headers = {
                ["Content-Type"] = "application/json"
            }
        })

        assert.res_status(201, create_call)

        local retrieve_call = assert(helpers.admin_client():send {
            method = "GET",
            path = "/consumers/" .. consumer.id .. "/escher_key/another_test_key"
        })

        local body = assert.res_status(200, retrieve_call)
        local json = cjson.decode(body)
        assert.is_equal('another_test_key', json.key)
        assert.is_equal(nil, json.secret)
    end)

    it("should be able to delete an escher key", function()
        local create_call = assert(helpers.admin_client():send {
            method = "POST",
            path = "/consumers/" .. consumer.id .. "/escher_key/",
            body = {
                key = 'yet_another_test_key',
                secret = 'test_secret'
            },
            headers = {
                ["Content-Type"] = "application/json"
            }
        })

        assert.res_status(201, create_call)

        local delete_call = assert(helpers.admin_client():send {
            method = "DELETE",
            path = "/consumers/" .. consumer.id .. "/escher_key/yet_another_test_key"
        })

        assert.res_status(204, delete_call)
    end)

    context("when escher key does not exist", function()
        local test_cases = {"GET", "DELETE"}

        for _, method in ipairs(test_cases) do
            it("should respond with 404 on " .. method .. " request" , function()
                local retrieve_call = assert(helpers.admin_client():send {
                    method = method,
                    path = "/consumers/" .. consumer.id .. "/escher_key/another_test_key"
                })

                local body = assert.res_status(404, retrieve_call)
                local json = cjson.decode(body)

                assert.are.same({ message = "Not found" }, json)
            end)
        end
    end)
end)
