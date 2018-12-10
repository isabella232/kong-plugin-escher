local crud = require "kong.api.crud_helpers"
local Crypt = require "kong.plugins.escher.crypt"
local EncryptionKeyPathRetriever =  require "kong.plugins.escher.encryption_key_path_retriever"

return {
    ["/consumers/:username_or_id/escher_key/"] = {
        before = function(self, dao_factory, helpers)
            crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
            self.params.consumer_id = self.consumer.id
        end,

        POST = function(self, dao_factory, helpers)
            local path = EncryptionKeyPathRetriever(dao_factory.plugins):find_key_path()

            if not path then
                return helpers.responses.send(412, {
                    message = "Encryption key was not defined"
                })
            end

            local crypt = Crypt(path)
            local encrypted_secret = crypt:encrypt(self.params.secret)

            self.params.secret = encrypted_secret

            crud.post(self.params, dao_factory.escher_keys)
        end
    },

    ["/consumers/:username_or_id/escher_key/:escher_key_name_or_id"] = {
        before = function(self, dao_factory, helpers)
            crud.find_consumer_by_username_or_id(self, dao_factory, helpers)

            local credentials, err = crud.find_by_id_or_field(
                dao_factory.escher_keys,
                { consumer_id = self.consumer.id },
                ngx.unescape_uri(self.params.escher_key_name_or_id),
                "key"
            )

            if err then
                return helpers.yield_error(err)
            elseif #credentials == 0 then
                return helpers.responses.send_HTTP_NOT_FOUND()
            end

            self.escher_key = credentials[1]
        end,

        GET = function(self, dao_factory, helpers)
            return helpers.responses.send_HTTP_OK({
                id = self.escher_key.id,
                consumer_id = self.escher_key.consumer_id,
                key = self.escher_key.key
            })
        end,

        DELETE = function(self, dao_factory, helpers)
            crud.delete(self.escher_key, dao_factory.escher_keys)
        end
    }
}
