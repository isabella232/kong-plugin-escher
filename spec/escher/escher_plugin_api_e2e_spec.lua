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

describe("Escher #plugin #api #e2e", function()

    local kong_sdk, send_admin_request
    local consumer

    setup(function()
        kong_helpers.start_kong({ plugins = "escher" })

        kong_sdk = test_helpers.create_kong_client()
        send_admin_request = test_helpers.create_request_sender(kong_helpers.admin_client())
    end)

    teardown(function()
        kong_helpers.stop_kong()
    end)

    before_each(function()
        kong_helpers.db:truncate()

        consumer = kong_sdk.consumers:create({
            username = "TestUser"
        })
    end)

    context("POST collection", function()
        it("should respond with error when key field is missing", function ()
            local response = send_admin_request({
                method = "POST",
                path = "/consumers/" .. consumer.id .. "/escher_key"
            })

            assert.are.equals(400, response.status)
            assert.are.equals("required field missing", response.body.fields.key)
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

            assert.are.equals(404, response.status)
            assert.are.equals("Not found", response.body.message)
        end)

        it("should store the escher key with encrypted secret using encryption key from file", function()
            local service = kong_sdk.services:create({
                name = "testservice",
                url = "http://mockbin:8080/request"
            })

            local plugin = kong_sdk.plugins:create({
                service = { id = service.id },
                name = "escher",
                config = { encryption_key_path = "/secret.txt" }
            })

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

            assert.are.equals(201, response.status)
            assert.are_not.equals("irrelevant", response.body.secret)

            local encryption_key = load_encryption_key_from_file(plugin.config.encryption_key_path)

            assert.are.equals("irrelevant", ecrypto:decrypt(encryption_key, response.body.secret))
        end)

        context("when no plugin is added", function()
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

                assert.are.equals(412, response.status)
                assert.are.equals("Encryption key was not defined", response.body.message)
            end)
        end)
    end)

    context("DELETE entity", function()
        it("should respond with error when the consumer does not exist", function ()
            local response = send_admin_request({
                method = "DELETE",
                path = "/consumers/" .. uuid() .. "/escher_key/" .. uuid()
            })

            assert.are.equals(404, response.status)
            assert.are.equals("Not found", response.body.message)
        end)

        it("should respond with error when the escher_key does not exist", function ()
            local response = send_admin_request({
                method = "DELETE",
                path = "/consumers/" .. consumer.id .. "/escher_key/" .. uuid()
            })

            assert.are.equals(404, response.status)
            assert.are.equals("Not found", response.body.message)
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

            assert.are.equals(201, response_create.status)
            local escher_key = response_create.body

            local response = send_admin_request({
                method = "DELETE",
                path = "/consumers/" .. consumer.id .. "/escher_key/" .. escher_key.id
            })

            assert.are.equals(204, response.status)
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

            assert.are.equals(201, response_create.status)
            local escher_key = response_create.body

            local response = send_admin_request({
                method = "DELETE",
                path = "/consumers/" .. consumer.id .. "/escher_key/" .. escher_key.key
            })

            assert.are.equals(204, response.status)
        end)
    end)

    context("GET entity", function()
        it("should respond with error when the consumer does not exist", function ()
            local response = send_admin_request({
                method = "GET",
                path = "/consumers/" .. uuid() .. "/escher_key/" .. uuid()
            })

            assert.are.equals(404, response.status)
            assert.are.equals("Not found", response.body.message)
        end)

        it("should respond with error when the escher_key does not exist", function ()
            local response = send_admin_request({
                method = "GET",
                path = "/consumers/" .. consumer.id .. "/escher_key/" .. uuid()
            })

            assert.are.equals(404, response.status)
            assert.are.equals("Not found", response.body.message)
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

            assert.are.equals(201, response_create.status)
            local escher_key_created = response_create.body

            local response = send_admin_request({
                method = "GET",
                path = "/consumers/" .. consumer.id .. "/escher_key/" .. escher_key_created.id
            })

            assert.are.equals(200, response.status)
            local escher_key = response.body

            assert.are.equals(escher_key_created.key, escher_key.key)
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

            assert.are.equals(201, response_create.status)
            local escher_key_created = response_create.body

            local response = send_admin_request({
                method = "GET",
                path = "/consumers/" .. consumer.id .. "/escher_key/" .. escher_key_created.key
            })

            assert.are.equals(200, response.status)
        end)
    end)
end)
