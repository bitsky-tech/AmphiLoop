# Amphibious Task


## Task Description
<!-- Describe what the generated project should do, step by step. Include inputs, actions, and outputs. Be specific. -->

<!-- Example:
1. Read every `.csv` file under `~/data/inputs/` whose filename starts with `orders_`.
2. For each file, extract rows where `status == "paid"` and aggregate the `amount` column by `customer_id`.
3. Write a single summary CSV at `~/data/outputs/summary.csv` with columns: customer_id, total_amount, order_count.
-->

## Expected Output
<!-- What specific output indicates success? File names, formats, content expectations, or observable side effects. -->

<!-- Example:
A file at `~/data/outputs/summary.csv` containing one row per unique customer_id, plus a console summary printing the total number of customers and the grand total amount.
-->

## Domain References
<!-- Optional but strongly recommended. One path per line. Paths may be absolute or relative to this TASK.md.

The agents will read each reference to understand your domain. Two flavors are recognized (a single file may be either or both):

1. Operational / tool-based — teach the agent HOW to act on the environment:
   - SKILL.md files (e.g., a `bridgic-*` skill, or your own skill)
   - CLI help dumps, man pages
   - SDK / API documentation
   - Sample scripts showing correct tool usage

2. Guidance-based — teach the agent WHAT rules to follow:
   - Style guides
   - Architectural constraints and conventions
   - Domain DOs and DON'Ts
   - Known edge cases and gotchas
-->

<!-- Example:
- ~/skills/my-csv-toolkit/SKILL.md
- docs/csv-processing-cli.txt
- rules/output-format-conventions.md
-->

## Notes
<!-- This section is optional. -->
<!-- Any additional context: authentication, timing, parameterization needs, multi-step flows, known quirks, or places where human intervention is expected. -->

<!-- Example:
- Input files may be malformed; rows that fail to parse should be logged and skipped, not crash the run.
- The output path's parent directory must be created if it does not exist.
- Whether to use a dry-run mode should be a CLI parameter of the generated program.
-->
