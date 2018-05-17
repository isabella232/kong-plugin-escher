local crud = require "kong.api.crud_helpers"

return {
    ["/consumers/:username_or_id/escher_key/"] = {
        before = function(self, dao_factory, helpers)
            crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
            self.params.consumer_id = self.consumer.id
        end,

        POST = function(self, dao_factory, helpers)
            crud.post(self.params, dao_factory.escher_keys)
        end
    },

    ["/consumers/:username_or_id/escher_key/:escher_key_name_or_id"] = {
        before = function(self, dao_factory, helpers)
            crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
            self.params.consumer_id = self.consumer.id

            local credentials, err = crud.find_by_id_or_field(
                dao_factory.escher_keys,
                { consumer_id = self.params.consumer_id },
                ngx.unescape_uri(self.params.escher_key_name_or_id),
                "key"
            )

            if err then
                return helpers.yield_error(err)
            elseif next(credentials) == nil then
                return helpers.responses.send_HTTP_NOT_FOUND()
            end
            self.params.escher_key_name_or_id = nil

            self.escher_key = credentials[1]
        end,

        GET = function(self, dao_factory, helpers)
            local escher_key = {}
            escher_key.id = self.escher_key.id
            escher_key.consumer_id = self.escher_key.consumer_id
            escher_key.key = self.escher_key.key

            return helpers.responses.send_HTTP_OK(escher_key)
        end,

        DELETE = function(self, dao_factory, helpers)
            crud.delete(self.escher_key, dao_factory.escher_keys)
        end
    }
}
