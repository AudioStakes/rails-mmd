# rails-mmd Usage

`rails-mmd generate` reads a Rails project, builds P0 render plans, serializes
Mermaid text, and publishes local artifacts under the configured output
directory.

## Command

```sh
ASDF_RUBY_VERSION=4.0.6 asdf exec bundle exec exe/rails-mmd generate \
  --config rails_mmd.yml \
  --output-dir docs/rails_mmd \
  --domain core \
  --format both \
  --fail-on-warning
```

All options are optional except that the resolved config file must exist.

| option | default | meaning |
|---|---|---|
| `--config PATH` | `rails_mmd.yml` | config file to load |
| `--output-dir DIR` | config value, then `docs/rails_mmd` | project-root-relative artifact directory |
| `--domain ID` | all configured domains | render one configured domain |
| `--format er\|class\|both` | config value, then `both` | artifact formats to publish |
| `--fail-on-warning` | false | return exit `1` when warning diagnostics are present |

## Minimal Config

```yaml
version: 1
domains:
  core:
    include_models:
      - User
    exclude_models: []
output:
  directory: docs/rails_mmd
  format: both
  attributes: keys
  direction: LR
```

## Artifacts

Successful domains can publish:

- `<domain>.diagnostics.json`
- `<domain>.er.mmd`
- `<domain>.er.render_plan.json`
- `<domain>.class.mmd`
- `<domain>.class.render_plan.json`

`global.diagnostics.json` is published only for post-output invocation-scope
diagnostics when applicable. Empty diagnostics files are omitted.

Blocking diagnostics usually publish diagnostics JSON when output is available
and omit the affected Mermaid and render-plan artifacts. Publish failures may
fall back to sanitized stderr and leave previous managed artifacts intact.
Pre-output fatal failures write sanitized diagnostics to stderr and write no
files.

## Exit Codes

| exit | meaning |
|---:|---|
| 0 | success, including warning diagnostics when `--fail-on-warning` is absent |
| 1 | warning diagnostics were present and `--fail-on-warning` was set |
| 2 | config, output setup, Rails boot, domain, or schema probe error |
| 3 | Mermaid serialization failure or unresolved safe-token collision |
| 4 | output write or atomic publish failure |
| 99 | internal error |

`rails-mmd generate` does not invoke Mermaid CLI, hosted CI, Node, TypeScript,
or network services.
