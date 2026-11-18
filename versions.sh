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

json="$(
	jq --null-input --tab \
		--argjson frankenphp "$frankenphp" \
		--argjson watcher "$watcher" \
		--arg goRequired "$goRequired" \
		--argjson php "$php" \
		--argjson golang "$golang" '
			def version_key: split(".") | map(tonumber? // .);

			# the "golang" image we borrow our toolchain from: the oldest one (for this suite) that is new enough for FrankenPHP
			# (so if the exact Go version FrankenPHP asks for has fallen out of "library/golang", we take the next oldest one that is still around)
			def golang_pick($suite):
				[
					$golang[]
					| .arches as $arches
					| [
						.tags[]
						| select(startswith("golang:") and endswith("-" + $suite))
						| ltrimstr("golang:")
						| rtrimstr("-" + $suite)
					] as $versions # "1.27.3", "1.27", "1", ...
					| first($versions[] | select(test("^[0-9]+[.][0-9]+[.][0-9]+$"))) as $patch
					| first($versions[] | select(test("^[0-9]+[.][0-9]+$"))) as $minor
					| {
						from: "golang:\($minor)-\($suite)",
						version: $patch,
						arches: $arches,
					}
					| select((.version | version_key) >= ($goRequired | version_key))
				]
				| sort_by(.version | version_key)
				| first // error("no golang image for \($suite) is new enough for Go \($goRequired)")
			;

			(
				# https://github.com/php/frankenphp/blob/a3663e9e2cc4c258018a28ee068e50cc12f3ed2d/frankenphp.go#L210 ("checkPHPConfig" refuses anything older)
				# TODO scrape this instead of hard-coding it (it is a little fiddly)
				# TODO if FrankenPHP ever starts refusing newer PHP versions, add that here too as "<": "X.Y" (the filter below already understands it, but nothing sets it yet)
				{ ">=": "8.2" }
				| map_values(version_key)
			) as $requires

			# PHP 8.6+ makes the default ("cli") variant ZTS (and drops "zts"), so that is the variant we build on there
			# (see "Dockerfile-linux.template" in docker-library/php)
			| [ 8, 6 ] as $ztsInCli

			| (
				$php
				| map(
					.arches as $arches
					| first(
						.tags[]
						| capture("(?x)
							^
							php :
							(?<php> [0-9]+ [.] [0-9]+ )
							(?<rc> -rc )?
							- (?<flavor> zts | cli )
							- (?<suite> [^:]+ )
							$
						")
					)
					| .rc = (.rc != null)
					| .arches = $arches
					| select(
						(.php | version_key) as $v
						| (.flavor == "zts" or $v >= $ztsInCli)
						and if $requires.">=" then
							$v >= $requires.">="
						else true end
						and if $requires."<" then
							$v < $requires."<"
						else true end
					)
				)
			) as $phpVariants

			# only the newest Debian suite and the newest Alpine suite (which is the first of each in the library order)
			| [
				first($phpVariants[].suite | select(startswith("alpine") | not)),
				first($phpVariants[].suite | select(startswith("alpine"))),
				empty
			] as $suites

			| {
				latest: {
					version: $frankenphp.version,
					commit: $frankenphp.commit,
					go: $goRequired,
					watcher: $watcher,
					variants: (
						[
							$phpVariants[]
							| select(.suite | IN($suites[]))
							| golang_pick(.suite) as $go
							| {
								php: "\(.php)\(if .rc then "-rc" else "" end)", # "8.5", "8.6-rc"
								suite,
								from: "php:\(.php)\(if .rc then "-rc" else "" end)-\(.flavor)-\(.suite)",
								golang: $go.from,
								arches: (
									.arches
									| map(select(IN($go.arches[])))
									| if length == 0 then
										error("no architectures in common between php and golang for \(.suite)")
									else . end
								),
							}
						]
						| sort_by([
							(.php | rtrimstr("-rc") | version_key | map(-.)),
							(.php | endswith("-rc")),
							(.suite as $suite | $suites | index($suite)),
							empty
						])
						| map({
							key: "php\(.php)-\(.suite)",
							value: .,
						})
						| from_entries
					),
				},
			}
		'
)"
printf '%s\n' "$json" > versions.json
