---
name: spec-lookup
description: Search the UCIe 3.0 specification PDF (docs/Spec) by keyword/table/section and return matching excerpts with page numbers, for cross-checking RTL against the spec. Use when implementing or reviewing a state machine/datapath against UCIe behavior, resolving a TB-vs-RTL disagreement, or looking up a spec table/figure/section.
---

# spec-lookup

Find the relevant spec text fast instead of paging through a large PDF by hand. The spec is the source of truth: when it conflicts with a plan or a test, the **spec wins** and the **RTL** is what gets fixed.

## Instructions

### Step 1: Search
From the project root:

```
.claude/skills/spec-lookup/scripts/spec_search.sh "<pattern>" [context_lines]
```

- `<pattern>` is a case-insensitive regex, e.g. `Table 10-4`, `RDI.*Active`, `MBINIT`, `scrambl`, `sideband.*handshake`.
- `context_lines` (default 3) is how many lines around each hit to print.
- Output is grouped by `── page N ──` so you can cite the page and, if needed, open it precisely with the Read tool (`pages:` on the PDF) for the surrounding figure/table.

### Step 2: Read deeper if a table/figure is involved
`pdftotext` flattens tables and drops figures. When a hit lands in a table (e.g. RDI state transitions) or references a figure, open that page range directly with the Read tool's `pages` parameter on `docs/Spec/UCIe_Specification_rev3p0_ver1p0_final_2025Aug05_public_clean [website requests].pdf` to see the real layout.

### Step 3: Apply the spec, cite it
When reporting, quote the relevant clause and cite the page/table. If this resolves a TB-vs-RTL disagreement, the conclusion is to fix the RTL to match the spec, not to relax the test.

## Notes
- The script caches the extracted text under `/tmp` keyed by the PDF's mtime, so the first search pays the `pdftotext` cost once and later searches are instant.
- Known anchors: RDI transitions live around Table 10-4; the PHY interface summary is also mirrored in `docs/Spec/PHY_Interface.md`.
- Read-only; touches nothing in the repo.
