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

it contains two helpers:

You can use `discourse_theme new PATH` to crate a new blank theme, the CLI will guide you through the process.

You can use `discourse_theme watch PATH` to monitor your theme or component for changes, when changed the program will synchronize the theme or component to your Discourse of choice.

## Contributing

Bug reports and pull requests are welcome at [Meta Discourse](https://meta.discourse.org). This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the DiscourseTheme project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/SamSaffron/discourse_theme/blob/master/CODE_OF_CONDUCT.md).
