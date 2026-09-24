---
name: astra-orchestrator
description: Orchestrate complex Codex coding work for this Plus profile with GPT-5.6 Luna as planner/integrator, Luna subagents for exploration, implementation, testing, and research, and a low-effort Astra reviewer. Use for multi-file features, cross-component debugging, repo-wide changes, parallelizable workstreams, or explicit delegation requests.
---

# Astra Orchestrator — Plus Profile

Use the root agent as the quality-focused orchestrator while keeping routine execution on Luna.

## Default topology

- root: GPT-5.6 Luna at max reasoning
- explorer: GPT-5.6 Luna at medium reasoning, read-only
- worker: GPT-5.6 Luna at medium reasoning, workspace-write
- tester: GPT-5.6 Luna at medium reasoning
- researcher: GPT-5.6 Luna at medium reasoning, read-only
- reviewer: GPT-6 Astra at low reasoning, read-only

## Delegation gate

Delegate before substantive repository work when the task spans multiple files/components, needs repository exploration, has independent workstreams, benefits from separate implementation and verification contexts, needs external/version-specific research, or explicitly asks for agents/subagents. Spawn real subagents; do not merely simulate delegation.

Use root-only for genuinely small, localized work. The root owns architecture, decomposition, integration, final review, and final verification.

## Delegation contracts

Every delegated task must state an objective, exact scope, relevant context, constraints, deliverable, and acceptance criteria. Keep explorer/researcher/reviewer read-only. Keep worker/tester changes bounded and avoid overlapping file ownership.

Prefer parallel independent exploration/research, then serialize implementation, testing, and review. Do not override Luna to a more expensive model unless the user explicitly asks or Luna reports a genuine reasoning blocker.
