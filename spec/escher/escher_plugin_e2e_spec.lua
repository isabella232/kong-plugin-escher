local Escher = require "escher"
local base64 = require "base64"
local kong_helpers = require "spec.helpers"
local test_helpers = require "kong_client.spec.test_helpers"

describe("Plugin: escher (access) #e2e", function()

    local kong_sdk, send_request, send_admin_request

    local service

    setup(function()
        kong_helpers.start_kong({ plugins = 'escher' })

        kong_sdk = test_helpers.create_kong_client()
        send_request = test_helpers.create_request_sender(kong_helpers.proxy_client())
        send_admin_request = test_helpers.create_request_sender(kong_helpers.admin_client())
    end)

    teardown(function()
        kong_helpers.stop_kong()
    end)

    describe("Plugin setup", function()
        local service, consumer

        before_each(function()
            kong_helpers.db:truncate()

            service = kong_sdk.services:create({
                name = "testservice",
                url = "http://mockbin:8080/request"
            })

            kong_sdk.routes:create_for_service(service.id, "/")

            consumer = kong_sdk.consumers:create({
                username = 'test',
            })
        end)

        context("when using a wrong config", function()
            it("should respond 400 when required config values not provided", function()

                local success, response = pcall(function()
                    kong_sdk.plugins:create({
                        service_id = service.id,
                        name = "escher",
                        config = {}
                    })
                end)

                assert.are.equal("encryption_key_path is required", response.body["config.encryption_key_path"])
            end)

            it("should respond 400 when encryption file does not exist", function()

                local success, response = pcall(function()
                    kong_sdk.plugins:create({
                        service_id = service.id,
                        name = "escher",
                        config = { encryption_key_path = "/non-existing-file.txt" }
                    })
                end)

                assert.are.equal(400, response.status)
            end)

            it("should respond 400 when encryption file path does not equal with the other escher plugin configurations", function()

                local other_service = kong_sdk.services:create({
                    name = "second",
                    url = "http://mockbin:8080/request"
                })

                kong_sdk.routes:create_for_service(other_service.id, "/")

                local f = io.open("/tmp/other_secret.txt", "w")
                f:close()

                kong_sdk.plugins:create({
                    service_id = service.id,
                    name = "escher",
                    config = { encryption_key_path = "/secret.txt" }
                })

                local success, response = pcall(function()
                    kong_sdk.plugins:create({
                        service_id = other_service.id,
                        name = "escher",
                        config = { encryption_key_path = "/tmp/other_secret.txt" }
                    })
                end)

                assert.are.equal(400, response.status)
            end)

            it("should indicate failure when message_template is not a valid JSON", function()

                local success, response = pcall(function()
                    kong_sdk.plugins:create({
                        service_id = service.id,
                        name = "escher",
                        config = { message_template = "not a JSON" }
                    })
                end)

                assert.are.equal(400, response.status)
                assert.are.equal("message_template should be valid JSON object", response.body["config.message_template"])
            end)

            it("should indicate failure when status code is not in the HTTP status range", function()

                local success, response = pcall(function()
                    kong_sdk.plugins:create({
                        service_id = service.id,
                        name = "escher",
                        config = { status_code = 600 }
                    })
                end)

                assert.are.equal(400, response.status)
                assert.are.equal("status code is invalid", response.body["config.status_code"])
            end)
        end)

        it("should use dafaults configs aren't provided", function()

            local plugin = kong_sdk.plugins:create({
                service_id = service.id,
                name = "escher",
                config = { encryption_key_path = "/secret.txt" }
            })

            assert.are.equal('{"message": "%s"}', plugin.config.message_template)
            assert.are.equal(401, plugin.config.status_code)
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
            ["url"] = "/request"
        }

        local escher = Escher:new(config)
        local escher_wrong_api_key = Escher:new(config_wrong_api_key)

        local ems_auth_header = escher:generateHeader(request, {})
        local ems_auth_header_wrong_api_key = escher_wrong_api_key:generateHeader(request, {})

        context("when anonymous user does not allowed", function()
            local service, consumer

            before_each(function()
                kong_helpers.db:truncate()

                service = kong_sdk.services:create({
                    name = "testservice",
                    url = "http://mockbin:8080/request"
                })

                kong_sdk.routes:create_for_service(service.id, "/")

                kong_sdk.plugins:create({
                    service_id = service.id,
                    name = "escher",
                    config = { encryption_key_path = "/secret.txt" }
                })

                consumer = kong_sdk.consumers:create({
                    username = 'test',
                })
            end)

            it("responds with status 401 if request not has X-EMS-DATE and X-EMS-AUTH header", function()
                local response = send_request({
                    method = "GET",
                    path = "/",
                    headers = {
                        ["Host"] = "test1.com"
                    }
                })

                assert.are.equal(401, response.status)
                assert.are.equal("The x-ems-date header is missing", response.body.message)
                assert.are.same({ message = "The x-ems-date header is missing" }, response.body)
            end)

            it("responds with status 401 when X-EMS-AUTH header is invalid", function()
                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = 'invalid header'
                    }
                })

                assert.are.equal(401, response.status)
                assert.are.same({ message = "Could not parse X-Ems-Auth header" }, response.body)
            end)

            it("responds with status 401 when X-EMS-Date header is invalid", function()
                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = 'invalid date',
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = 'invalid header'
                    }
                })

                assert.are.equal(401, response.status)
                assert.are.same({ message = "Could not parse X-Ems-Date header" }, response.body)
            end)

            it("responds with status 200 when X-EMS-AUTH header is valid", function()
                send_admin_request({
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

                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = ems_auth_header
                    }
                })

                assert.are.equal(200, response.status)
            end)

            it("responds with status 401 when api key was not found", function()
                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = ems_auth_header_wrong_api_key
                    }
                })

                assert.are.equal(401, response.status)
                assert.are.same({ message = "Invalid Escher key" }, response.body)
            end)
        end)

        context("when anonymous user allowed", function()

            local service, consumer

            before_each(function()
                kong_helpers.db:truncate()

                service = kong_sdk.services:create({
                    name = "testservice",
                    url = "http://mockbin:8080/request"
                })

                kong_sdk.routes:create_for_service(service.id, "/")

                anonymous = kong_sdk.consumers:create({
                    username = 'anonymous',
                })

                kong_sdk.plugins:create({
                    service_id = service.id,
                    name = "escher",
                    config = { anonymous = anonymous.id, encryption_key_path = "/secret.txt" }
                })

                consumer = kong_sdk.consumers:create({
                    username = 'TestUser',
                })
            end)

            it("responds with status 200 if request not has X-EMS-AUTH header", function()
                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["Host"] = "test1.com"
                    }
                })

                assert.are.equal(200, response.status)
            end)

            it("should proxy the request with anonymous when X-EMS-AUTH header is invalid", function()
                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = 'invalid header'
                    }
                })

                assert.are.equal(200, response.status)
                assert.are.equal("anonymous", response.body.headers["x-consumer-username"])
            end)

            it("should proxy the request with proper user when X-EMS-AUTH header is valid", function()
                send_admin_request({
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

                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = ems_auth_header
                    }
                })

                assert.are.equal(200, response.status)
                assert.are.equal("TestUser", response.body.headers["x-consumer-username"])
            end)

            it("responds with status 200 when api key was not found", function()
                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = ems_auth_header_wrong_api_key
                    }
                })

                assert.are.equal(200, response.status)
            end)
        end)

        context("when message template is not default", function()

            local service

            before_each(function()
                kong_helpers.db:truncate()

                service = kong_sdk.services:create({
                    name = "testservice",
                    url = "http://mockbin:8080/request"
                })

                kong_sdk.routes:create_for_service(service.id, "/")

                kong_sdk.plugins:create({
                    service_id = service.id,
                    name = "escher",
                    config = { encryption_key_path = "/secret.txt", message_template = '{"custom-message": "%s"}' }
                })
            end)

            it("should return response message in the given format", function()
                local response = send_request({
                    method = "GET",
                    path = "/request"
                })

                assert.are.equal(401, response.status)

                assert.is_nil(response.body.message)
                assert.not_nil(response.body['custom-message'])
                assert.are.equal("The x-ems-date header is missing", response.body['custom-message'])
            end)

        end)

        context('when given status code for failed authentications', function()

            local service

            before_each(function()
                kong_helpers.db:truncate()

                service = kong_sdk.services:create({
                    name = "testservice",
                    url = "http://mockbin:8080/request"
                })

                kong_sdk.routes:create_for_service(service.id, "/")

                kong_sdk.plugins:create({
                    service_id = service.id,
                    name = "escher",
                    config = { encryption_key_path = "/secret.txt", status_code = 400 }
                })
            end)

            it("should reject request with given HTTP status", function()
                local response = send_request({
                    method = "GET",
                    path = "/request"
                })

                assert.are.equal(400, response.status)
            end)

        end)

        context("when Escher returns debug info", function()
            before_each(function()
                kong_helpers.db:truncate()

                service = kong_sdk.services:create({
                    name = "testservice",
                    url = "http://mockbin:8080/request"
                })

                kong_sdk.routes:create_for_service(service.id, "/")

                kong_sdk.plugins:create({
                    service_id = service.id,
                    name = "escher",
                    config = { encryption_key_path = "/secret.txt" }
                })

                local consumer = kong_sdk.consumers:create({
                    username = 'test'
                })

                send_admin_request({
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
            end)

            it("should append base64 encoded debug message if x-ems-debug is present", function()
                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-Ems-Debug"] = "",
                        ["X-Ems-Date"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-Ems-Auth"] = ems_auth_header .. "b"
                    }
                })

                assert.are.equal(401, response.status)

                local encoded_message = response.body.message:match("The signatures do not match %(Base64 encoded debug message: '(.-)'%)")
                local debug_message = encoded_message and base64.decode(encoded_message) or nil

                assert.are.equal("string", type(debug_message))
            end)

            it("should not append debug message if x-ems-debug is missing", function()
                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-Ems-Date"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-Ems-Auth"] = ems_auth_header .. "b"
                    }
                })

                assert.are.equal(401, response.status)
                assert.are.equal("The signatures do not match", response.body.message)
            end)
        end)

    end)

end)
