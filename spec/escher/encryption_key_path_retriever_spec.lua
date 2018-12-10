local EncryptionKeyPathRetriever = require "kong.plugins.escher.encryption_key_path_retriever"

describe("encryption key retriever", function()

    local plugins_dao
    local plugins = {}

    before_each(function()
        plugins_dao = {
            find_page = function(self, filter, page_offset, page_size)
                return plugins
            end
        }
    end)

    after_each(function()
        plugins = {}
    end)

    describe("#retrieve_key", function()
        it("should return encryption key of the first escher plugin", function()
            plugins = {
                {
                    config = {
                        encryption_key_path = "/secret.txt",
                    },
                    name = "escher",
                }
            }

            local key_retriever = EncryptionKeyPathRetriever(plugins_dao)

            assert.are.same(plugins[1].config.encryption_key_path, key_retriever:find_key_path())
        end)

        context("when plugin has yet to be registered", function()
            it("should return nil", function()
                local key_retriever = EncryptionKeyPathRetriever(plugins_dao)

                assert.is_Nil(key_retriever:find_key_path())
            end)
        end)
    end)
end)