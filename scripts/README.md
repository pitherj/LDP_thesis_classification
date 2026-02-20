# scripts — README

This directory contains the main analysis scripts for the thesis classification pipeline. Scripts are numbered to reflect execution order. See the root `README.md` for a full pipeline diagram.

**Note**: Scripts 00 and 04 process private LDP data and are stored in `data/raw_data/scripts/` rather than here. This directory is synced to GitHub; the `data/` directory is not.

**Author**: Jason Pither
**Last updated**: 2026-02-20

---

## Scripts

| Script | Description |
|--------|-------------|
| `01-1_extract_ubc_thesis_data_from_circle.R` | Scrapes thesis metadata from the UBC cIRcle repository (2022–2024) using `httr2` and `rvest`. |
| `01-2_extract_uot_uoa_theses.R` | Scrapes thesis metadata from the University of Toronto and University of Alberta Scholaris repositories using `RSelenium`. |
| `01-3_extract_uoa_thesis_degrees.R` | Fetches degree type (masters/doctoral) for each Alberta thesis record by following individual Scholaris record URLs. Run after `01-2`. |
| `02_thesis_classification_model_training.qmd` | **v1 classifier (archived).** Trains a text classifier on UBC thesis data using Zoology/Botany programme membership as positive labels. Retained for reference only. |
| `03_thesis_classification_model_training_v2.qmd` | **v2 classifier (current).** Trains the classifier using a keyword-seeding approach across multiple institutions, with a manual review round. Produces `eee_text_classifier_v2.rds`. |
| `05_clean_thesis_data.R` | Reads raw thesis CSVs (varied formats), standardises fields, and writes one clean CSV per institution. Routes non-LDP institutions to `clean/not_used/`. |
| `06_apply_classifier.R` | Applies the v2 classifier to cleaned thesis CSVs, appending a `Category` column (`EEE` or `other`) to each. |
| `07_get_candidate_control_authors.R` | Identifies EEE thesis authors as comparator candidates and retrieves their first-author publications from OpenAlex using a two-phase API approach. |

---

## Execution Order

Scripts should be run in the following sequence. Steps 01-x require a live internet connection and may take time due to rate limiting and pagination.

```
01-1  →  01-2  →  01-3        # Thesis data collection (web scraping)
         ↓
         03                   # Classifier training (Quarto render)
         ↓
         05  →  06            # Clean and classify theses
         ↓
         07                   # Retrieve comparator author publications
```

Scripts 00 and 04 (in `data/raw_data/scripts/`) must be run before 07, as `07` depends on `LDP_author_publications.csv`.

---

## Notes

- All scripts use `here::here()` for path construction; the working directory must be the project root (`thesis_classification/`).
- Scripts 01-2 requires Firefox and geckodriver to be installed and configured for `RSelenium`.
- Script 07 uses the OpenAlex API polite pool (registered email required; set via `options(openalexR.mailto = ...)`). It writes a checkpoint file (`comparator_checkpoint.rds`) after each institution, allowing interrupted runs to resume.
- The v1 Quarto script (02) is archived and not part of the active pipeline.
