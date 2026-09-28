# rails-mmd Usage

Run `rails-mmd generate` from the **target Rails application's root**, with `rails-mmd` in that application's `Gemfile` (see the [quick start](../README.md)). The command loads and eager-loads the Rails app, reads metadata for selected models, builds Mermaid render plans, and publishes local artifacts. Use an environment that can boot the app and read its database schema.

## Command

```sh
RAILS_ENV=development bundle exec rails-mmd generate \
  --config rails_mmd.yml \
  --output-dir tmp/rails_mmd \
  --domain core \
  --format both \
  --fail-on-warning
```

`--config` is optional as an option, but the resolved configuration file must exist. Paths for output are relative to the application root; the output directory must stay within it. `--config` may be an absolute path.

| Option | Default | Meaning |
|---|---|---|
| `--config PATH` | `rails_mmd.yml` | Configuration file to load |
| `--output-dir DIR` | Config value, then `docs/rails_mmd` | Application-root-relative artifact directory |
| `--domain ID` | All configured domains | Render one configured domain |
| `--format er\|class\|both` | Config value, then `both` | Artifact formats to publish |
| `--fail-on-warning` | False | Return exit `1` when warning diagnostics are present |

## Minimal configuration

```yaml
version: 1
domains:
  core:
    include_models:
      - User
    exclude_models: []
output:
  directory: tmp/rails_mmd
  format: both
  attributes: keys
  direction: LR
```

Replace `User` with a named Active Record model in your app. `include_models` is required and must be nonempty. A model must be loaded and have usable table metadata. The command does not search for models automatically or install Mermaid CLI.

## Artifacts

Successful domains can publish:

- `<domain>.diagnostics.json`
- `<domain>.er.mmd`
- `<domain>.er.render_plan.json`
- `<domain>.class.mmd`
- `<domain>.class.render_plan.json`

`global.diagnostics.json` is published only for post-output invocation-scope diagnostics when applicable. Empty diagnostics files are omitted. A run replaces the managed artifacts for selected domains in the output directory; keep unrelated files separate from these names.

Blocking diagnostics usually publish diagnostics JSON when output is available and omit the affected Mermaid and render-plan artifacts. Publish failures may fall back to sanitized stderr and leave previous managed artifacts intact. Pre-output fatal failures write sanitized diagnostics to stderr and write no files.

The artifacts include application schema information and can include connection identifiers in diagnostics. Review them before sharing or committing them; use a private or ignored output directory for private schemas.

## Exit codes

| Exit | Meaning |
|---:|---|
| 0 | Success, including warning diagnostics when `--fail-on-warning` is absent |
| 1 | Warning diagnostics were present and `--fail-on-warning` was set |
| 2 | Config, output setup, Rails boot, domain, or schema probe error |
| 3 | Mermaid serialization failure or unresolved safe-token collision |
| 4 | Output write or atomic publish failure |
| 99 | Internal error |

If the command reports a Rails load failure, check that you ran it from the application's root, in its bundle, and that the selected Rails environment can boot. If a model is missing, check its constant name and whether it was loaded by Rails. Domain and association limits are described in the [support matrix](active-record-association-support.md).

`rails-mmd generate` does not invoke Mermaid CLI or any hosted service.
