# Review type: Tests

Evaluate whether the tests would actually catch regressions in the reviewed code. Read both the code under test and the tests; map behaviors to tests before judging.

Assess:

1. **Coverage of behavior**: which changed or risky code paths have no test? List the specific untested branches, error paths, and states.
2. **Edge and negative cases**: empty, null, boundary values, large inputs, invalid input, concurrency, time and locale, permission failures.
3. **Assertion quality**: do tests assert outcomes, or just that nothing threw? Over-broad snapshot tests? Assertions on implementation details that will break on refactor?
4. **Isolation and determinism**: shared state between tests, order dependence, real network/clock/filesystem use, sleeps, randomness without seeds. Anything likely to be flaky?
5. **Mocking**: over-mocking that makes the test tautological, mocks that diverge from the real contract, missing integration coverage at important seams.
6. **Readability and maintenance**: clear arrange/act/assert, meaningful names, helpers vs. duplication, fixtures that hide what matters.
7. **Mutation check**: name two or three plausible bugs (e.g. flipped condition, off-by-one) that the current tests would NOT catch.

For missing tests, give the test name and a short sketch of what it should set up and assert.
