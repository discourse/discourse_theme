# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.3] - 2024-10-09

### Added

- Made `new` command compatible with the replacement of `yarn` with `pnpm` as a package manager, and will prompt users to install `pnpm` if not installed already.

## [2.1.2] - 2024-04-16

### Added

- Suggest the root URL of the local site when running `watch` command

## [2.1.1] - 2024-03-25

### Added

- `--version` to CLI (#46)

## [2.1.0] - 2024-02-28

### Changed

- `new` command now uses discourse-theme-skeleton repo (#44)

## [2.0.0] - 2024-01-31

### Added

- `watch` command for `discourse_theme` will prompt user if pending theme migrations should be run (#40)

### Removed

- Remove upload theme migrations prompt to `watch` command for `discourse_theme` CLI previously added in #38. Theme migrations
  files are always uploaded going forward.

## [1.1.0] - 2024-01-10

### Added

- Add upload theme migrations prompt to `watch` command for `discourse_theme` CLI (#38)

## [1.0.2] - 2023-12-08

### Fixed

- `discourse_theme rspec` command using Docker container not copying theme to the right directory that is mounted inside
  the Docker container.

## [1.0.1] - 2023-10-19

### Fixed

- Spec path was not preserved when running rspec against a local Discourse repository.

## [1.0.0] - 2023-10-09

### Fixed

- Change `--headless` option for the rspec command to `--headful` which is the correct name.

## [0.9.1] - 2023-10-06

### Fixed

- `rspec` command saving settings using wrong dir

## [0.9.0] - 2023-09-27

### Added

- Added the `rspec` command to the CLI to support running RSpec system tests for a theme using either a Docker container
  running the `discourse/discourse_test` image or a local Discourse development environment. See 100f320847a22e11c145886588fac04479c143bb and
  c0c920280bef7869f0515f5e4220cf5cd3e408ef for more details.

## [0.7.6] - 2023-09-16

### Fixed

- Remove trailing slash when storing URL (#25)
