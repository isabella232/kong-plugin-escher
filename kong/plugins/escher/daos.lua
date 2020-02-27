local typedefs = require "kong.db.schema.typedefs"

return { escher_keys = {
    name = "escher_keys",
    primary_key = { "id" },
    cache_key = { "key" },
    generate_admin_api = false,
    endpoint_key = "key",
    fields = {
        { id = typedefs.uuid },
        {
            consumer = {
                type      = "foreign",
                reference = "consumers",
                default   = ngx.null,
                on_delete = "cascade"
            }
        },
        { key = { type = "string", unique = true, required = true } },
        { secret = { type = "string", auto = true } }
    }
} }