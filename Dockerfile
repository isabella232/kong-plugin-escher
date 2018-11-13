FROM emarsys/kong-dev-docker:d1a40fe7ae16a51df073a6f12e2cf60060d16afd

RUN yum update -y && \
    yum install -y \
        cmake \
        gcc-c++ \
        openssl-devel && \
    yum clean all && \
    rm -rf /var/cache/yum

RUN luarocks install date 2.1.2-1 && \
    luarocks install classic && \
    luarocks install escher && \
    luarocks install lua-easy-crypto 1.0.0 && \
    luarocks install kong-lib-logger --deps-mode=none
