# processed_data — Data Dictionary

Variable-level documentation for files in `data/processed_data/` and its subdirectories.

---

## Raw thesis CSVs (`comparator-theses/raw/[Institution]_Results_*.csv`)

Schema varies slightly by source (LAC vs. Scholaris vs. cIRcle). Fields common to most files:

| Variable | Type | Description |
|----------|------|-------------|
| `title` | character | Thesis title. |
| `abstract` | character | Thesis abstract (may be empty for some records). |
| `author` | character | Author name, typically in `Surname, Given` format. |
| `year` | integer | Year of thesis submission or publication. |
| `program` | character | Graduate programme or degree type (e.g., `MSc`, `PhD`, `masters`, `doctoral`). Field name and values vary by source. |
| `institution` | character | Institution abbreviation (added during cleaning). |
| `redirects` | character | Relative URL path used to fetch additional metadata (Scholaris sources only). |

---

## McGill intermediate files (`comparator-theses/raw/McGill_redirects.csv`, `McGill_abstracts.csv`)

Intermediate outputs of the two-stage McGill scraping process. Used only as inputs to `01-6_merge_mcgill_theses.R`; not used in any downstream stage directly.

**`McGill_redirects.csv`** (output of `01-4_scrape_mcgill_redirects.R`):

| Variable | Type | Description |
|----------|------|-------------|
| `redirects` | character | Full URL to individual McGill thesis record page. |
| `titles` | character | Thesis title from search results listing. |

**`McGill_abstracts.csv`** (output of `01-5_scrape_mcgill_abstracts.R`):

| Variable | Type | Description |
|----------|------|-------------|
| `authors` | character | Thesis author name. |
| `degree` | character | Degree type (`Masters` or `Doctoral`). |
| `abstract` | character | Thesis abstract (English only). |
| `year` | integer | Year of thesis submission. |
| `location` | character | URL of individual thesis record page (used as join key with `McGill_redirects.csv`). |

---

## Clean thesis CSVs (`comparator-theses/clean/[Institution]_clean.csv`)

Standardised output of `02_clean_theses.R`. One row per thesis.

| Variable | Type | Description |
|----------|------|-------------|
| `title` | character | Thesis title. |
| `abstract` | character | Thesis abstract (empty string if not available). |
| `author` | character | Author name as provided by the source. |
| `year` | integer | Year of thesis. |
| `program` | character | Degree level (`MSc` or `PhD`; standardised). |
| `institution` | character | Institution abbreviation (e.g., `UBC`). |
| `firstname_lastname` | character | Author name reformatted as `First Last` for OpenAlex matching. |
| `institution_fullname` | character | Full institution name from `institution_names.csv`. |

---

## Classified thesis CSVs (`comparator-theses/classified/[Institution]_classified.csv`)

Output of `03_apply_classifier.R`. Same columns as the clean CSVs, plus:

| Variable | Type | Description |
|----------|------|-------------|
| `Category` | character | Classifier prediction: `EEE` (ecology, evolution, environment) or `other`. Based on a 0.5 probability threshold. |
| `prob_EEE` | numeric | Predicted probability of EEE class (0–1) from the v2 classifier. |

---

## Training data files (`comparator-theses/training-data/`)

### Current classifier review CSVs (`v2_*.csv`)

Intermediate files used during classifier development. Key variables:

| Variable | Type | Description |
|----------|------|-------------|
| `title` | character | Thesis title. |
| `abstract` | character | Thesis abstract. |
| `label` | character | Assigned label (`EEE` or `other`); may be keyword-derived or manually assigned. |
| `confidence` | numeric | Model predicted probability (where applicable). |

*(Exact schema may vary; these files are for classifier development and not used in final analysis.)*

### Current classifier model files

| File | Contents |
|------|----------|
| `eee_text_classifier_v2.rds` | Fitted `tidymodels` workflow object. Load with `readRDS()` and apply with `predict()`. Input data must have a `combined_text` column (title + space + abstract). |
| `eee_text_classifier_v2_model_info.rds` | List with model metadata including training accuracy, feature importance, and date trained. |

---

## v1 archived files (`comparator-theses/training-data/version-1_classification/`)

All files from the original UBC-only classifier development. Not used in current analysis.

### v1 model files

| File | Contents |
|------|----------|
| `eee_text_classifier.rds` | Fitted v1 `tidymodels` workflow object (archived). |
| `eee_text_classifier_model_info.rds` | Model metadata for the v1 classifier. |

### v1 training data (`ubc_*.csv` / `.RData`)

| File pattern | Description |
|---|---|
| `ubc_thesis_data.csv` / `.RData` | Raw UBC thesis data used as the v1 training corpus. |
| `ubc_eeb_candidate_theses_for_review.csv` | Initial candidate EEE theses from UBC flagged for manual review. |
| `ubc_eeb_candidate_theses_for_review_round[1–4].csv` | Per-round review subsets (4 iterative rounds). |
| `ubc_manually_reviewed_labels_round[1–4].csv` | Manually assigned labels from each review round. |
| `ubc_thesis_data_with_manual_labels_v[1–4].csv` | Full UBC dataset with cumulative manual labels at each version. |

Key variables common to v1 review files:

| Variable | Type | Description |
|----------|------|-------------|
| `title` | character | Thesis title. |
| `abstract` | character | Thesis abstract. |
| `label` | character | Manually assigned label (`EEE` or `other`). |
| `program` | character | Graduate programme (used as a labelling signal in v1). |
