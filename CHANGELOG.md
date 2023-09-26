# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2023-09-27

### Added

- Added the `rspec` command to the CLI to support running RSpec system tests for a theme using either a Docker container
  running the `discourse/discourse_test` image or a local Discourse development environment. See 100f320847a22e11c145886588fac04479c143bb and
  c0c920280bef7869f0515f5e4220cf5cd3e408ef for more details.

## [0.7.6] - 2023-09-16

### Fixed

- Remove trailing slash when storing URL (#25)
