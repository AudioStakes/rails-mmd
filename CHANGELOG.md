# Changelog

## 0.1.0

Initial release.

- Generate Mermaid ER and class diagrams from explicitly configured Rails model domains.
- Include primary and foreign key attributes and supported direct, through, polymorphic, and HABTM associations. See the [support matrix](docs/active-record-association-support.md) for limits.
- Write validated render plans and structured diagnostics alongside diagrams, with deterministic output and atomic file replacement.
- Verify Rails 7.2 with Ruby 4.0.6, and Rails 8.1 with Ruby 3.3.12 and 4.0.6, using real SQLite fixture applications.
