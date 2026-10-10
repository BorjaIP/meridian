# readme-gentle-ai-flow-diagram

Branch: feat/odd-simplification (same feature branch; no new branch needed)
Meridian task: slug readme-gentle-ai-flow-diagram in the vault project note (E:\Documents\pkm\pkm\meridian\meridian\project.md)
Checks mode: docs/diagram work, no runnable RED test applies. Test-first exception recorded; functional checks = `bash tests/run.sh`, diagram self_check.py, SVG XML validity, README relative-link check.
Delivery: part of the existing unpushed branch; push/PR is the user's decision.

## Specs

- S1: README makes sense for the ODD-based flow and states that gentle-ai (ODD + Engram) generates and tracks the work, and explains the integration: what gentle-ai produces (odd/tasks/<slug>.md, work-unit commits, Engram mirror odd/<slug>/tasks) versus what Meridian records (project.md task, Run/Trace from git, logs/, dashboard.md), the mechanism (slug passed as ODD feature name, delivery sentence, never toggles RDD, main thread), and what is NOT guaranteed (model may ignore the slug; small tasks create no ODD document; skills are instructions).
- S2: A diagram of the flow is created with the diagram-design skill, styled from the Meridian icon (monochrome, black/white), as a project profile + `.diagram-design` marker (global skill defaults untouched). Shows the human, /mdn-run steps, gentle-ai ODD, mdn-trace, /mdn-done, /mdn-archive, and the three stores (vault, repo, Engram).
- S3: The diagram is embedded in the README as SVG (renders on GitHub: no external fonts); the HTML source lives in docs/diagrams/.
- S4: This run doubles as the end-to-end example of /mdn-run on the real vault (Run/Trace/logs/dashboard).

## Tasks

- [x] R1 (S2,S3) Create style profile `meridian` from the icon (monochrome), `.diagram-design` marker, flow diagram HTML + exported SVG | route: delegated writer | commits ee209e5, 2803b2a | evidence: self_check OK, SVG XML valid, no external refs, skill working style-guide.md checksum unchanged (all re-run by parent); parent rendered the SVG with resvg-wasm (installed in scratchpad, FreeSans fallback font) and LOOKED at it: legible; refined 3 labels after viewing. NOT verified: real fonts (Avenir/Century Gothic metrics), GitHub rendering, dark-mode look (SVG has an opaque white bg rect), no verify-geometry/contrast tools in the install (checks by script written by the writer + inspection)
- [ ] R2 (S1,S3) Rewrite README (review for sense, gentle-ai integration section, embed diagram, fix limits/wording) | route: delegated writer
- [ ] R3 (S1-S3) Verify: tests/run.sh, links, SVG validity, README renders sensibly; record evidence | route: inline

## Log

- L1 (2026-10-10, user): "vale revia el readme de este proyecto para ver que tenga sentido e indica que uso Gentle-ai ahora para generar todo y como es mi integracion. * Crea un /diagram-design de como funciona ahora el flujo para documentarlo y ponerlo en el readme. * Ejecuta alguna tarea de ejemplo para probar todo el flujo"
- L2 (user): style for the diagram = derive from the Meridian icon (docs/images/icon-rounded.png: black rounded square, white hand-drawn line art, geometric caps wordmark; monochrome).
- L3: R1 done. Skill gate answered by user (icon-derived). The marker `.diagram-design` points to ~/.diagram-design/profiles/meridian.md (outside repo; a copy is in docs/diagrams/style-profile-meridian.md).
- Progress: 1/3 tasks. Next step: R2 README rewrite via delegated writer.
