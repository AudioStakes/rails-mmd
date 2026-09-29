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

## Configuration reference

Unknown keys are rejected. The [configuration schema](../schemas/config.schema.json) is the machine-readable reference.

| Key | Default | Allowed values / meaning |
|---|---|---|
| `version` | Required | Integer `1` |
| `domains` | Required | One or more named model groups |
| `domains.<id>.include_models` | Required | Nonempty list of exact Ruby constant names, such as `User` or `Billing::Invoice` |
| `domains.<id>.exclude_models` | `[]` | Exact model names to remove from that domain's included set |
| `output.directory` | `docs/rails_mmd` | Relative path inside the application root |
| `output.format` | `both` | `er`, `class`, or `both` |
| `output.attributes` | `keys` | `keys` shows primary and foreign keys; `none` hides attributes |
| `output.direction` | `LR` | `LR` left to right, `RL` right to left, `TB` top to bottom, `BT` bottom to top |

Domain IDs use lowercase letters and digits, start with a letter, and may contain single underscores between nonempty segments: `core` and `billing_v2` are valid; `Core`, `billing-v2`, and `billing__v2` are not. Model names are case-sensitive; wildcards and regular expressions are not supported. Each domain renders independently. Include both endpoints of a relationship in the same domain to display it.

CLI values for `--output-dir` and `--format` override their YAML equivalents. `--domain` selects one configured domain; omitting it renders all domains. `attributes` and `direction` are YAML settings only.

## Viewing a generated diagram

The `.mmd` files contain Mermaid source, not an image or an HTML page. Open them in a local viewer with Mermaid support, or copy the contents of one file into a Markdown file between these fences:

````markdown
```mermaid
<paste the contents of core.er.mmd here, replacing this line>
```
````

Open that Markdown file in a viewer that renders Mermaid code blocks. An ordinary text editor displays the source only. The illustrative diagram in the [README](../README.md) demonstrates this embedding. Keep private application diagrams in a local viewer; copying them to a hosted editor shares their schema content with that service.

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
| 0 | success, including warning diagnostics when `--fail-on-warning` is absent |
| 1 | warning diagnostics were present and `--fail-on-warning` was set |
| 2 | config, output setup, Rails boot, domain, or schema probe error |
| 3 | Mermaid serialization failure or unresolved safe-token collision |
| 4 | output write or atomic publish failure |
| 99 | internal error |

CLI argument errors also return exit `1` before generation starts. These include unknown options, unexpected positional arguments, missing option values, and invalid boolean values. Check stderr for the argument error.

If the command reports a Rails load failure, check that you ran it from the application's root, in its bundle, and that the selected Rails environment can boot. If a model is missing, check its constant name and whether it was loaded by Rails. Domain and association limits are described in the [support matrix](active-record-association-support.md).

## Troubleshooting

Start with `bundle exec rails-mmd generate --help` to verify that the executable is available in the application's bundle. After generation, inspect `<domain>.diagnostics.json` in the output directory, along with stderr. A warning can omit an unsupported relationship while still returning exit `0`; use `--fail-on-warning` when omissions should fail a check.

| Symptom | What to check |
|---|---|
| Bundler cannot find `rails-mmd` | Add the gem to the target application's Gemfile and run `bundle install` there. |
| Unknown option, unexpected argument, or invalid boolean | Compare the command with `bundle exec rails-mmd generate --help`. Pass model names through YAML, not positional arguments. Use `--fail-on-warning` as a flag, or set it explicitly to `true` or `false`. |
| Configuration file not found or invalid | Create `rails_mmd.yml` in the application root; compare keys and values with the configuration reference above. |
| Rails boot or database metadata error | Use the application's usual setup instructions to prepare its dependencies, environment, and database. Run `RAILS_ENV=development bundle exec rails runner 'puts Rails.env'` to isolate boot failures. |
| Model not found | Use its full constant name, including namespace, and ensure Rails eager loading can load it. |
| Expected relationship is missing | Include both models in the same domain, inspect warning diagnostics, and check the support matrix for unsupported options. |
| Output directory rejected | Use an application-root-relative path such as `tmp/rails_mmd`; paths escaping the root are rejected. |
| Diagram appears as text | Use a Mermaid-capable viewer or the Markdown embedding instructions above. |

`rails-mmd generate` does not invoke Mermaid CLI or any hosted service.
