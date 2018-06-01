local helpers = require "spec.helpers"
local cjson = require "cjson"
local Escher = require "escher"
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

    return service, route, plugin, consumer
end

describe("Plugin: escher (access)", function()

    setup(function()
        helpers.start_kong({ custom_plugins = 'escher' })
    end)

    teardown(function()
        helpers.stop_kong(nil)
    end)

    describe("Admin API", function()

        local service, route, plugin, consumer

        before_each(function()
            service, route, plugin, consumer = setup_test_env()
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

            local body = assert.res_status(204, delete_call)
          end)
    end)

    describe("Setup plugin with wrong config", function()

        local service, route, plugin, consumer

        before_each(function()
            helpers.dao:truncate_tables()
            service = get_response_body(TestHelper.setup_service())
            route = get_response_body(TestHelper.setup_route_for_service(service.id))
        end)

        it("should respons 400 when encryption file does not exists", function()
            local res = TestHelper.setup_plugin_for_service(service.id, 'escher', { encryption_key_path = "/kong.txt" })

            assert.res_status(400, res)
        end)
    end)

    describe("Setup plugin with wrong config", function()

        before_each(function()
            helpers.dao:truncate_tables()
        end)

        it("should respons 400 when encryption file does not exists", function()
            local first_service = get_response_body(TestHelper.setup_service("first"))
            local second_service = get_response_body(TestHelper.setup_service("second"))

            get_response_body(TestHelper.setup_route_for_service(first_service.id))
            get_response_body(TestHelper.setup_route_for_service(second_service.id))

            local f = io.open("/tmp/other_secret.txt", "w")
            f:close()

            local first_res = TestHelper.setup_plugin_for_service(first_service.id, 'escher', { encryption_key_path = "/secret.txt" })
            local second_res = TestHelper.setup_plugin_for_service(second_service.id, 'escher', { encryption_key_path = "/tmp/other_secret.txt" })

            assert.res_status(400, second_res)
        end)
    end)

    describe("Authentication", function()

        local service, route, plugin, consumer

        before_each(function()
            service, route, plugin, consumer = setup_test_env()
        end)

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

        local config_wrong_api_key = {
            algoPrefix      = 'EMS',
            vendorKey       = 'EMS',
            credentialScope = 'eu/suite/ems_request',
            authHeaderName  = 'X-Ems-Auth',
            dateHeaderName  = 'X-Ems-Date',
            accessKeyId     = 'wrong_key',
            apiSecret       = 'test_secret',
            date            = current_date,
        }

        local request_headers = {
            { "X-Ems-Date", current_date },
            { "Host", "test1.com" }
        }

        local request = {
            ["method"] = "GET",
            ["headers"] = request_headers,
            --["body"] = '',
            ["url"] = "/request"
        }

        local escher = Escher:new(config)
        local escher_wrong_api_key = Escher:new(config_wrong_api_key)

        local ems_auth_header = escher:generateHeader(request, {})
        local ems_auth_header_wrong_api_key = escher_wrong_api_key:generateHeader(request, {})


        it("responds with status 401 if request not has X-EMS-AUTH header and anonymous not allowed", function()
            local res = assert(helpers.proxy_client():send {
                method = "GET",
                path = "/request",
                headers = {
                    ["Host"] = "test1.com"
                }
            })

            local body = assert.res_status(401, res)
            assert.is_equal('{"message":"X-EMS-AUTH header not found!"}', body)
        end)

        it("responds with status 401 when X-EMS-AUTH header is invalid", function()
            local res = assert(helpers.proxy_client():send {
                method = "GET",
                path = "/request",
                headers = {
                    ["X-EMS-DATE"] = current_date,
                    ["Host"] = "test1.com",
                    ["X-EMS-AUTH"] = 'invalid header'
                }
            })

            assert.res_status(401, res)
        end)

        it("responds with status 200 when X-EMS-AUTH header is valid", function()
            assert(helpers.admin_client():send {
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

            local res = assert(helpers.proxy_client():send {
                method = "GET",
                path = "/request",
                headers = {
                    ["X-EMS-DATE"] = current_date,
                    ["Host"] = "test1.com",
                    ["X-EMS-AUTH"] = ems_auth_header
                }
            })

            assert.res_status(200, res)
        end)

        it("responds with status 401 when api key was not found", function()
            local res = assert(helpers.proxy_client():send {
                method = "GET",
                path = "/request",
                headers = {
                    ["X-EMS-DATE"] = current_date,
                    ["Host"] = "test1.com",
                    ["X-EMS-AUTH"] = ems_auth_header_wrong_api_key
                }
            })

            assert.res_status(401, res)
        end)

    end)

end)
