FROM emarsys/kong-dev-docker:latest

RUN yum install -y cmake gcc-c++ openssl-devel

RUN luarocks install date 2.1.2-1
RUN luarocks install classic
RUN luarocks install escher
RUN luarocks install kong-lib-logger --deps-mode=none

COPY docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["/kong/bin/kong", "start", "--v"]
