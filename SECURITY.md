# Security

## Reporting a vulnerability

Please do not put credentials, private application code, database contents, or
exploit details in a public issue or pull request.

Use [GitHub private vulnerability reporting](https://github.com/AudioStakes/rails-mmd/security/advisories/new)
to send a suspected vulnerability to the maintainer privately.

If the private form is unavailable, open an
[issue](https://github.com/AudioStakes/rails-mmd/issues/new) asking the maintainer
for a private reporting channel. Include only that request, with no sensitive
details, and wait for a private channel before sharing the report.

Once a private channel is established, include the affected commit or version,
Ruby and Rails versions, expected and actual behavior, and a minimal reproduction
using synthetic data. There is no guaranteed response time or published security
backport policy yet.

## Running rails-mmd safely

`rails-mmd generate` loads the target application's `config/environment.rb` and
eager-loads its Ruby code in the current process. Initializers and application
code run with your operating-system permissions, environment, and database
credentials. Use only applications and configuration you trust. Prefer a local
development environment with a disposable database; application startup can have
side effects even though rails-mmd inspects schema metadata rather than records.

The tool writes artifacts under the application directory and does not upload
them. Application startup code may still contact services. The YAML configuration
uses safe loading, and output paths are checked against the application root;
these checks do not sandbox application code.

Generated diagrams and JSON artifacts contain model, table, column, and
relationship names. Treat them as application documentation that may be
confidential. Review artifacts and console output before sharing them or pasting
them into an online Mermaid viewer. Diagnostic redaction is a limited safeguard,
not a guarantee that every secret is removed; application logs are outside its
control.
