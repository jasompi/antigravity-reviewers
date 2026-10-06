# Review type: Design (API / interface / UX)

Evaluate the design of the surfaces other people touch: public APIs, library interfaces, CLI commands and flags, configuration formats, HTTP/RPC endpoints, data schemas, and user-facing UI or messages.

Assess:

1. **Consistency**: naming, casing, argument order, and conventions consistent internally and with the platform/ecosystem norms?
2. **Clarity and ergonomics**: is the common case easy and the dangerous case hard? Sensible defaults? Surprising behavior? Too many knobs?
3. **Contracts and errors**: are inputs, outputs, nullability, and side effects clear? Are errors typed or structured, actionable, and consistent? Do failures leave things in a known state?
4. **Compatibility and evolution**: breaking changes, versioning strategy, room for extension without breaking callers, deprecation path.
5. **Abstraction level**: does the interface leak implementation details? Is it too low-level or too magical for its audience?
6. **Documentation**: are behavior, examples, and edge cases documented where users will look?
7. **UX and accessibility (for UI)**: information hierarchy, feedback and loading/error states, keyboard and screen-reader support, contrast, localization readiness.

For each finding, show the current usage from a caller's point of view and a suggested improved shape.
