# Documentation Instructions

Documentation holds human-readable guidance and accepted evidence, not new
machine-readable contracts.

- Do not add JSON schemas, JSON/JSONL evidence dumps, source manifests, worktree
  snapshots, validation transcripts, generated matrices, or dated agent artifacts
  under `docs/`.
- Put reusable machine-readable contracts only in `Resources/Schemas/` and make
  producers declare the applicable schema.
- Record accepted hardware observations concisely in the relevant stable page
  under `docs/testing/`; do not create a new dated report format.
- `docs/external/` is a gitignored local archive of upstream issues, pull
  requests, and patches from `./Scripts/ojd docs export-external-issues`. Do not
  rewrite archived evidence into a project-defined schema, and do not link it
  from tracked files; cite the upstream URL instead.
