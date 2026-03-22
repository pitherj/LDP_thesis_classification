# supplemental — README

This directory contains the **original (v1) classification approach** for the thesis classifier pipeline. It is retained as reference material, analogous to supplemental information in a publication — available for transparency and reproducibility but not part of the active pipeline.

**Author**: Jason Pither
**Last updated**: 2026-03-22

---

## Why this approach was superseded

The v1 classifier was trained exclusively on UBC thesis data, using Zoology and Botany program membership as the source of positive (EEE) labels. This created two problems:

1. **Narrow positive labels**: The model learned "Zoology/Botany vocabulary" rather than generalizable EEE signal, since only those two programs were used as anchors.
2. **Poorly separated negatives**: The negative training examples (Business, Medicine, Physics, etc.) were lexically very distant from EEE, so the model never learned to distinguish EEE from near-neighbour fields — geology, physical geography, and environmental social science — which produced false positives in practice.

The current classifier (`thesis_classification_model_training.qmd` at the project root) addresses these issues by using keyword-seeded labels across all seven comparator institutions, with explicit near-neighbour negatives and a manual review round. See the introduction section of that document for a full comparison.

---

## Contents

### Original classifier (v1)

| File | Description |
|---|---|
| `02_thesis_classification_model_training_v1.qmd` | Original Quarto notebook documenting the v1 classifier development. Trained on UBC data only; uses program membership (Zoology/Botany) as positive labels. |
| `02_thesis_classification_model_training_v1.html` | Rendered HTML output of the v1 notebook. Self-contained; can be opened in any browser without re-running the notebook. |

The fitted v1 model object and all UBC training data files associated with its development are archived in `data/processed_data/comparator-theses/training-data/version-1_classification/` (private; not synced to GitHub).

### Superseded McGill extraction scripts

At an early stage of development the McGill scraping steps were numbered differently. When the numbering was corrected, the old-numbered copies were retained here rather than deleted.

| File | Description |
|---|---|
| `01-4_McGill_thesis_metadata_extraction.R` | Earlier version of `01-5_scrape_mcgill_abstracts.R`. Visits McGill record URLs to extract author/abstract/year/degree. Superseded; uses a hardcoded start index and lacks a script header. |
| `01-5_McGill_thesis_extraction.R` | Earlier version of `01-4_scrape_mcgill_redirects.R`. Scrapes thesis titles and redirect URLs from McGill eScholarship. Superseded by the current `01-4` script. |

### Orphaned utility

| File | Description |
|---|---|
| `00_extract_institution_names.R` | Early utility that extracted unique institution abbreviations from the LDP roster CSV. Its output (`LDP_unique-institutions_2020_2022.csv`) is not consumed by any current pipeline step. Retained here for reference. |

---

## Notes

- None of these files are executed as part of the active pipeline.
- The v1 model is **not** used by `03_apply_classifier.R` or any downstream script; the current model (`eee_text_classifier_v2.rds`) is used instead.
