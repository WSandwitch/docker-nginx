FROM alpine:3.17 AS build

ENV NGINX_VERSION 1.25.4
# https://github.com/nginx/njs
ENV NJS_MODULE_VERSION 0.8.4
# https://github.com/google/ngx_brotli
ENV BROTLI_MODULE_VERSION 6e975bcb015f62e1f303054897783355e2a877dc
# https://github.com/openresty/echo-nginx-module
ENV ECHO_MODULE_VERSION v0.63
# https://github.com/openresty/headers-more-nginx-module
ENV HEADERS_MODULE_VERSION v0.37
# https://github.com/openresty/memc-nginx-module
ENV MEMC_MODULE_VERSION v0.20
# https://github.com/vision5/ngx_devel_kit
ENV NDK_MODULE_VERSION v0.3.3
# https://github.com/openresty/ngx_postgres
ENV POSTGRES_MODULE_VERSION 1.0
# https://github.com/openresty/rds-json-nginx-module
ENV RDSJSON_MODULE_VERSION nginx-1.25.3
# https://github.com/openresty/redis2-nginx-module
ENV REDIS2_MODULE_VERSION v0.15
# https://github.com/centminmod/ngx_http_redis
ENV REDIS_MODULE_VERSION 0.4.1-cmm
# https://github.com/openresty/set-misc-nginx-module
ENV SETMISC_MODULE_VERSION v0.33
# https://github.com/levonet/nginx-sticky-module-ng
ENV STICKY_MODULE_VERSION nginx-1.23.0
# https://github.com/openresty/srcache-nginx-module
ENV SRCACHE_MODULE_VERSION v0.33
# https://github.com/weibocom/nginx-upsync-module
ENV UPSYNC_MODULE_VERSION v2.1.3
# https://github.com/xiaokai-wang/nginx-stream-upsync-module
ENV UPSYNC_STREAM_MODULE_VERSION v1.2.2
# https://github.com/jaegertracing/jaeger-client-cpp
ENV JAEGER_CLIENT_VERSION v0.9.0
# https://github.com/opentracing/opentracing-cpp
ENV OPENTRACING_LIB_VERSION v1.6.0
# https://github.com/opentracing-contrib/nginx-opentracing
ENV OPENTRACING_MODULE_VERSION v0.27.0
# https://github.com/matsumotory/ngx_mruby
ENV MRUBY_MODULE_VERSION v2.5.0
# https://github.com/tokers/zstd-nginx-module
ENV ZSTD_MODULE_VERSION master
# https://github.com/quictls/openssl
ENV QUICTLS_VERSION openssl-3.1.5+quic
# https://github.com/AlecJY/socks-nginx-module
ENV SOCKS5HTTP_VERSION space-fix

COPY *.patch /tmp/

RUN set -eux \
    && addgroup -S -g 101 nginx \
    && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u 101 nginx \
    && apk add --no-cache \
        cmake \
        perl \
        curl \
        g++ \
        gcc \
        gettext \
        git \
        gnupg-dirmngr \
        gpg \
        gpg-agent \
        libc-dev \
        linux-headers \
        make \
        ruby-rake \
        patch \
        pcre-dev \
        postgresql-dev \
        readline-dev \
        fts \
        libxml2-dev libxslt-dev \
        zlib-dev \
        zstd-dev \
        musl-fts-dev 


RUN set -eux \
    && export GPG_KEYS=B0F4253373F8F6F510D42178520A9993A1C052F8 \
    # https://nginx.org/en/pgp_keys.html
    && curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz -o nginx.tar.gz \
    && curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz.asc -o nginx.tar.gz.asc \
    && export GNUPGHOME="$(mktemp -d)" \
    && found=''; \
    for server in \
        ha.pool.sks-keyservers.net \
        hkp://keyserver.ubuntu.com:80 \
        hkp://p80.pool.sks-keyservers.net:80 \
        pgp.mit.edu \
    ; do \
        echo "Fetching GPG key $GPG_KEYS from $server"; \
        gpg --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$GPG_KEYS" && found=yes && break; \
    done; \
    test -z "$found" && echo >&2 "error: failed to fetch GPG key $GPG_KEYS" && exit 1; \
    curl -fSL https://nginx.org/keys/pluknet.key -o nginx_signing.key \
    && gpg --import nginx_signing.key \
    && curl -fSL https://nginx.org/keys/maxim.key -o nginx_signing.key \
    && gpg --import nginx_signing.key \
    && curl -fSL https://nginx.org/keys/arut.key -o nginx_signing.key \
    && gpg --import nginx_signing.key \
    && curl -fSL https://nginx.org/keys/sb.key -o nginx_signing.key \
    && gpg --import nginx_signing.key \
    && curl -fSL https://nginx.org/keys/thresh.key -o nginx_signing.key \
    && gpg --import nginx_signing.key \
    && curl -fSL https://nginx.org/keys/nginx_signing.key -o nginx_signing.key \
    && gpg --import nginx_signing.key \
    && gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz \
    && rm -rf "$GNUPGHOME" nginx_signing.key nginx.tar.gz.asc \
    && mkdir -p /usr/src \
    && tar -zxC /usr/src -f nginx.tar.gz \
    && rm nginx.tar.gz 

RUN set -eux && echo SSL \
    && cd /usr/src/nginx-${NGINX_VERSION} \
    && git clone --depth=1 --single-branch -b ${QUICTLS_VERSION} https://github.com/quictls/openssl \
    && (cd openssl && git submodule update --init --recursive; \
        ./Configure --prefix=/opt/openssl --libdir=lib --api=1.1.1; \
	make -j3; \
        make test TESTS="-test_afalg"; \
        make install; \
    ) 

    # Jaeger
RUN set -eux && echo opentracing \
    && cd /usr/src/nginx-${NGINX_VERSION} \
    && git clone --depth=1 --single-branch -b ${OPENTRACING_LIB_VERSION} https://github.com/opentracing/opentracing-cpp.git \
    && mkdir opentracing-cpp/.build \
    && (cd opentracing-cpp/.build; \
        cmake \
            -DBUILD_MOCKTRACER=OFF \
            -DBUILD_STATIC_LIBS=OFF \
            -DBUILD_TESTING=OFF \
            -DCMAKE_BUILD_TYPE=Release \
            ..; \
        make -j3; \
        make install \
    ) 

RUN set -eux && echo jaeger \
    && cd /usr/src/nginx-${NGINX_VERSION} \
    && git clone --depth=1 --single-branch -b ${JAEGER_CLIENT_VERSION} https://github.com/jaegertracing/jaeger-client-cpp.git \
    && mkdir jaeger-client-cpp/.build \
    && (cd jaeger-client-cpp/.build; \
        cmake \
            -DBUILD_TESTING=OFF \
            -DCMAKE_BUILD_TYPE=Release \
            -DHUNTER_CONFIGURATION_TYPES=Release \
            -DJAEGERTRACING_BUILD_EXAMPLES=OFF \
            -DJAEGERTRACING_COVERAGE=OFF \
            -DJAEGERTRACING_WARNINGS_AS_ERRORS=OFF \
            -DJAEGERTRACING_WITH_YAML_CPP=ON \
            ..; \
        make -j3; \
#        make test; \
        make install \
    ) 

RUN set -eux && echo modules \
    && cd /usr/src/nginx-${NGINX_VERSION} \
    && export HUNTER_INSTALL_DIR=$(cat jaeger-client-cpp/.build/_3rdParty/Hunter/install-root-dir) \
    && git clone --depth=1 --single-branch -b ${OPENTRACING_MODULE_VERSION} https://github.com/opentracing-contrib/nginx-opentracing.git \
    \
    # Nginx Development Kit
    && git clone --depth=1 --single-branch -b ${NDK_MODULE_VERSION} https://github.com/vision5/ngx_devel_kit.git \
    \
    # Transparent subrequest-based caching layout for arbitrary nginx locations
    && git clone --depth=1 --single-branch -b ${SRCACHE_MODULE_VERSION} https://github.com/openresty/srcache-nginx-module.git \
    \
    # An nginx output filter that formats Resty DBD Streams generated by ngx_drizzle and others to JSON
    && git clone --depth=1 --single-branch -b ${RDSJSON_MODULE_VERSION} https://github.com/openresty/rds-json-nginx-module.git \
    \
    # Nginx upstream module that allows nginx to communicate directly with PostgreSQL database
    && git clone --depth=1 --single-branch -b ${POSTGRES_MODULE_VERSION} https://github.com/openresty/ngx_postgres.git \
    && (cd ngx_postgres; patch -p1 < /tmp/ngx_postgres-dynamic-module.patch) \
    \
    # Nginx upstream module for the Redis 2.0 protocol
    && git clone --depth=1 --single-branch -b ${REDIS2_MODULE_VERSION} https://github.com/openresty/redis2-nginx-module.git \
    \
    # An extended version of the standard memcached module
    && git clone --depth=1 --single-branch -b ${MEMC_MODULE_VERSION} https://github.com/openresty/memc-nginx-module.git \
    \
    # An Nginx module for bringing the power of "echo", "sleep", "time" and more to Nginx's config file
    && git clone --depth=1 --single-branch -b ${ECHO_MODULE_VERSION} https://github.com/openresty/echo-nginx-module.git \
    \
    # Set and clear input and output headers
    && git clone --depth=1 --single-branch -b ${HEADERS_MODULE_VERSION} https://github.com/openresty/headers-more-nginx-module.git \
    \
    # Various set_xxx directives added to nginx's rewrite module
    && git clone --depth=1 --single-branch -b ${SETMISC_MODULE_VERSION} https://github.com/openresty/set-misc-nginx-module.git \
    \
    # Sticky
    && git clone --depth=1 --single-branch -b ${STICKY_MODULE_VERSION} https://github.com/levonet/nginx-sticky-module-ng.git \
    \
    # Upstream health check
    && git clone --depth=1 https://github.com/yaoweibin/nginx_upstream_check_module.git \
    && patch -p1 < /usr/src/nginx-${NGINX_VERSION}/nginx_upstream_check_module/check_1.20.1+.patch \
    \
    # Brotli
    && git clone https://github.com/google/ngx_brotli.git \
    && ( \
      cd ngx_brotli; \
      git checkout ${BROTLI_MODULE_VERSION};  \
      git submodule update --init; \
      cd deps/brotli; \
      mkdir out; cd out; \
      cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_C_FLAGS="-Ofast -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" -DCMAKE_CXX_FLAGS="-Ofast -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" -DCMAKE_INSTALL_PREFIX=./installed .. ;\
      cmake --build . --config Release --target brotlienc ;\
    ) \
    \
    # Redis
    && git clone --depth=1 --single-branch -b ${REDIS_MODULE_VERSION} https://github.com/centminmod/ngx_http_redis \
    \
    # A forward proxy module for CONNECT request handling
    && git clone --depth=1 https://github.com/chobits/ngx_http_proxy_connect_module.git \
    && patch -p1 < ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_102101.patch \
    \
    # Sync upstreams from consul or others
    && git clone --depth=1 --single-branch -b ${UPSYNC_MODULE_VERSION} https://github.com/weibocom/nginx-upsync-module.git \
    \
    # Stream sync upstreams from consul or others
    && git clone --depth=1 --single-branch -b ${UPSYNC_STREAM_MODULE_VERSION} https://github.com/xiaokai-wang/nginx-stream-upsync-module.git \
    \
    # njs scripting language
    && git clone --depth=1 --single-branch -b ${NJS_MODULE_VERSION} https://github.com/nginx/njs.git \
    && git clone https://github.com/WSandwitch/njs_inline_patch \
    && (cd njs_inline_patch && \
	sh apply.sh ../njs \
    ) \
    && (cd njs && \
        ./configure \
            --cc-opt="-O2 -pipe -fPIC -fomit-frame-pointer" && \
        make && \
        make unit_test && \
        install -m755 build/njs /usr/bin/ \
    ) \
    \
    # mruby scripting language
    && git clone --depth=1 --single-branch -b ${MRUBY_MODULE_VERSION} https://github.com/matsumotory/ngx_mruby.git \
    && (cd ngx_mruby && \
        touch mruby/include/mruby/internal.h && \
        patch -p1 < /tmp/mruby_alpine.patch && \
        patch -p1 < /tmp/add_gems.patch && \
        ./configure --enable-dynamic-module --with-ngx-src-root=/usr/src/nginx-${NGINX_VERSION} --with-ngx-config-opt=--prefix=/etc/nginx --with-ndk-root=/usr/src/nginx-${NGINX_VERSION}/ngx_devel_kit && \
        NGX_MRUBY_CFLAGS=-O3 make build_mruby && \
        make generate_gems_config_dynamic \
    ) \
    # ZStd compression
    && git clone --depth=1 --single-branch -b ${ZSTD_MODULE_VERSION} https://github.com/tokers/zstd-nginx-module.git \
    # http_socks5
    && git clone --depth=1 --single-branch -b ${SOCKS5HTTP_VERSION} https://github.com/AlecJY/socks-nginx-module.git

RUN set -eux && echo nginx \
    && cd /usr/src/nginx-${NGINX_VERSION} \
    && export HUNTER_INSTALL_DIR=$(cat jaeger-client-cpp/.build/_3rdParty/Hunter/install-root-dir) \
    && CFLAGS="-Ofast -pipe -fPIE -fPIC -flto -funroll-loops -fstack-protector-strong -ffast-math -fomit-frame-pointer -Wformat -Werror=format-security -D_FORTIFY_SOURCE=2" \
        ./configure \
            --prefix=/etc/nginx \
            --sbin-path=/usr/sbin/nginx \
            --modules-path=/usr/lib/nginx/modules \
            --conf-path=/etc/nginx/nginx.conf \
            --error-log-path=/var/log/nginx/error.log \
            --http-log-path=/var/log/nginx/access.log \
            --pid-path=/var/run/nginx.pid \
            --lock-path=/var/run/nginx.lock \
            --http-client-body-temp-path=/var/cache/nginx/client_temp \
            --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
            --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
            --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
            --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
            --user=nginx \
            --group=nginx \
            --with-compat \
            --with-file-aio \
            --with-http_addition_module \
            --with-http_auth_request_module \
            --with-http_degradation_module \
            --with-http_gunzip_module \
            --with-http_gzip_static_module \
            --with-http_realip_module \
            --with-http_secure_link_module \
            --with-http_ssl_module \
            --with-http_stub_status_module \
            --with-http_v2_module \
            --with-http_v3_module \
            --with-pcre \
            --with-stream \
            --with-stream_realip_module \
            --with-stream_ssl_module \
            --with-stream_ssl_preread_module \
            --with-threads \
            --with-cc-opt="-I${HUNTER_INSTALL_DIR}/include -I./openssl/include" \
            --with-ld-opt="-L${HUNTER_INSTALL_DIR}/lib -lfts -L./openssl" \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/echo-nginx-module \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/headers-more-nginx-module \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/memc-nginx-module \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/nginx-opentracing/opentracing \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/nginx-sticky-module-ng \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/nginx-stream-upsync-module \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/nginx-upsync-module \
            --add-module=/usr/src/nginx-${NGINX_VERSION}/ngx_brotli \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/ngx_devel_kit \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/ngx_http_redis \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/ngx_postgres \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/njs/nginx \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/rds-json-nginx-module \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/redis2-nginx-module \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/set-misc-nginx-module \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/srcache-nginx-module \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/ngx_mruby \
            --add-module=/usr/src/nginx-${NGINX_VERSION}/nginx_upstream_check_module \
            --add-module=/usr/src/nginx-${NGINX_VERSION}/ngx_http_proxy_connect_module \
            --add-module=/usr/src/nginx-${NGINX_VERSION}/zstd-nginx-module \
            --add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/socks-nginx-module \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install \
    && rm -rf /etc/nginx/html/ \
    && mkdir /etc/nginx/conf.d/ \
    && mkdir /etc/nginx/sites-enabled/ \
    && mkdir -p /usr/share/nginx/html/ \
    && install -m644 html/index.html /usr/share/nginx/html/ \
    && install -m644 html/50x.html /usr/share/nginx/html/ \
    && ln -s ../../usr/lib/nginx/modules /etc/nginx/modules \
    && cp -p ${HUNTER_INSTALL_DIR}/lib/libyaml-cpp.so* /usr/local/lib/ \
    && strip /usr/bin/njs \
        /usr/sbin/nginx \
        /usr/lib/nginx/modules/*.so \
        /usr/local/lib/libopentracing.so* \
        /usr/local/lib/libyaml-cpp.so* \
        /usr/local/lib/libjaegertracing.so*

FROM alpine:3.17

COPY --from=build /etc/nginx /etc/nginx
COPY --from=build /usr/sbin/nginx /usr/sbin/nginx
COPY --from=build /usr/bin/njs /usr/bin/njs
COPY --from=build /usr/bin/envsubst /usr/local/bin/envsubst
COPY --from=build /usr/lib/nginx/ /usr/lib/nginx/
COPY --from=build /usr/share/nginx /usr/share/nginx
COPY --from=build /usr/local/lib/libopentracing.so* /usr/local/lib/
COPY --from=build /usr/local/lib/libyaml-cpp.so* /usr/local/lib/
COPY --from=build /usr/local/lib/libjaegertracing.so* /usr/local/lib/
COPY --from=build /opt/openssl /opt/openssl

COPY nginx.conf /etc/nginx/nginx.conf
COPY nginx.vh.default.conf /etc/nginx/conf.d/default.conf

RUN apk add --no-cache \
        libintl \
        libpq \
        libstdc++ \
        musl \
        pcre \
        readline \
        tzdata \
	fts \
	musl-fts \
	libxml2 libxslt\
        zstd \
        zlib \
    && addgroup -S -g 101 nginx \
    && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u 101 nginx \
    && mkdir -p /var/log/nginx \
    && ln -sf /usr/local/lib/libjaegertracing.so /usr/local/lib/libjaegertracing_plugin.so \
    && ln -sf /opt/openssl/lib/*so* /usr/lib/ \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]
