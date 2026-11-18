# appease tooling that expects us to support multiple versions (see also versions.sh / versions.json)
if IN($ARGS.positional; [], ["latest"]) then . else
	error("unexpected parameters: \($ARGS.positional)")
end
| .latest

| .version as $version
| (
	# "1.2.3" -> [ "1.2.3", "1.2", "1", "" ]
	$version
	| split(".")
	| [
		foreach .[] as $c ([]; . += [ $c ])
		| join(".")
	]
	| reverse + [ "" ]
) as $versionTags

| .variants
| to_entries

# variants are in precedence order (newest PHP first, with pre-releases after the release of the same version), so the first of each kind gets the "generic" tags
| first(.[].value.php | select(endswith("-rc") | not)) as $latestPhp
| first(.[].value.suite | select(startswith("alpine") | not)) as $latestDebian
| first(.[].value.suite | select(startswith("alpine"))) as $latestAlpine

| .[]
| .key as $variant # "php8.5-trixie", "php8.6-rc-alpine3.24", etc
| .value

# Tags: version-phpX.Y-suite, version-phpX.Y, (version-phpX.Y-alpine), and (version-suite, version, version-alpine) for the latest PHP release
| (
	.suite as $suite
	| [
		$suite,
		if $suite == $latestDebian then
			""
		else empty end,
		if $suite == $latestAlpine then
			"alpine"
		else empty end,
		empty
	] as $suiteNames
	| [
		$suiteNames[] as $suiteName
		| [ "php\(.php)", $suiteName | select(. != "") ]
		| join("-")
	]
	+ if .php == $latestPhp then
		$suiteNames
	else [] end
) as $names

| {
	Tags: [
		$versionTags[] as $version
		| $names[] as $name
		| [ $version, $name | select(. != "") ]
		| join("-")
		| if . == "" then "latest" else . end
	],
	Architectures: .arches,
	Directory: "latest/\($variant)",
}

| "", (
	to_entries[]
	| .value |= if type == "array" then join(", ") else . end
	| "\(.key): \(.value)"
)
