local endpoints = require "kong.api.endpoints"
local Crypt = require "kong.plugins.escher.crypt"
local EncryptionKeyPathRetriever =  require "kong.plugins.escher.encryption_key_path_retriever"

local escher_keys_schema = kong.db.escher_keys.schema
local consumers_schema = kong.db.consumers.schema

return {
    ["/consumers/:consumers/escher_key"] = {
        schema = escher_keys_schema,
        methods = {
            POST = function(self, db, helpers)
                if self.args.post.secret then
                    local path = EncryptionKeyPathRetriever(db):find_key_path()
                    if not path then
                        return kong.response.exit(412, {
                            message = "Encryption key was not defined"
                        })
                    end
                    local crypt = Crypt(path)
                    local encrypted_secret = crypt:encrypt(self.args.post.secret)
                    self.args.post.secret = encrypted_secret
                end
                return endpoints.post_collection_endpoint(escher_keys_schema, consumers_schema, "consumer")(self, db, helpers)
            end,
        }
    },
    ["/consumers/:consumers/escher_key/:escher_keys"] = {
        schema = escher_keys_schema,
        methods = {
            before = function(self, db, helpers)
                local consumer, _, err_t = endpoints.select_entity(self, db, consumers_schema)
                if err_t then
                  return endpoints.handle_error(err_t)
                end
                if not consumer then
                  return kong.response.exit(404, { message = "Not found" })
                end
                self.consumer = consumer

                local cred, _, err_t = endpoints.select_entity(self, db, escher_keys_schema)
                if err_t then
                  return endpoints.handle_error(err_t)
                end

                if not cred or cred.consumer.id ~= consumer.id then
                  return kong.response.exit(404, { message = "Not found" })
                end
                self.escher_key = cred
            end,
            DELETE = endpoints.delete_entity_endpoint(escher_keys_schema),
            GET = function(self, db, helpers)
                return kong.response.exit(200, {
                    id = self.escher_key.id,
                    consumer_id = self.escher_key.consumer.id,
                    key = self.escher_key.key
                })
            end
        }
    }
}
