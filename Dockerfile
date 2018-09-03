FROM emarsys/kong-dev-docker:75e7c55c6b5e0e76cc70db52c142120e97199fe1

RUN yum install -y cmake gcc-c++ openssl-devel

RUN luarocks install date 2.1.2-1
RUN luarocks install classic
RUN luarocks install escher
RUN luarocks install lua-easy-crypto 1.0.0
RUN luarocks install kong-lib-logger --deps-mode=none

CMD ["/kong/bin/kong", "start", "--v"]
