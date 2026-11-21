#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM php:8.3-zts-alpine3.24

RUN apk add --no-cache \
# for "/etc/mime.types" (static files get their "Content-Type" from it)
		mailcap

# https://frankenphp.dev
ENV FRANKENPHP_VERSION 1.13.5
ENV FRANKENPHP_COMMIT a3663e9e2cc4c258018a28ee068e50cc12f3ed2d

# https://github.com/e-dant/watcher (file watching)
ENV WATCHER_VERSION 0.14.5
ENV WATCHER_COMMIT 06f84a1314be18f5e697ebbf28c0fab2d17c9c39

RUN --mount=type=bind,from=golang:1.27-alpine3.24,source=/usr/local/go,target=/usr/local/go \
	set -eux; \
	\
	apk add --no-cache --virtual .build-deps \
		$PHPIZE_DEPS \
		argon2-dev \
		brotli-dev \
		cmake \
		curl-dev \
		git \
		gnu-libiconv-dev \
		libcap \
		libsodium-dev \
		libxml2-dev \
		linux-headers \
		oniguruma-dev \
		openssl-dev \
		readline-dev \
		sqlite-dev \
	; \
	\
	git clone --depth 1 --branch "release/$WATCHER_VERSION" https://github.com/e-dant/watcher.git /usr/src/watcher; \
	[ "$(git -C /usr/src/watcher rev-parse HEAD)" = "$WATCHER_COMMIT" ]; \
	cmake -S /usr/src/watcher -B /usr/src/watcher/build -DCMAKE_BUILD_TYPE=Release; \
	cmake --build /usr/src/watcher/build --parallel "$(nproc)"; \
	cmake --install /usr/src/watcher/build; \
	rm -rf /usr/src/watcher; \
	\
	git clone --depth 1 --branch "v$FRANKENPHP_VERSION" https://github.com/php/frankenphp.git /usr/src/frankenphp; \
	[ "$(git -C /usr/src/frankenphp rev-parse HEAD)" = "$FRANKENPHP_COMMIT" ]; \
	cd /usr/src/frankenphp/caddy/frankenphp; \
	ldflags="-w -s -X 'github.com/caddyserver/caddy/v2.CustomVersion=FrankenPHP $FRANKENPHP_VERSION PHP $PHP_VERSION Caddy' -X 'github.com/caddyserver/caddy/v2.CustomBinaryName=frankenphp' -X 'github.com/caddyserver/caddy/v2/modules/caddyhttp.ServerHeader=FrankenPHP Caddy'"; \
# musl's default thread stack size is small, and PHP code (especially Symfony) can need a lot more
# https://frankenphp.dev/docs/compile/#using-xcaddy
	ldflags="$ldflags -extldflags '-Wl,-z,stack-size=0x80000'"; \
	export \
		CGO_CFLAGS="-DFRANKENPHP_VERSION=$FRANKENPHP_VERSION $PHP_CFLAGS" \
		CGO_CPPFLAGS="$PHP_CPPFLAGS" \
		CGO_LDFLAGS="-L/usr/local/lib -lssl -lcrypto -lreadline -largon2 -lcurl -lonig -lz $PHP_LDFLAGS" \
		GOBIN=/usr/local/bin \
		GOCACHE=/tmp/go-build \
		GOPATH=/tmp/go \
# the toolchain comes from the "golang" image, so never download a different one
		GOTOOLCHAIN=local \
		PATH="/usr/local/go/bin:$PATH" \
	; \
	../../go.sh install -ldflags "$ldflags" -buildvcs=true; \
# binding to ports 80 and 443 shouldn't require running as root
# "+p" instead of "+ep" because Caddy (2.11.8+) raises the capability itself when it needs it, so this keeps working with "--cap-drop ALL" and friends
# https://github.com/caddyserver/caddy-docker/commit/8338ec8d1aece9a6ccfa68649adf6935166d6acf
	setcap cap_net_bind_service=+p /usr/local/bin/frankenphp; \
	\
	mkdir -p \
		/config/caddy \
		/data/caddy \
		/etc/frankenphp/Caddyfile.d \
	; \
	cp Caddyfile /etc/frankenphp/Caddyfile; \
# the upstream docs use "/etc/frankenphp", but "/etc/caddy" is where people expect it (a symlink, so mounting or copying over either path replaces the one config)
	ln -s /etc/frankenphp /etc/caddy; \
	cp /usr/src/frankenphp/package/content/index.php /var/www/html/index.php; \
	\
	cd /; \
	rm -rf /usr/src/frankenphp /tmp/go /tmp/go-build; \
# the watcher's CLI, headers, static library, and "pkg-config" files are only here because we built it (FrankenPHP only needs the versioned shared library at runtime)
	rm -rf \
		/usr/local/bin/wtr.watcher \
		/usr/local/include/wtr \
		/usr/local/lib/libwatcher-c.a \
		/usr/local/lib/libwatcher-c.so \
		/usr/local/lib/pkgconfig/watcher*.pc \
	; \
	\
# only scan what we ship ("/usr/local" also contains the mounted Go toolchain, whose test data has ELF files for all kinds of other platforms)
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/bin /usr/local/lib \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --no-cache $runDeps; \
	\
	apk del --no-network .build-deps; \
	\
# smoke test
	frankenphp version; \
	frankenphp build-info

COPY docker-php-entrypoint /usr/local/bin/

# "/var/www/html" already exists in the "php" base image (and is where "php:apache" and "php:fpm" serve from)
WORKDIR /var/www/html

# these are the environment variables the upstream "Caddyfile" reads (it defaults to "public/" relative to the working directory, and to a "localhost" site that Caddy redirects to HTTPS)
# https://github.com/php/frankenphp/blob/v1.13.5/caddy/frankenphp/Caddyfile
ENV SERVER_ROOT /var/www/html
# a bare port serves plain HTTP on every hostname (like the other web server images do); set this to a domain name to get automatic HTTPS
ENV SERVER_NAME :80

# https://caddyserver.com/docs/conventions#file-locations
ENV XDG_CONFIG_HOME /config
ENV XDG_DATA_HOME /data

# https://frankenphp.dev/docs/performance/
ENV GODEBUG cgocheck=0

EXPOSE 80
EXPOSE 443
EXPOSE 443/udp

# "docker-php-entrypoint" supplies "frankenphp run --config /etc/frankenphp/Caddyfile" when there are no arguments (or only flags), so any "--config" a user passes simply comes last and wins
CMD []
