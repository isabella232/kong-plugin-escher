local helpers = require "spec.helpers"
local cjson = require "cjson"
local KongSdk = require "spec.kong_sdk"

local function create_request_sender(http_client)
    return function(request)
        local response = assert(http_client:send(request))

        local raw_body = assert(response:read_body())
        local success, parsed_body = pcall(cjson.decode, raw_body)

        return {
            body = success and parsed_body or raw_body,
            headers = response.headers,
            status = response.status
        }
    end
end

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

describe("Plugin: escher #e2e Admin API", function()

    local kong_sdk, send_admin_request

    setup(function()
        helpers.start_kong({ plugins = "escher" })

        kong_sdk = KongSdk.from_admin_client()

        send_admin_request = create_request_sender(helpers.admin_client())
    end)

    teardown(function()
        helpers.stop_kong(nil)
    end)

    context("when plugin exists", function()

        local service, plugin, consumer

        before_each(function()
            helpers.db:truncate()

            service = kong_sdk.services:create({
                name = "testservice",
                url = "http://mockbin:8080/request"
            })

            kong_sdk.routes:create_for_service(service.id, "/")

            plugin = kong_sdk.plugins:create({
                service_id = service.id,
                name = "escher",
                config = { encryption_key_path = "/secret.txt" }
            })

            consumer = kong_sdk.consumers:create({
                username = 'test',
            })
        end)

        it("registered the plugin globally", function()
            local response = send_admin_request({
                method = "GET",
                path = "/plugins/" .. plugin.id
            })

            assert.are.equal(200, response.status)
            assert.is_table(response.body)
            assert.is_not.falsy(response.body.enabled)
        end)

        it("registered the plugin for the service", function()
            local response = send_admin_request({
                method = "GET",
                path = "/plugins/" .. plugin.id
            })

            assert.are.equal(200, response.status)
            assert.are.equal(service.id, response.body.service_id)
        end)

        it("should create a new escher key for the given consumer", function()
            local response = send_admin_request({
                method = "POST",
                path = "/consumers/" .. consumer.id .. "/escher_key/",
                body = {
                    key = "test_key",
                    secret = "test_secret"
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            assert.are.equal(201, response.status)
            assert.are.equal("test_key", response.body.key)
        end)

        it("should create a new escher key with encrypted secret using encryption key from file", function()
            local ecrypto = get_easy_crypto()

            local secret = "test_secret"

            local response = send_admin_request({
                method = "POST",
                path = "/consumers/" .. consumer.id .. "/escher_key/",
                body = {
                    key = "test_key_v2",
                    secret = secret
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            assert.are.equal(201, response.status)
            assert.are.equal("test_key_v2", response.body.key)
            assert.are_not.equal(secret, response.body.secret)

            local encryption_key = load_encryption_key_from_file(plugin.config.encryption_key_path)

            assert.are.equal(secret, ecrypto:decrypt(encryption_key, response.body.secret))
        end)

        it("should be able to retrieve an escher key", function()
            local create_escher_key_response = send_admin_request({
                method = "POST",
                path = "/consumers/" .. consumer.id .. "/escher_key/",
                body = {
                    key = "another_test_key",
                    secret = "test_secret"
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            assert.are.equal(201, create_escher_key_response.status)

            local retrieve_escher_key_response = send_admin_request({
                method = "GET",
                path = "/consumers/" .. consumer.id .. "/escher_key/another_test_key"
            })

            assert.are.equal(200, retrieve_escher_key_response.status)
            assert.are.equal("another_test_key", retrieve_escher_key_response.body.key)
            assert.is_nil(retrieve_escher_key_response.body.secret)
        end)

        it("should be able to delete an escher key", function()
            local create_escher_key_response = send_admin_request({
                method = "POST",
                path = "/consumers/" .. consumer.id .. "/escher_key/",
                body = {
                    key = "yet_another_test_key",
                    secret = "test_secret"
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })

            assert.are.equal(201, create_escher_key_response.status)

            local delete_escher_key_response = assert(helpers.admin_client():send {
                method = "DELETE",
                path = "/consumers/" .. consumer.id .. "/escher_key/yet_another_test_key"
            })

            assert.are.equal(204, delete_escher_key_response.status)
        end)

        context("when escher key does not exist", function()
            local test_cases = {"GET", "DELETE"}

            for _, method in ipairs(test_cases) do
                it("should respond with 404 on " .. method .. " request", function()
                    local retrieve_escher_key_response = send_admin_request({
                        method = method,
                        path = "/consumers/" .. consumer.id .. "/escher_key/" .. consumer.id
                    })

                    assert.are.equal(404, retrieve_escher_key_response.status)
                    assert.are.same({ message = "Not found" }, retrieve_escher_key_response.body)
                end)
            end
        end)
    end)

    context("when plugin does not exist", function()

        local consumer

        before_each(function()
            helpers.db:truncate()

            local service = kong_sdk.services:create({
                name = "testservice",
                url = "http://mockbin:8080/request"
            })

            kong_sdk.routes:create_for_service(service.id, "/")

            consumer = kong_sdk.consumers:create({
                username = 'test',
            })
        end)

        it("should return 412 on escher key creation", function()
            local response = send_admin_request({
                method = "POST",
                path = "/consumers/" .. consumer.id .. "/escher_key/",
                body = {
                    key = "test_key2",
                    secret = "test_secret2"
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
