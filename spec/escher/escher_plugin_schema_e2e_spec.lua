local kong_helpers = require "spec.helpers"
local test_helpers = require "kong_client.spec.test_helpers"

describe("Escher #plugin #schema #e2e", function()

    local kong_sdk
    local service

    setup(function()
        kong_helpers.start_kong({ plugins = "escher" })

        kong_sdk = test_helpers.create_kong_client()
    end)

    teardown(function()
        kong_helpers.stop_kong()
    end)

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

        assert.are.equals("required field missing", response.body.fields.config.encryption_key_path)
    end)

    it("should use dafaults when config values are not provided", function()
        local plugin = kong_sdk.plugins:create({
            service = { id = service.id },
            name = "escher",
            config = { encryption_key_path = "/secret.txt" }
        })

        assert.are.equals(plugin.config.anonymous, ngx.null)
        assert.are.equals('{"message": "%s"}', plugin.config.message_template)
        assert.are.equals(401, plugin.config.status_code)
        assert.are.same({}, plugin.config.additional_headers_to_sign)
        assert.are.equals(false, plugin.config.require_additional_headers_to_be_signed)
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

            assert.are.equals(400, response.status)
            assert.are.equals("Anonymous must a valid uuid if specified", response.body.fields.config.anonymous)
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

            assert.are.equals(400, response.status)
            assert.are.equals("Encryption key file could not be found.", response.body.fields.config["@entity"][1])
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

            assert.are.equals(400, response.status)
            assert.are.equals("All Escher plugins must be configured to use the same encryption file.", response.body.fields.config["@entity"][1])
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

                assert.are.equals(400, response.status)
                assert.are.equals("message_template should be valid JSON object", response.body.fields.config.message_template)
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

            assert.are.equals(400, response.status)
            assert.are.equals("status code is invalid", response.body.fields.config.status_code)
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

            assert.are.equals(400, response.status)
            assert.are.equals("status code is invalid", response.body.fields.config.status_code)
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

            assert.are.equals(true, success)
        end)
    end)
end)
