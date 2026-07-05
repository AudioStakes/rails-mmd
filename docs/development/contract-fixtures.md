# Contract Fixtures

The schema and Mermaid fixtures are executable P0 contract scaffolding. They
describe the JSON payloads and text artifacts future implementation issues must
produce, without implementing Rails loading, config loading, IR generation,
render-plan generation, or Mermaid serialization in this issue.

Mermaid CLI validation is intentionally deferred. This repository remains
Ruby-only, and no non-Ruby development dependency has been approved for P0
contract scaffolding.

Render-plan attribute fixtures must include the serializer-facing lowercase
`type` field. Serializers consume that field directly and must not infer types
from IR, schema metadata, or Rails runtime objects.
