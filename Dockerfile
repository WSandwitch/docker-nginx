FROM alpine:edge AS build

ENV NGINX_VERSION 1.14.2

RUN GPG_KEYS=B0F4253373F8F6F510D42178520A9993A1C052F8 \
	&& addgroup -S nginx \
	&& adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
	&& apk add --no-cache --repository "http://dl-cdn.alpinelinux.org/alpine/edge/testing/" \
		gcc \
		libc-dev \
		make \
		openssl-dev \
		pcre-dev \
		zlib-dev \
		linux-headers \
		curl \
		gnupg1 \
		git \
		gettext \
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
	gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz \
	&& rm -rf "$GNUPGHOME" nginx.tar.gz.asc \
	&& mkdir -p /usr/src \
	&& tar -zxC /usr/src -f nginx.tar.gz \
	&& rm nginx.tar.gz \
	&& cd /usr/src/nginx-${NGINX_VERSION} \
	\
	# https://bitbucket.org/nginx-goodies/nginx-sticky-module-ng
	&& mkdir -p /usr/src/nginx-${NGINX_VERSION}/nginx-sticky-module-ng \
	&& curl -fSL https://bitbucket.org/nginx-goodies/nginx-sticky-module-ng/get/master.tar.gz -o nginx-sticky-module-ng.tar.gz \
	&& tar -zxC /usr/src/nginx-${NGINX_VERSION}/nginx-sticky-module-ng -f nginx-sticky-module-ng.tar.gz --strip 1 \
	\
	# https://github.com/2Fast2BCn/nginx_upstream_check_module
	&& mkdir -p /usr/src/nginx-${NGINX_VERSION}/nginx_upstream_check_module \
	&& curl -fSL https://github.com/2Fast2BCn/nginx_upstream_check_module/archive/master.tar.gz -o nginx_upstream_check_module.tar.gz \
	&& tar -zxC /usr/src/nginx-${NGINX_VERSION}/nginx_upstream_check_module -f nginx_upstream_check_module.tar.gz --strip 1 \
	&& patch -p1 < /usr/src/nginx-${NGINX_VERSION}/nginx_upstream_check_module/check_1.14.0+.patch \
	\
	# Brotli
	&& git clone https://github.com/google/ngx_brotli --depth=1 \
	&& (cd ngx_brotli; git submodule update --init) \
	\
	# Redis
	&& mkdir -p /usr/src/nginx-${NGINX_VERSION}/ngx_http_redis \
	&& curl -fSL https://people.freebsd.org/~osa/ngx_http_redis-0.3.9.tar.gz -o ngx_http_redis.tar.gz \
	&& tar -zxC /usr/src/nginx-${NGINX_VERSION}/ngx_http_redis -f ngx_http_redis.tar.gz --strip 1 \
	\
	&& CFLAGS="-pipe -m64 -Ofast -flto -mtune=generic -march=x86-64 -fPIE -fPIC -funroll-loops -fstack-protector-strong -mfpmath=sse -msse4.2 -ffast-math -fomit-frame-pointer -Wformat -Werror=format-security -D_FORTIFY_SOURCE=2" \
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
			--with-threads \
			--with-file-aio \
			--with-http_ssl_module \
			--with-http_v2_module \
			--with-http_realip_module \
			--with-http_addition_module \
			--with-http_gunzip_module \
			--with-http_gzip_static_module \
			--with-http_auth_request_module \
			--with-http_secure_link_module \
			--with-http_degradation_module \
			--with-stream \
			--with-stream_ssl_module \
			--with-stream_ssl_preread_module \
			--with-stream_realip_module \
			--with-compat \
			--with-pcre \
			--add-module=/usr/src/nginx-${NGINX_VERSION}/nginx-sticky-module-ng \
			--add-module=/usr/src/nginx-${NGINX_VERSION}/nginx_upstream_check_module \
			--add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/ngx_brotli \
			--add-dynamic-module=/usr/src/nginx-${NGINX_VERSION}/ngx_http_redis \
	&& make -j$(getconf _NPROCESSORS_ONLN) \
	&& make install \
	&& rm -rf /etc/nginx/html/ \
	&& mkdir /etc/nginx/conf.d/ \
	&& mkdir /etc/nginx/sites-enabled/ \
	&& mkdir -p /usr/share/nginx/html/ \
	&& install -m644 html/index.html /usr/share/nginx/html/ \
	&& install -m644 html/50x.html /usr/share/nginx/html/ \
	&& ln -s ../../usr/lib/nginx/modules /etc/nginx/modules \
	&& strip /usr/sbin/nginx \
	&& strip /usr/lib/nginx/modules/*.so

FROM alpine:edge

COPY --from=build /etc/nginx /etc/nginx
COPY --from=build /usr/sbin/nginx /usr/sbin/nginx
COPY --from=build /usr/bin/envsubst /usr/local/bin/envsubst
COPY --from=build /usr/lib/nginx/ /usr/lib/nginx/
COPY --from=build /usr/share/nginx /usr/share/nginx

COPY nginx.conf /etc/nginx/nginx.conf
COPY nginx.vh.default.conf /etc/nginx/conf.d/default.conf

RUN apk add --no-cache \
		musl \
		pcre \
		libssl1.1 \
		libcrypto1.1 \
		zlib \
		libintl \
		tzdata \
	&& addgroup -S nginx \
	&& adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
	&& mkdir -p /var/log/nginx \
	&& ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]
