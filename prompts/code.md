# Review type: Code

Focus on whether this code is correct and maintainable. Check, in priority order:

1. **Correctness**: logic errors, off-by-one, wrong conditions, unhandled null/empty/zero/negative/huge inputs, incorrect assumptions about callers or data, broken invariants.
2. **Error handling**: swallowed errors, misleading messages, missing cleanup on failure paths, partial-failure states, retries without bounds.
3. **Concurrency and state**: races, shared mutable state, ordering assumptions, re-entrancy, async misuse (unawaited work, blocking calls on async paths).
4. **Resources**: leaks (files, sockets, memory, handles, subscriptions), unbounded growth, missing timeouts.
5. **Performance**: hot-path inefficiency, accidental quadratic work, N+1 calls, needless allocation or I/O. Only flag what plausibly matters.
6. **Readability and idiom**: does it match the surrounding codebase's conventions? Unclear names, dead code, duplicated logic that already exists elsewhere in the repo, comments that lie.
7. **Integration**: does the change break existing callers, public behavior, configs, or migrations?

Mention security issues if you spot them, but a dedicated security review exists; do not pad this review with speculative ones.
