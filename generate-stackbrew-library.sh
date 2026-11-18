#!/usr/bin/env bash
set -Eeuo pipefail

# this generates the verbatim "library/frankenphp" file contents for making a PR against:
# https://github.com/docker-library/official-images/blob/HEAD/library/frankenphp

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

# get the most recent commit which modified any files related to a build context
commit="$(git log -1 --format='format:%H' HEAD -- '[^.]*/**')"
[ -n "$commit" ]

selfCommit="$(git log -1 --format='format:%H' HEAD -- "$self")"
cat <<-EOH
# this file is generated via https://github.com/tianon-sso/docker-frankenphp/blob/$selfCommit/$self

Maintainers: Tianon Gravi <tianon.gravi@docker.com> (@tianon)
GitRepo: https://github.com/tianon-sso/docker-frankenphp.git
GitCommit: $commit
Builder: buildkit
EOH

exec jq \
	--raw-output \
	--from-file generate-stackbrew-library.jq \
	versions.json \
	--args -- "$@"
