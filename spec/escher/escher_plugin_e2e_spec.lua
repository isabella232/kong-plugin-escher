local helpers = require "spec.helpers"
local cjson = require "cjson"
local Escher = require "escher"

describe("Plugin: escher (access)", function()
    local dev_env = {
        custom_plugins = 'escher'
    }

    local plugin
    local api_id

    setup(function()
        local api1 = assert(helpers.dao.apis:insert { name = "test-api", hosts = { "test1.com" }, upstream_url = "http://mockbin.com" })
        api_id = api1.id

        plugin = assert(helpers.dao.plugins:insert {
            api_id = api1.id,
            name = "escher",
            config = {}
        })

        consumer = assert(helpers.dao.consumers:insert {
            username = "test"
        })


        assert(helpers.start_kong(dev_env))
    end)

    teardown(function()
        helpers.stop_kong(nil)
    end)

    describe("Admin API", function()
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
            path = "/consumers/test/escher_key/",
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
          assert.is_equal('test_secret', json.secret)
        end)

        it("should be able to retrieve an escher key", function()
            local create_call = assert(helpers.admin_client():send {
              method = "POST",
              path = "/consumers/test/escher_key/",
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
                path = "/consumers/test/escher_key/another_test_key"
              })

            local body = assert.res_status(200, retrieve_call)
            local json = cjson.decode(body)
            assert.is_equal('another_test_key', json.key)
            assert.is_equal(nil, json.secret)
        end)

        it("should be able to delete an escher key", function()
            local create_call = assert(helpers.admin_client():send {
              method = "POST",
              path = "/consumers/test/escher_key/",
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
                path = "/consumers/test/escher_key/yet_another_test_key"
              })

            local body = assert.res_status(204, delete_call)
          end)
    end)

    describe("Authentication", function()
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
                path = "/consumers/test/escher_key/",
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
