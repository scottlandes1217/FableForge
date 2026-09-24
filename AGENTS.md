# Codex project instructions

For complex coding tasks, use the `astra-orchestrator` skill when its trigger conditions match.

The root agent owns architecture, decomposition, integration, and final verification. Prefer specialized Luna subagents for bounded exploration, implementation, testing, and research, with Astra reserved for low-effort independent review.

Do not delegate trivial work merely for parallelism. Do not let multiple implementation agents edit the same files without explicit ownership boundaries. User instructions always take precedence.

## Verification before reporting completion

For every UI, visual asset, animation, camera, inventory, equipment, or interaction change, do not report the work as complete based on compilation alone. Launch an isolated preview or editor test using the current build, exercise the changed path, capture a screenshot or equivalent runtime evidence, and inspect it for alignment, scale, readability, clipping, missing assets, and unexpected fallback styling. For interaction changes, test both the accepted and rejected paths and repeat the action afterward. If a live visual check cannot be completed, state that limitation explicitly instead of claiming the result is done.
