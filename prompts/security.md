# Review type: Security

Perform a security audit. Think like an attacker: for each finding, state the attacker's position (unauthenticated remote, authenticated user, local user, malicious dependency, etc.), the concrete exploit path, and the impact.

Check:

1. **Injection**: SQL/NoSQL, shell/command, template, LDAP, XPath, header/log injection, XSS (reflected, stored, DOM), prompt injection where untrusted text reaches an LLM with tools.
2. **AuthN / AuthZ**: missing or bypassable checks, IDOR, privilege escalation, session/token handling, CSRF, insecure defaults.
3. **Secrets**: hard-coded credentials, keys or tokens in code, configs, logs, error messages, or test fixtures.
4. **Input handling**: path traversal, unsafe file uploads, deserialization of untrusted data, XML external entities, regex DoS, integer overflow, unchecked sizes.
5. **Network**: SSRF, open redirects, missing TLS verification, overly permissive CORS.
6. **Cryptography**: weak or home-grown algorithms, static IVs/salts, predictable randomness, misuse of hashing for passwords.
7. **Data exposure**: PII or sensitive data in logs, telemetry, caches, URLs, or client-visible errors.
8. **Supply chain and execution**: risky new dependencies, `eval`/dynamic code execution, unpinned downloads piped to a shell, overly broad file or process permissions.

Rate each finding with the shared severity scale and add an exploitability note (*easy / moderate / hard*). Do not report theoretical issues with no reachable path. Say explicitly when the reviewed scope looks clean.
