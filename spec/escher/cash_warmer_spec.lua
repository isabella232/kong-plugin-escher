local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("CacheWarmer", function()

    local consumer

    before_each(function()
        helpers.db:truncate()

        consumer = helpers.db.daos.consumers:insert({
            username = "CacheTestUser"
        })
    end)

    after_each(function()
        helpers.stop_kong()
    end)

    context("cache_all_entities", function()
        it("should store consumer in cache", function()
            helpers.start_kong({ plugins = "escher" })

            local cache_key = helpers.db.daos.consumers:cache_key(consumer.id)

            local raw_response = assert(helpers.admin_client():send {
                method = "GET",
                path = "/cache/" .. cache_key,
            })

            local body = assert.res_status(200, raw_response)
            local response = cjson.decode(body)

            assert.is_equal(response.username, "CacheTestUser")
        end)

        it("should store escher_key in cache", function()
            local escher_credential = helpers.dao.escher_keys:insert({
                key = "suite_test-integration_v1",
                consumer_id = consumer.id
            })

            helpers.start_kong({ plugins = "escher" })

            local cache_key = helpers.dao.escher_keys:cache_key(escher_credential.key)

            local raw_response = assert(helpers.admin_client():send {
                method = "GET",
                path = "/cache/" .. cache_key,
            })

            local body = assert.res_status(200, raw_response)
            local response = cjson.decode(body)

            assert.is_equal(response.key, "suite_test-integration_v1")
        end)
    end)
end)