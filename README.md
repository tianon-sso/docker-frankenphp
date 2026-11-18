# frankenphp

This is a mock-up of how a [Docker Official Images](https://github.com/docker-library/official-images#what-are-official-images) repo for `frankenphp` (FrankenPHP, built on top of the official `php` images) *could* look -- and probably would, if Tianon were maintaining it.

It is not an official image, and nothing here is published anywhere.

- `./versions.sh` scrapes upstream into `versions.json`: FrankenPHP and watcher releases, plus the `php` and `golang` library files for the PHP versions, suites, and architectures we can build
- `./apply-templates.sh` generates the `Dockerfile`s from `Dockerfile.template`
- `./generate-stackbrew-library.sh` prints the `library/frankenphp` file that would be submitted to `docker-library/official-images`
