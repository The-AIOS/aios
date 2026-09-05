# agents/aios/commerce/ — customer-facing commerce agents

Agents for designing and building **commerce agents that ship inside a product** — a shopping assistant serving buyers, or a merchant-side operations agent serving the business. Distinct from the rest of this directory, which holds workers that run *inside* the operator's vault.

| Agent | Use it for |
|---|---|
| [`commerce-agent-architect`](./commerce-agent-architect.md) | Designing, building, tuning or reviewing a shopping or merchant agent — architecture, latency and cost, production hardening |

**Why one agent and not a catalog.** The published guidance this bundle draws from makes a specific architectural claim: *one model in a standard agent loop, with skills for the long tail* — explicitly rejecting decomposition into multiple cooperating sub-agents for the conversational path. Shipping a `shopping-agent` and a `merchant-agent` as separate bundled workers would contradict the very argument they would be implementing. The two shapes are **modes of one architecture**, and the agent handles both.

Add more here only when a genuinely different *architecture* appears — not when a new commerce use case does.
