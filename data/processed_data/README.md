# processed_data — README

This directory contains thesis metadata at various stages of processing and classifier model files. See `data-dictionary.md` in this directory for variable-level documentation.

**Author**: Jason Pither
**Last updated**: 2026-03-22

---

## Contents

### `comparator-theses/` subdirectory

Thesis metadata at successive processing stages, organised by institution.

#### `raw/` — Raw scraped and intermediate files

All raw input files for the cleaning stage. Produced by Stage 1 scripts (01-1 through 01-6).

| File pattern | Source | Producing script | Description |
|---|---|---|---|
| `UBC_Results_*.csv` | UBC cIRcle | `01-1_scrape_ubc_theses.R` | UBC thesis metadata scraped from cIRcle. |
| `Toronto_Results_Scholaris.csv` | U of T Scholaris | `01-2_scrape_uot_uoa_theses.R` | Toronto thesis metadata scraped via Scholaris. |
| `Alberta_Results_Scholaris.csv` | U of A Scholaris | `01-2_scrape_uot_uoa_theses.R` | Alberta thesis metadata without degree field. |
| `Alberta_Results_Scholaris_with_degrees.csv` | U of A Scholaris | `01-3_scrape_uoa_degrees.R` | Alberta metadata with degree type added. |
| `[Other]_Results_*.csv` | Library and Archives Canada | Manual download | Thesis metadata for all other institutions, downloaded in bulk from LAC (date in filename). Institutions: Carleton, Guelph, Manitoba, Montreal, Queens, Regina, SFU, Waterloo, WLU. |
| `McGill_redirects.csv` | McGill eScholarship | `01-4_scrape_mcgill_redirects.R` | Intermediate: McGill thesis titles and record URLs. Input to both `01-5` and `01-6`. |
| `McGill_abstracts.csv` | McGill eScholarship | `01-5_scrape_mcgill_abstracts.R` | Intermediate: McGill per-record metadata (author, degree, abstract, year). Input to `01-6`. |
| `McGill_theses.csv` | McGill eScholarship | `01-6_merge_mcgill_theses.R` | Final merged McGill thesis data (titles + abstracts + metadata). |

#### `clean/`

Cleaned and standardised thesis CSVs, one per institution. Produced by `02_clean_theses.R`.

#### `classified/`

Per-institution CSVs with appended `Category` (`EEE` or `other`) and `prob_EEE` (classifier probability) columns. Produced by `03_apply_classifier.R` using the saved v2 model.

#### `training-data/`

Current classifier model and associated review files.

| File | Description |
|------|-------------|
| `eee_text_classifier_v2.rds` | v2 classifier model (current; multi-institution, keyword-seeded). |
| `eee_text_classifier_v2_model_info.rds` | Supplementary model metadata for the v2 classifier. |
| `v2_eee_keyword_sample_for_review.csv` | Sample of keyword-labelled EEE theses used for manual review. |
| `v2_manually_reviewed_labels_round1.csv` | Manually corrected labels from round 1 review. |
| `v2_round1_high_conf_EEE_for_review.csv` | High-confidence EEE predictions flagged for review. |
| `v2_round1_uncertain_for_review.csv` | Uncertain predictions flagged for manual review. |

#### `training-data/version-1_classification/`

Archived v1 classifier model and all UBC-specific training data used in its development.

| File | Description |
|------|-------------|
| `eee_text_classifier.rds` | v1 classifier model (archived; trained on UBC data only). |
| `eee_text_classifier_model_info.rds` | Supplementary model metadata for the v1 classifier. |
| `ubc_thesis_data.csv` / `.RData` | Raw UBC thesis data used as the v1 training corpus. |
| `ubc_eeb_candidate_theses_for_review.csv` | Initial candidate EEE theses from UBC flagged for manual review. |
| `ubc_eeb_candidate_theses_for_review_round[1–4].csv` | Per-round review subsets used iteratively during v1 development. |
| `ubc_manually_reviewed_labels_round[1–4].csv` | Manually assigned labels from each review round. |
| `ubc_thesis_data_with_manual_labels_v[1–4].csv` | Full UBC thesis dataset with cumulative manual labels at each version. |

---

## Data Sources

- Library and Archives Canada: bulk download (public, max 5000 records per query).
- UBC cIRcle and Scholaris (U of T, U of A): web-scraped using `rvest` / `RSelenium`.
- McGill eScholarship: web-scraped using `RSelenium`.
---

## Notes

- Thesis date range covered: 2022–2024 (approximate; varies by institution and collection date).
- Data collection dates: 2026-01-23 (LAC), 2026-01-29 (Scholaris).
- The v2 classifier is used for all downstream analysis; v1 is retained for reference only.
