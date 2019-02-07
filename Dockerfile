FROM emarsys/kong-dev-docker:0.14.1-centos-a44c2be-f3e427b

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
