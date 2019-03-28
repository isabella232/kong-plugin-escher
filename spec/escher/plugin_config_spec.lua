local PluginConfig = require "kong.plugins.escher.plugin_config"

describe("PluginConfig", function()
    describe("#merge_onto_defaults", function()
        it("should return an empty table for an empty schema and empty config", function()
            local subject = PluginConfig({})

            assert.are.same({}, subject:merge_onto_defaults({}))
        end)

        it("should return merged copy of schema defaults and config", function()
            local schema = {
                fields = {
                    my_config = { type = "string" },
                    with_default = { type = "string", default = "some other value" }
                }
            }

            local subject = PluginConfig(schema)

            assert.are.same({
                my_config = "some value",
                with_default = "some other value"
            }, subject:merge_onto_defaults({
                my_config = "some value"
            }))
        end)

        it("should handle the plugin's schema correctly", function()
            local schema = require "kong.plugins.escher.schema"

            assert.are.same({
                headers_to_sign = {},
                strict_header_signing = false,
                message_template = '{"message": "%s"}',
                status_code = 401
            }, PluginConfig(schema):merge_onto_defaults({}))
        end)
    end)
end)