#!/usr/bin/env bash

# local config layered on top of https://github.com/docker-library/official-images/blob/HEAD/test/config.sh
# (bashbrew's "github-actions/generate.sh" passes both configs to "run.sh" when this file exists)

# FrankenPHP is built on top of "php", so it should pass every test that "php" does ("php-hello-world", "php-argon2", "php-ext-install", etc)
testAlias+=(
	[frankenphp]='php'
)

# "php:apache" tests are only selected for the "apache" variant, but FrankenPHP is also a web server that serves "/var/www/html" over HTTP on port 80, so the same test applies
imageTests+=(
	[frankenphp]='
		php-apache-hello-web
	'
)
