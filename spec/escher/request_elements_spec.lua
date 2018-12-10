local RequestElements = require "kong.plugins.escher.request_elements"

describe("Request Elements", function()

    local ngx_mock

    before_each(function()
        ngx_mock = {
            req = {
                get_method = function()
                    return "GET"
                end,
                get_body_data = function()
                    return ''
                end,
                get_headers = function()
                    return { ["X-Test-Header"] = 'Some Content', }
                end,
                read_body = function() end
            },
            var = {
                request_uri = ''
            },
        }

    end)

    describe("#collect", function()
        it("should return a request object for authentication", function()
            local request_elements = RequestElements(ngx_mock)

            local expected = {
                ["method"] = "GET",
                ["url"] = '',
                ["headers"] = { ["X-Test-Header"] = 'Some Content', },
                ["body"] = ''
            }

            assert.are.same(expected, request_elements:collect())
        end)

        it("should call ngx.req.read_body() when creating request object", function()
            spy.on(ngx_mock.req, "read_body")
            local request_elements = RequestElements(ngx_mock)
            request_elements:collect()

            assert.spy(ngx_mock.req.read_body).was.called()
        end)

    end)
end)