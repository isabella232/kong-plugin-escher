FROM emarsys/kong-dev-docker:5fa91b6bb62e6a01d6a5a8782a8a550d4d7ec56d

RUN yum install -y cmake gcc-c++ openssl-devel

RUN luarocks install date 2.1.2-1
RUN luarocks install classic
RUN luarocks install escher
RUN luarocks install lua-easy-crypto 1.0.0
RUN luarocks install kong-lib-logger --deps-mode=none
