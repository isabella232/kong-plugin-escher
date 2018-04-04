package = "kong-plugin-escher"
version = "0.1.0-1"
supported_platforms = {"linux", "macosx"}
source = {
  url = "git+https://github.com/emartech/kong-plugin-escher.git",
  tag = "0.1.0"
}
description = {
  summary = "Escher auth plugin for Kong API gateway.",
  homepage = "https://github.com/emartech/kong-plugin-escher",
  license = "UNLICENSED"
}
dependencies = {
  "lua >= 5.1",
  "date 2.1.2-1",
  "classic 0.1.0-1",
  "escher 0.2-17",
  "kong-lib-logger >= 0.3.0-1"
}
build = {
  type = "builtin",
  modules = {
    ["kong.plugins.escher.handler"] = "kong/plugins/escher/handler.lua",
    ["kong.plugins.escher.schema"] = "kong/plugins/escher/schema.lua",
    ["kong.plugins.escher.migrations.cassandra"] = "kong/plugins/escher/migrations/cassandra.lua",
    ["kong.plugins.escher.migrations.postgres"] = "kong/plugins/escher/migrations/postgres.lua"
  }
}
