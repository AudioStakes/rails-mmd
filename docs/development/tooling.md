# Ruby Tooling

Ruby repair, diagnostics, tests, coverage, and dependency audit run through Rake.
RuboCop is the only formatter and autocorrect owner.

## Commands

Run repair before diagnostics when using local hooks:

```sh
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec rake rubocop:auto_correct
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec rake
```

Read-only diagnostics do not autocorrect:

```sh
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec rake rubocop
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec rake spec
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec rake coverage
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec rake bundle:audit
```

Refresh Bundler Audit advisory data explicitly before read-only diagnostics when
network access is intended:

```sh
ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec rake bundle:audit:update
```

Set `UNDERCOVER_COMPARE` when a stacked PR should compare changed-code coverage
against a specific base branch:

```sh
UNDERCOVER_COMPARE=issue/9-bootstrap-ruby-gem-and-cli-skeleton \
  ASDF_RUBY_VERSION=4.0.5 asdf exec bundle exec rake coverage
```

Specs start SimpleCov before application code through `.rspec`. RSpec randomizes
example order and reports the seed. Focused specs fail the suite so committed
focus metadata cannot narrow CI by accident.

Use `:env` metadata for environment-isolated specs:

```ruby
it 'uses an isolated environment', env: { 'RAILS_MMD_EXAMPLE' => '1' } do
  expect(ENV.fetch('RAILS_MMD_EXAMPLE')).to eq('1')
end
```

Aruba is loaded in `spec/spec_helper.rb` for future CLI acceptance tests.
