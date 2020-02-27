local kong_helpers = require "spec.helpers"
local test_helpers = require "kong_client.spec.test_helpers"
local uuid = require "kong.tools.utils".uuid

local function get_easy_crypto()
    local EasyCrypto = require("resty.easy-crypto")
    local ecrypto = EasyCrypto:new({
        saltSize = 12,
        ivSize = 16,
        iterationCount = 10000
    })
    return ecrypto
end

local function load_encryption_key_from_file(file_path)
    local file = assert(io.open(file_path, "r"))
    local encryption_key = file:read("*all")
    file:close()
    return encryption_key
end

describe("Escher plugin Admin API #e2e #api", function()

    local kong_sdk, send_admin_request

    setup(function()
        kong_helpers.start_kong({ plugins = "escher" })

        kong_sdk = test_helpers.create_kong_client()
        send_admin_request = test_helpers.create_request_sender(kong_helpers.admin_client())
    end)

    teardown(function()
        kong_helpers.stop_kong()
    end)

    context("when plugin exists", function()

        local service, plugin, consumer

        before_each(function()
            kong_helpers.db:truncate()

            service = kong_sdk.services:create({
                name = "testservice",
                url = "http://mockbin:8080/request"
            })

            kong_sdk.routes:create_for_service(service.id, "/")

            plugin = kong_sdk.plugins:create({
                service = { id = service.id },
                name = "escher",
                config = { encryption_key_path = "/secret.txt" }
            })

            consumer = kong_sdk.consumers:create({
                username = "test",
            })
        end)

        context("POST collection", function()
            it("should respond with error when key field is missing", function ()
                local response = send_admin_request({
                    method = "POST",
                    path = "/consumers/" .. consumer.id .. "/escher_key"
                })

                assert.are.equal(400, response.status)
                assert.is_equal("required field missing", response.body.fields.key)
            end)

            it("should respond with error when the consumer does not exist", function ()
                local response = send_admin_request({
                    method = "POST",
                    path = "/consumers/1234/escher_key",
                    body = {
                        key = "irrelevant"
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                assert.are.equal(404, response.status)
                assert.is_equal("Not found", response.body.message)
            end)

            it("should store the escher key with encrypted secret using encryption key from file", function()
                local ecrypto = get_easy_crypto()
                local response = send_admin_request({
                    method = "POST",
                    path = "/consumers/" .. consumer.id .. "/escher_key",
                    body = {
                        key = "irrelevant",
                        secret = "irrelevant"
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                assert.are.equal(201, response.status)
                assert.are_not.equal("irrelevant", response.body.secret)

                local encryption_key = load_encryption_key_from_file(plugin.config.encryption_key_path)

                assert.are.equal("irrelevant", ecrypto:decrypt(encryption_key, response.body.secret))
            end)
        end)

        context("DELETE entity", function()
            it("should respond with error when the consumer does not exist", function ()
                local response = send_admin_request({
                    method = "DELETE",
                    path = "/consumers/" .. uuid() .. "/escher_key/" .. uuid()
                })

                assert.are.equal(404, response.status)
                assert.is_equal("Not found", response.body.message)
            end)

            it("should respond with error when the escher_key does not exist", function ()
                local response = send_admin_request({
                    method = "DELETE",
                    path = "/consumers/" .. consumer.id .. "/escher_key/" .. uuid()
                })

                assert.are.equal(404, response.status)
                assert.is_equal("Not found", response.body.message)
            end)

            it("should remove the escher_key", function()
                local response_create = send_admin_request({
                    method = "POST",
                    path = "/consumers/" .. consumer.id .. "/escher_key",
                    body = {
                        key = 'irrelevant'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                assert.are.equal(201, response_create.status)
                local escher_key = response_create.body

                local response = send_admin_request({
                    method = "DELETE",
                    path = "/consumers/" .. consumer.id .. "/escher_key/" .. escher_key.id
                })

                assert.are.equal(204, response.status)
            end)

            it("should lookup the escher_key by key name and remove it", function()
                local response_create = send_admin_request({
                    method = "POST",
                    path = "/consumers/" .. consumer.id .. "/escher_key",
                    body = {
                        key = 'irrelevant'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                assert.are.equal(201, response_create.status)
                local escher_key = response_create.body

                local response = send_admin_request({
                    method = "DELETE",
                    path = "/consumers/" .. consumer.id .. "/escher_key/" .. escher_key.key
                })

                assert.are.equal(204, response.status)
            end)
        end)

        context("GET entity", function()
            it("should respond with error when the consumer does not exist", function ()
                local response = send_admin_request({
                    method = "GET",
                    path = "/consumers/" .. uuid() .. "/escher_key/" .. uuid()
                })

                assert.are.equal(404, response.status)
                assert.is_equal("Not found", response.body.message)
            end)

            it("should respond with error when the escher_key does not exist", function ()
                local response = send_admin_request({
                    method = "GET",
                    path = "/consumers/" .. consumer.id .. "/escher_key/" .. uuid()
                })

                assert.are.equal(404, response.status)
                assert.is_equal("Not found", response.body.message)
            end)

            it("should return with the escher_key but should not return the secret", function ()
                local response_create = send_admin_request({
                    method = "POST",
                    path = "/consumers/" .. consumer.id .. "/escher_key",
                    body = {
                        key = 'irrelevant'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                assert.are.equal(201, response_create.status)
                local escher_key_created = response_create.body

                local response = send_admin_request({
                    method = "GET",
                    path = "/consumers/" .. consumer.id .. "/escher_key/" .. escher_key_created.id
                })

                assert.are.equal(200, response.status)
                local escher_key = response.body

                assert.is_equal(escher_key_created.key, escher_key.key)
                assert.is_nil(escher_key.secret)
            end)

            it("should lookup the escher_key by key name and return it", function()
                local response_create = send_admin_request({
                    method = "POST",
                    path = "/consumers/" .. consumer.id .. "/escher_key",
                    body = {
                        key = 'irrelevant'
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                assert.are.equal(201, response_create.status)
                local escher_key_created = response_create.body

                local response = send_admin_request({
                    method = "GET",
                    path = "/consumers/" .. consumer.id .. "/escher_key/" .. escher_key_created.key
                })

                assert.are.equal(200, response.status)
            end)
        end)

        -- it("should be able to retrieve an escher key", function()
        --     local create_escher_key_response = send_admin_request({
        --         method = "POST",
        --         path = "/consumers/" .. consumer.id .. "/escher_key/",
        --         body = {
        --             key = "another_test_key",
        --             secret = "test_secret"
        --         },
        --         headers = {
        --             ["Content-Type"] = "application/json"
        --         }
        --     })

        --     assert.are.equal(201, create_escher_key_response.status)

        --     local retrieve_escher_key_response = send_admin_request({
        --         method = "GET",
        --         path = "/consumers/" .. consumer.id .. "/escher_key/another_test_key"
        --     })

        --     assert.are.equal(200, retrieve_escher_key_response.status)
        --     assert.are.equal("another_test_key", retrieve_escher_key_response.body.key)
        --     assert.is_nil(retrieve_escher_key_response.body.secret)
        -- end)

        -- context("when escher key does not exist", function()
        --     local test_cases = {"GET", "DELETE"}

        --     for _, method in ipairs(test_cases) do
        --         it("should respond with 404 on " .. method .. " request", function()
        --             local retrieve_escher_key_response = send_admin_request({
        --                 method = method,
        --                 path = "/consumers/" .. consumer.id .. "/escher_key/irrelevant"
        --             })

        --             assert.are.equal(404, retrieve_escher_key_response.status)
        --             assert.are.same({ message = "Not found" }, retrieve_escher_key_response.body)
        --         end)
        --     end
        -- end)
    end)

    context("when no plugin is added", function()

        local consumer

        before_each(function()
            kong_helpers.db:truncate()

            local service = kong_sdk.services:create({
                name = "testservice",
                url = "http://mockbin:8080/request"
            })

            kong_sdk.routes:create_for_service(service.id, "/")

            consumer = kong_sdk.consumers:create({
                username = "test",
            })
        end)

        context("Admin API POST collection", function()
            it("should return 412 status", function()
                local response = send_admin_request({
                    method = "POST",
                    path = "/consumers/" .. consumer.id .. "/escher_key",
                    body = {
                        key = "irrelevant",
                        secret = "irrelevant"
                    },
                    headers = {
                        ["Content-Type"] = "application/json"
                    }
                })

                assert.are.equal(412, response.status)
                assert.are.equal("Encryption key was not defined", response.body.message)
            end)
        end)

    end)

end)
