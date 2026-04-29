# scripts — README

This directory contains the main analysis scripts for the thesis classification pipeline. Scripts are numbered to reflect execution order and pipeline stage. See the root `README.md` for a full pipeline diagram.

**Notes**:
- The classifier training notebook (`thesis_classification_model_training.qmd`) and the PRISMA-style flow diagram (`thesis_classification_prisma.qmd`) are unnumbered omnibus documents in this directory.
- This directory is synced to GitHub; the `data/` directory is not.

**Author**: Jason Pither
**Last updated**: 2026-03-22

---

## Scripts

| Script | Stage | Description |
|--------|-------|-------------|
| `thesis_classification_model_training.qmd` | — Classifier training | Keyword-seeded label assignment, tidymodels TF-IDF elastic-net classifier training, semi-supervised Round 1 refinement, and final v2 model save. Render with Quarto. |
| `thesis_classification_prisma.qmd` | — Pipeline diagram | PRISMA-style flow diagram tracing thesis metadata from raw collection through cleaning, classifier training, and application to the final EEE/other predictions. Exports SVG and PDF. Render with Quarto. |
| `01-1_scrape_ubc_theses.R` | 1 — Data collection | Scrapes thesis metadata from the UBC cIRcle repository (2022–2024) using `httr2` and `rvest`. |
| `01-2_scrape_uot_uoa_theses.R` | 1 — Data collection | Scrapes thesis metadata from the University of Toronto and University of Alberta Scholaris repositories using `RSelenium`. Outputs to `raw/`. |
| `01-3_scrape_uoa_degrees.R` | 1 — Data collection | Fetches degree type (masters/doctoral) for each Alberta thesis record by following individual Scholaris record URLs. Run after `01-2`. |
| `01-4_scrape_mcgill_redirects.R` | 1 — Data collection | Scrapes thesis titles and record URLs from the McGill eScholarship repository (2022–2024) using `RSelenium`. Outputs `raw/McGill_redirects.csv`. |
| `01-5_scrape_mcgill_abstracts.R` | 1 — Data collection | Visits each McGill thesis record URL and extracts author, degree, abstract, year, and URL. Outputs `raw/McGill_abstracts.csv`. Run after `01-4`. |
| `01-6_merge_mcgill_theses.R` | 1 — Data collection | Merges `McGill_redirects.csv` (titles + URLs) with `McGill_abstracts.csv` (metadata) to produce `raw/McGill_theses.csv`. Run after `01-5`. |
| `02_clean_theses.R` | 2 — Cleaning | Reads raw thesis CSVs from `raw/` (varied formats), standardises fields, and writes one clean CSV per institution. Routes non-LDP institutions to `clean/not_used/`. |
| `03_apply_classifier.R` | 3 — Classification | Applies the v2 classifier to cleaned thesis CSVs, appending a `Category` column (`EEE` or `other`) and a `prob_EEE` column (predicted probability) to each. |

---

## Execution Order

Scripts should be run in the following sequence. Steps 01-x require a live internet connection and may take time due to rate limiting and pagination.

```
01-1  ──────────────────────┐
01-2  →  01-3  ─────────────┤  # Stage 1: Thesis data collection (streams are independent)
01-4  →  01-5  →  01-6  ───┘
                            ↓
    thesis_classification_model_training.qmd   # Classifier training (scripts/; Quarto render)
                            ↓
                            02                  # Stage 2: Clean and standardise thesis CSVs
                            ↓
                            03                  # Stage 3: Apply classifier to cleaned CSVs
```

---

## `supplemental/` subdirectory

Contains materials **not part of the active pipeline**, retained as reference material:

- **Original v1 classifier** (`02_thesis_classification_model_training_v1.qmd` and rendered `.html`): the earlier UBC-only classifier approach, superseded by `thesis_classification_model_training.qmd` at the project root.
- **Superseded McGill extraction scripts** (`01-4_McGill_thesis_metadata_extraction.R`, `01-5_McGill_thesis_extraction.R`): earlier versions of the McGill scraping steps, superseded when the step numbering was corrected.
- **Orphaned utility** (`00_extract_institution_names.R`): early utility to extract institution abbreviations from the LDP roster; output not used in the current pipeline.

See `supplemental/README.md` for details.

---

## Notes

- All scripts use `here::here()` for path construction; the working directory must be the project root (`LDP_thesis_classification/`).
- Scripts 01-2, 01-4, and 01-5 are defaulted to Firefox and geckodriver and configured for `RSelenium`.
