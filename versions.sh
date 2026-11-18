#!/usr/bin/env bash
set -Eeuo pipefail

# this updates "versions.json" with the latest upstream release data

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

# appease tooling that expects us to support multiple versions (see also the end of this script where we write out the JSON file)
export fakeVersion='latest'
if [ "${*:-$fakeVersion}" != "$fakeVersion" ]; then
	printf >&2 'error: unexpected parameter: %q\n' "$@"
	exit 1
fi

# prints a JSON object with the "version" and "commit" of the highest "PREFIX" + "MAJOR.MINOR.PATCH" tag of a git repository
latestGitTag() {
	local repo="$1"; shift
	local prefix="$1"; shift

	local tags
	tags="$(git ls-remote --tags "$repo" "refs/tags/$prefix*")"

	jq <<<"$tags" --raw-input --slurp --arg prefix "$prefix" --arg repo "$repo" '
		split("\n")
		| map(
			select(. != "")
			| split("\t")
			| {
				commit: .[0],
				ref: (.[1] | ltrimstr("refs/tags/\($prefix)")),
			}
			| select(.ref | rtrimstr("^{}") | test("^[0-9]+[.][0-9]+[.][0-9]+$"))
		)
		# annotated tags list both the tag object and (as "^{}") the commit it points at, and we want the commit
		| group_by(.ref | rtrimstr("^{}"))
		| map({
			version: (.[0].ref | rtrimstr("^{}")),
			commit: ((map(select(.ref | endswith("^{}"))) + .)[0].commit),
		})
		| sort_by(.version | split(".") | map(tonumber))
		| last // error("no tags matching \($prefix)MAJOR.MINOR.PATCH in \($repo)")
	'
}

# FrankenPHP only supports its latest release, so that is the only one we build
# https://github.com/php/frankenphp/blob/a3663e9e2cc4c258018a28ee068e50cc12f3ed2d/SECURITY.md
frankenphp="$(latestGitTag https://github.com/php/frankenphp.git v)"
frankenphpCommit="$(jq <<<"$frankenphp" --raw-output '.commit')"
echo "FrankenPHP $(jq <<<"$frankenphp" --raw-output '.version') ($frankenphpCommit)"

watcher="$(latestGitTag https://github.com/e-dant/watcher.git release/)"

# the highest "go" directive of the two modules FrankenPHP builds from (the older "golang" images cannot build it, and "GOTOOLCHAIN=local" means they will not try to download something newer)
goMods="$(curl -fsSL \
	"https://github.com/php/frankenphp/raw/$frankenphpCommit/go.mod" \
	"https://github.com/php/frankenphp/raw/$frankenphpCommit/caddy/go.mod"
)"
goRequired="$(jq <<<"$goMods" --raw-input --slurp --raw-output '
	split("\n")
	| map(select(test("^go [0-9]")) | ltrimstr("go "))
	| max_by(split(".") | map(tonumber))
')"
echo "Go $goRequired"

oiBase="${BASHBREW_LIBRARY:-https://github.com/docker-library/official-images/raw/HEAD/library}"

# prints a JSON array of { "tags": [ "repo:tag", ... ], "arches": [ ... ] } objects (one per library entry) for the given library file(s)
libraryEntries() {
	bashbrew cat --format '{{ range .Entries }} { "tags": {{ $.Tags "" false . | json }} , "arches": {{ .Architectures | json }} } {{ end }}' "$@" \
		| jq --slurp --compact-output '.'
}
php="$(libraryEntries "$oiBase/php")"
golang="$(libraryEntries "$oiBase/golang")"

jq --null-input --tab \
	--argjson frankenphp "$frankenphp" \
	--argjson watcher "$watcher" \
	--arg goRequired "$goRequired" \
	--argjson php "$php" \
	--argjson golang "$golang" \
	--from-file versions.jq \
	> versions.json
