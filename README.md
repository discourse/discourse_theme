# Discourse Theme

This CLI contains helpers for creating [Discourse themes](https://meta.discourse.org/c/theme) and theme components.

## Installation

To install the CLI use:

    $ gem install discourse_theme

## Why this gem exists?

This gem allows you to use your editor of choice when developing Discourse themes and theme components. As you save files the CLI will update the remote theme or component and changes to it will appear live!

## Usage

For help run:

```
discourse_theme
```

### `discourse_theme new PATH`

Creates a new blank theme. The CLI will guide you through the process.

### `discourse_theme download PATH`

Downloads a theme from the server and stores in the designated directory.

### `discourse_theme watch PATH`

Monitors a theme or component for changes. When changed the program will synchronize the theme or component to your Discourse of choice.

### `discourse_theme upload PATH`

Uploads a theme to the server. Requires the theme to have been previously synchronized via `watch`.

### `discourse_theme rspec PATH`

Runs the [RSpec](https://rspec.info/) system tests under the `spec` folder for the theme.

Requires [Docker](https://docs.docker.com/engine/install/) to be installed as the tests are ran in a Docker container with
the Discourse test environment configured.

When the `--headless` option is used, a local installation of the [Google Chrome browser](https://www.google.com/chrome/) is required.

## Contributing

Bug reports and pull requests are welcome at [Meta Discourse](https://meta.discourse.org). This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the DiscourseTheme project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/discourse/discourse_theme/blob/main/CODE_OF_CONDUCT.md).
