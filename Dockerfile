FROM emarsys/kong-dev-docker:03dcac138951fc470872105917a67b4655205495

RUN yum install -y cmake gcc-c++ openssl-devel

RUN luarocks install date 2.1.2-1
RUN luarocks install classic
RUN luarocks install escher
RUN luarocks install lua-easy-crypto 1.0.0
RUN luarocks install kong-lib-logger --deps-mode=none

COPY docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["/kong/bin/kong", "start", "--v"]
