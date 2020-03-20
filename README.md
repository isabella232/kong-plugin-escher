# Kong Escher Plugin

## Install

- clone the git repo
- add luarock api key to environment variables (LUAROCKS_API_KEY)

## Running tests from project folder

`make test`

## Publish new release

- rename rockspec file to the new version
- change then version and source.tag in rockspec file
- commit the changes
- create a new tag (ex.: git tag 0.1.0)
- push the changes with the tag (git push --tag)
- `make publish`

## Create dummy data on Admin API

- `make dev-env`

## Access local DB

- `make db`
