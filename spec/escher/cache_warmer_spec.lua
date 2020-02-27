local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("CacheWarmer", function()

    local consumer
    local admin_client
    local db

    setup(function()
        local _
        _, db = helpers.get_db_utils()
    end)

    before_each(function()
        db:truncate()

        consumer = db.consumers:insert({
            username = "CacheTestUser"
        })

        assert(helpers.start_kong({ plugins = "bundled,escher" }))
        admin_client = helpers.admin_client()
    end)

    after_each(function()
        if admin_client then
            admin_client:close()
        end
        helpers.stop_kong()
    end)

    context("cache_all_entities", function()
        it("should store consumer in cache", function()
            local cache_key = db.consumers:cache_key(consumer.id)
            local raw_response = assert(admin_client:get("/cache/" .. cache_key, {
                headers = {}
            }))
            local body = assert.res_status(200, raw_response)
            local response = cjson.decode(body)

            assert.is_equal(response.username, "CacheTestUser")
        end)

        it("should store escher_key in cache", function()
            local escher_key = db.escher_keys:insert({
                key = "suite_test-integration_v1",
                consumer = { id = consumer.id }
            })

            local cache_key = db.escher_keys:cache_key(escher_key.key)
            local raw_response = assert(admin_client:get("/cache/" .. cache_key, {
                headers = {}
            }))
            local body = assert.res_status(200, raw_response)
            local response = cjson.decode(body)

            assert.is_equal(response.key, "suite_test-integration_v1")
        end)
    end)
end)