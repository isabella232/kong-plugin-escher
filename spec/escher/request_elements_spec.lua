local RequestElements = require "kong.plugins.escher.request_elements"

describe("Request Elements", function()

    local kong_mock

    before_each(function()

        kong_mock = {
            request = {
                get_path = function()
                    return ""
                end,
                get_path_with_query = function()
                    return "/?a=b"
                end,
                get_method = function()
                    return "GET"
                end,
                get_headers = function()
                    return { ["X-Test-Header"] = "Some Content", }
                end,
                get_body = function()
                    return ""
                end
            }
        }

    end)

    describe("#collect", function()
        it("should return a request object for authentication", function()
            local request_elements = RequestElements(kong_mock)

            local expected = {
                ["method"] = "GET",
                ["url"] = "/?a=b",
                ["headers"] = { ["X-Test-Header"] = "Some Content", },
                ["body"] = ""
            }

            assert.are.same(expected, request_elements:collect())
        end)
    end)
end)