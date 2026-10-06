# Review type: Architecture

Evaluate the structure of the system (or of the change in the context of the system). Explore the repository layout and key modules before judging.

Assess:

1. **Boundaries and responsibilities**: are modules/services cohesive with clear ownership? Any god objects or leaky abstractions?
2. **Coupling and dependency direction**: do dependencies point toward stable abstractions? Circular dependencies? Domain logic tangled with I/O, UI, or framework code?
3. **Layering and data flow**: is it clear where state lives and how data moves? Duplicated sources of truth?
4. **Fit for purpose**: is it over-engineered (speculative abstraction, unnecessary indirection, patterns for their own sake) or under-engineered (hard-coded assumptions that will not survive the next requirement)?
5. **Failure modes**: what happens when a dependency is slow, down, or returns garbage? Retries, timeouts, idempotency, backpressure, consistency.
6. **Scalability and performance shape**: bottlenecks, single points of failure, unbounded fan-out, chatty interfaces.
7. **Operability**: configuration, observability (logs/metrics/traces), deployability, migration and rollback story.
8. **Evolvability**: how hard is the most likely next change? Where will it hurt?

For each finding, explain the trade-off and propose a concrete alternative. Distinguish "wrong" from "different from how I would do it"; only the former is a finding.
