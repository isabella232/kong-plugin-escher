local Escher = require "escher"
local base64 = require "base64"
local kong_helpers = require "spec.helpers"
local test_helpers = require "kong_client.spec.test_helpers"

describe("Escher plugin #e2e", function()

    local kong_sdk, send_request, send_admin_request

    setup(function()
        kong_helpers.start_kong({ plugins = "escher" })

        kong_sdk = test_helpers.create_kong_client()
        send_request = test_helpers.create_request_sender(kong_helpers.proxy_client())
        send_admin_request = test_helpers.create_request_sender(kong_helpers.admin_client())
    end)

    teardown(function()
        kong_helpers.stop_kong()
    end)

    describe("#schema", function()
        local service

        before_each(function()
            kong_helpers.db:truncate()

            service = kong_sdk.services:create({
                name = "testservice",
                url = "http://mockbin:8080/request"
            })
        end)

        it("should respond with error when required config values are not provided", function()
            local _, response = pcall(function()
                kong_sdk.plugins:create({
                    service = { id = service.id },
                    name = "escher",
                    config = {}
                })
            end)

            assert.is_equal("required field missing", response.body.fields.config.encryption_key_path)
        end)

        it("should use dafaults when config values are not provided", function()
            local plugin = kong_sdk.plugins:create({
                service = { id = service.id },
                name = "escher",
                config = { encryption_key_path = "/secret.txt" }
            })

            assert.is_equal('{"message": "%s"}', plugin.config.message_template)
            assert.is_equal(401, plugin.config.status_code)
            assert.are.same({}, plugin.config.additional_headers_to_sign)
            assert.is_equal(false, plugin.config.require_additional_headers_to_be_signed)
        end)

        context("when anonymous field is set", function()
            it("should throw error when anonymous is not a valid uuid", function()
                local _, response = pcall(function()
                    kong_sdk.plugins:create({
                        service = { id = service.id },
                        name = "escher",
                        config = {
                            encryption_key_path = "/secret.txt",
                            anonymous = "not-a-valid-uuid"
                        }
                    })
                end)

                assert.is_equal(400, response.status)
                assert.is_equal("Anonymous must a valid uuid if specified", response.body.fields.config.anonymous)
            end)
        end)

        context("when encryption_key_path field is set", function()
            it("should respond 400 when encryption file does not exist", function()
                local _, response = pcall(function()
                    kong_sdk.plugins:create({
                        service = { id = service.id },
                        name = "escher",
                        config = { encryption_key_path = "/non-existing-file.txt" }
                    })
                end)

                assert.is_equal(400, response.status)
                assert.is_equal("Encryption key file could not be found.", response.body.fields.config["@entity"][1])
            end)

            it("should respond 400 when encryption file path does not equal with the other escher plugin configurations", function()
                local other_service = kong_sdk.services:create({
                    name = "second",
                    url = "http://mockbin:8080/request"
                })

                local f = io.open("/tmp/other_secret.txt", "w")
                f:close()

                kong_sdk.plugins:create({
                    service = { id = service.id },
                    name = "escher",
                    config = { encryption_key_path = "/secret.txt" }
                })

                local _, response = pcall(function()
                    kong_sdk.plugins:create({
                        service = { id = other_service.id },
                        name = "escher",
                        config = { encryption_key_path = "/tmp/other_secret.txt" }
                    })
                end)

                assert.is_equal(400, response.status)
                assert.is_equal("All Escher plugins must be configured to use the same encryption file.", response.body.fields.config["@entity"][1])
            end)
        end)

        context("when message_template field is set", function()
            local test_cases = {'{"almafa": %s}', '""', '[{"almafa": "%s"}]'}
            for _, test_template in ipairs(test_cases) do
                it("should throw error when message_template is not valid JSON object", function()
                    local _, response = pcall(function()
                        kong_sdk.plugins:create({
                            service = { id = service.id },
                            name = "escher",
                            config = {
                                encryption_key_path = "/secret.txt",
                                message_template = test_template
                            }
                        })
                    end)

                    assert.is_equal(400, response.status)
                    assert.is_equal("message_template should be valid JSON object", response.body.fields.config.message_template)
                end)
            end
        end)

        context("when status_code field is set", function()
            it("should throw error when it is lower than 100", function()
                local _, response = pcall(function()
                    kong_sdk.plugins:create({
                        service = { id = service.id },
                        name = "escher",
                        config = {
                            encryption_key_path = "/secret.txt",
                            status_code = 66
                        }
                    })
                end)

                assert.is_equal(400, response.status)
                assert.is_equal("status code is invalid", response.body.fields.config.status_code)
            end)
            it("should throw error when it is higher than 600", function()
                local _, response = pcall(function()
                    kong_sdk.plugins:create({
                        service = { id = service.id },
                        name = "escher",
                        config = {
                            encryption_key_path = "/secret.txt",
                            status_code = 666
                        }
                    })
                end)

                assert.is_equal(400, response.status)
                assert.is_equal("status code is invalid", response.body.fields.config.status_code)
            end)
            it("should succeed when it is within the range", function()
                local success, _ = pcall(function()
                    return kong_sdk.plugins:create({
                        service = { id = service.id },
                        name = "escher",
                        config = {
                            encryption_key_path = "/secret.txt",
                            status_code = 400
                        }
                    })
                end)

                assert.is_equal(true, success)
            end)
        end)
    end)

    describe("#handler", function()

        local current_date = os.date("!%Y%m%dT%H%M%SZ")

        local config = {
            algoPrefix      = "EMS",
            vendorKey       = "EMS",
            credentialScope = "eu/suite/ems_request",
            authHeaderName  = "X-Ems-Auth",
            dateHeaderName  = "X-Ems-Date",
            accessKeyId     = "test_key",
            apiSecret       = "test_secret",
            date            = current_date,
        }

        local config_wrong_api_key = {
            algoPrefix      = "EMS",
            vendorKey       = "EMS",
            credentialScope = "eu/suite/ems_request",
            authHeaderName  = "X-Ems-Auth",
            dateHeaderName  = "X-Ems-Date",
            accessKeyId     = "wrong_key",
            apiSecret       = "test_secret",
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
                    service = { id = service.id },
                    name = "escher",
                    config = { encryption_key_path = "/secret.txt" }
                })

                consumer = kong_sdk.consumers:create({
                    username = "test",
                    custom_id = "Test"
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

                assert.is_equal(401, response.status)
                assert.is_equal("The x-ems-date header is missing", response.body.message)
                assert.are.same({ message = "The x-ems-date header is missing" }, response.body)
            end)

            it("responds with status 401 when X-EMS-AUTH header is invalid", function()
                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = "invalid header"
                    }
                })

                assert.is_equal(401, response.status)
                assert.are.same({ message = "Could not parse X-Ems-Auth header" }, response.body)
            end)

            it("responds with status 401 when X-EMS-Date header is invalid", function()
                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = "invalid date",
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = "invalid header"
                    }
                })

                assert.is_equal(401, response.status)
                assert.are.same({ message = "Could not parse X-Ems-Date header" }, response.body)
            end)

            it("responds with status 200 when X-EMS-AUTH header is valid", function()
                send_admin_request({
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

                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = ems_auth_header
                    }
                })

                assert.is_equal(200, response.status)
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

                assert.is_equal(401, response.status)
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

                local anonymous = kong_sdk.consumers:create({
                    username = "anonymous",
                })

                kong_sdk.plugins:create({
                    service = { id = service.id },
                    name = "escher",
                    config = {
                        anonymous = anonymous.id,
                        encryption_key_path = "/secret.txt"
                    }
                })

                consumer = kong_sdk.consumers:create({
                    username = "TestUser",
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

                assert.is_equal(200, response.status)
            end)

            it("should proxy the request with anonymous when X-EMS-AUTH header is invalid", function()
                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = "invalid header"
                    }
                })

                assert.is_equal(200, response.status)
                assert.is_equal("anonymous", response.body.headers["x-consumer-username"])
            end)

            it("should proxy the request with proper user when X-EMS-AUTH header is valid", function()
                send_admin_request({
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

                local response = send_request({
                    method = "GET",
                    path = "/request",
                    headers = {
                        ["X-EMS-DATE"] = current_date,
                        ["Host"] = "test1.com",
                        ["X-EMS-AUTH"] = ems_auth_header
                    }
                })

                assert.is_equal(200, response.status)
                assert.is_equal("TestUser", response.body.headers["x-consumer-username"])
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

                assert.is_equal(200, response.status)
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
                    service = { id = service.id },
                    name = "escher",
                    config = {
                        encryption_key_path = "/secret.txt",
                        message_template = '{"custom-message": "%s"}'
                    }
                })
            end)

            it("should return response message in the given format", function()
                local response = send_request({
                    method = "GET",
                    path = "/request"
                })

                assert.is_equal(401, response.status)

                assert.is_nil(response.body.message)
                assert.not_nil(response.body["custom-message"])
                assert.is_equal("The x-ems-date header is missing", response.body["custom-message"])
            end)

        end)

        context("when given headers to sign", function()

            local service

            before_each(function()
                kong_helpers.db:truncate()

                service = kong_sdk.services:create({
                    url = "http://mockbin:8080/request"
                })

                kong_sdk.routes:create_for_service(service.id, "/")

                local consumer = kong_sdk.consumers:create({
                    username = "test"
                })

                send_admin_request({
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
            end)

            local function headers_to_array(key_value_headers)
                local headers = {}

                for key, value in pairs(key_value_headers) do
                    table.insert(headers, {key, value})
                end

                return headers
            end

            local function sign_request(request)
                request.headers["X-Ems-Date"] = current_date
                request.headers["X-Ems-Auth"] = escher:generateHeader({
                    method = request.method,
                    url = request.path,
                    headers = headers_to_array(request.headers)
                }, request.additional_headers_to_sign)

                return request
            end

            context("and strict header signing is off", function()

                before_each(function()
                    kong_helpers.db.plugins:truncate()

                    kong_sdk.plugins:create({
                        service = { id = service.id },
                        name = "escher",
                        config = {
                            encryption_key_path = "/secret.txt",
                            additional_headers_to_sign = { "X-Suite-CustomerId" },
                            require_additional_headers_to_be_signed = false
                        }
                    })
                end)

                it("should allow request when header is signed", function()
                    local response = send_request(sign_request({
                        method = "GET",
                        path = "/request",
                        additional_headers_to_sign = { "X-Suite-CustomerId" },
                        headers = {
                            ["Host"] = "test1.com",
                            ["X-Suite-CustomerId"] = "12345678"
                        }
                    }))

                    assert.is_equal(200, response.status)
                end)

                it("should reject request when header is not signed", function()
                    local response = send_request(sign_request({
                        method = "GET",
                        path = "/request",
                        additional_headers_to_sign = {},
                        headers = {
                            ["Host"] = "test1.com",
                            ["X-Suite-CustomerId"] = "12345678"
                        }
                    }))

                    assert.is_equal(401, response.status)
                    assert.is_equal("The X-Suite-CustomerId header is not signed", response.body.message)
                end)

                it("should allow request when header is not present", function()
                    local response = send_request(sign_request({
                        method = "GET",
                        path = "/request",
                        additional_headers_to_sign = {},
                        headers = {
                            ["Host"] = "test1.com"
                        }
                    }))

                    assert.is_equal(200, response.status)
                end)

            end)

            context("and strict header signing is on", function()

                before_each(function()
                    kong_helpers.db.plugins:truncate()

                    kong_sdk.plugins:create({
                        service = { id = service.id },
                        name = "escher",
                        config = {
                            encryption_key_path = "/secret.txt",
                            additional_headers_to_sign = { "X-Suite-CustomerId" },
                            require_additional_headers_to_be_signed = true
                        }
                    })
                end)

                it("should reject request when header is not present", function()
                    local response = send_request(sign_request({
                        method = "GET",
                        path = "/request",
                        additional_headers_to_sign = {},
                        headers = {
                            ["Host"] = "test1.com"
                        }
                    }))

                    assert.is_equal(401, response.status)
                    assert.is_equal("The X-Suite-CustomerId header is not signed", response.body.message)
                end)

            end)

        end)

        context("when given status code for failed authentications", function()

            local service

            before_each(function()
                kong_helpers.db:truncate()

                service = kong_sdk.services:create({
                    name = "testservice",
                    url = "http://mockbin:8080/request"
                })

                kong_sdk.routes:create_for_service(service.id, "/")

                kong_sdk.plugins:create({
                    service = { id = service.id },
                    name = "escher",
                    config = {
                        encryption_key_path = "/secret.txt",
                        status_code = 400
                    }
                })
            end)

            it("should reject request with given HTTP status", function()
                local response = send_request({
                    method = "GET",
                    path = "/request"
                })

                assert.is_equal(400, response.status)
            end)

        end)

        context("when Escher returns debug info", function()

            local service

            before_each(function()
                kong_helpers.db:truncate()

                service = kong_sdk.services:create({
                    name = "testservice",
                    url = "http://mockbin:8080/request"
                })

                kong_sdk.routes:create_for_service(service.id, "/")

                kong_sdk.plugins:create({
                    service = { id = service.id },
                    name = "escher",
                    config = { encryption_key_path = "/secret.txt" }
                })

                local consumer = kong_sdk.consumers:create({
                    username = "test"
                })

                send_admin_request({
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

                assert.is_equal(401, response.status)

                local encoded_message = response.body.message:match("The signatures do not match %(Base64 encoded debug message: '(.-)'%)")
                local debug_message = encoded_message and base64.decode(encoded_message) or nil

                assert.is_equal("string", type(debug_message))
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

                assert.is_equal(401, response.status)
                assert.is_equal("The signatures do not match", response.body.message)
            end)
        end)

    end)

end)
