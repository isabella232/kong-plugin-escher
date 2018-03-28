FROM emarsys/kong-dev-docker:latest

RUN luarocks install date 2.1.2-1
RUN luarocks install classic

COPY docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["/kong/bin/kong", "start", "--v"]
