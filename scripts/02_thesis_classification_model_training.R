# ==============================================================================
# Semi-Supervised Ecology, Evolution, Environment (EEE) Classification
# Title and Abstract Only
# Program field used for labeling only, NOT as model feature
# ==============================================================================

library(tidyverse)
library(tidymodels)
library(textrecipes)
library(stopwords)
library(here)
library(future)
library(future.apply)
library(vip)

# ==============================================================================
# 1. DATA LOADING
# ==============================================================================

thesis_data <- readr::read_csv(here::here("data", "processed_data", "comparator-theses", "training-data", "ubc_thesis_data.csv"))

# Fields required for training: Title, Description (Description), Program

# Combine text fields that will be used for model building
thesis_data <- thesis_data %>%
  mutate(combined_text = paste(Title, Description, sep = " "))

# ==============================================================================
# 2. CREATE LABELS USING PROGRAM FIELD (NOT A MODEL FEATURE)
# ==============================================================================

# change the "Program (Theses)" field to "Program"

thesis_data <- thesis_data %>%
  rename(Program = "Program (Theses)")

# Find unique values of the "Program (Theses)" field
# sort alphabetically

unique_programs <- sort(unique(thesis_data$Program))

# Declare Programs that would definitely be categorized as EEE

positive_programs <- c("Zoology", "Botany")

# Definite non-EEE Programs - CUSTOMIZE THIS LIST

# first extract all Programs with distinguishing words
business <- unique_programs[grep("Business", unique_programs)]
music  <- unique_programs[grep("Music", unique_programs)]
engineering  <- unique_programs[grep("Engineering", unique_programs)]
education <- unique_programs[grep("Education", unique_programs)]
arts <- unique_programs[grep("Art", unique_programs)]
human <- unique_programs[grep("Human", unique_programs)]
physics <- unique_programs[grep("Physics", unique_programs)]
pharma <- unique_programs[grep("Pharma", unique_programs)]
culture <- unique_programs[grep("Cultur", unique_programs)]
health <- unique_programs[grep("Health", unique_programs)]
medical <- unique_programs[grep("Medic", unique_programs)]
psych <- unique_programs[grep("Psychology", unique_programs)]

# all Programs with "Studies", except "Integrated Studies in Land and Food Systems"

studies <- unique_programs[grep("Studies", unique_programs)]
studies <- studies[-grep("Food", studies)]

# all Programs with "Science", except a handful

science <- unique_programs[grep("Science", unique_programs)]
science <- science[-sapply(c("Plant", "Earth", "Soil"), function(x){grep(x,science)})]

# now get vector of obvious Programs

others <- c("Anthropology", "Architecture", "Astronomy", "Chemistry", "Classics",
            "Economics", "English", "French", "Geophysics", "History", "Journalism",
            "Kinesiology", "Mathematics", "Law", "Nursing", "Neuroscience", "Philosophy", "Planning",
            "Sociology", "Statistics", "Surgery", "Theatre", "Applied Animal Biology",
            "Social Work", "Children's Literature", "Occupational and Environmental Hygiene",
            "Classical and Near Eastern Archaeology", "Cell and Developmental Biology",
            "Teaching English as a Second Language","Interdisciplinary Oncology",
            "Linguistics", "Gender, Race, Sexuality and Social Justice",
            "Landscape Architecture", "Measurement, Evaluation and Research Methodology",
            "Creative Writing", "Biochemistry and Molecular Biology")

negative_programs <- c(
  business, music, engineering, education, arts, human, physics, pharma,
  culture, health, medical, psych, studies, science, others)

# take stock of remaining Programs, which are ambiguous wrt EEE
# noting that positive_programs are definitely EEE

setdiff(unique_programs, c(negative_programs, positive_programs))

# [1] "Geography"                                   "Bioinformatics"                              "Earth and Environmental Sciences"           
# [4] "Resources, Environment and Sustainability"   "Biology"                                     "Oceanography"                               
# [7] "Biochemistry and Molecular Biology"          "Forestry"                                    "Plant Science"                              
# [10] "Integrated Studies in Land and Food Systems" "Microbiology and Immunology"                 "Oceans and Fisheries"                       
# [13] "Soil Science" 

# Create labels - Program is ONLY used here for labeling
thesis_data <- thesis_data %>%
  mutate(
    label_status = case_when(
      Program %in% positive_programs ~ "positive",
      Program %in% negative_programs ~ "negative",
      TRUE ~ "unlabeled"
    ),
    category = case_when(
      label_status == "positive" ~ "EEE",
      label_status == "negative" ~ "other",
      TRUE ~ NA_character_
    ),
    category = factor(category, levels = c("EEE", "other"))
  )

# Review labeling
labeling_summary <- thesis_data %>%
  count(label_status, Program) %>%
  arrange(label_status, desc(n))

print(labeling_summary)

# Check numbers
thesis_data %>%
  count(label_status)

# ==============================================================================
# 3. PREPARE TRAINING DATA (RELIABLE LABELS ONLY)
# ==============================================================================

labeled_data <- thesis_data %>%
  filter(!is.na(category)) %>%
  # Select only TEXT features, NOT Program
  # use DOI as unique identifier
  select(DOI, combined_text, category, Title, Description)

# Check class balance
labeled_data %>% count(category)

# Balance classes if needed (downsample majority class)
set.seed(123)

min_class_size <- min(table(labeled_data$category))

balanced_data <- labeled_data %>%
  group_by(category) %>%
  slice_sample(n = min_class_size) %>%
  ungroup()

cat("Training with", nrow(balanced_data), "balanced examples\n")
cat("  EEE:", sum(balanced_data$category == "EEE"), "\n")
cat("  Other:", sum(balanced_data$category == "other"), "\n")

# Train/test split, use 80 / 20
data_split <- initial_split(balanced_data, prop = 0.80, strata = category)
train_data <- training(data_split)
test_data <- testing(data_split)

# Cross-validation folds
cv_folds <- vfold_cv(train_data, v = 5, strata = category)

# ==============================================================================
# 4. TEXT-ONLY MODEL RECIPE
# ==============================================================================

# Recipe uses ONLY combined_text - no Program field
text_recipe <- recipe(category ~ combined_text, data = train_data) %>%
  step_tokenize(combined_text) %>%
  step_stopwords(combined_text, 
                 custom_stopword_source = stopwords::stopwords("en")) %>%
  step_tokenfilter(combined_text, min_times = 5, max_tokens = 5000) %>%
  step_tfidf(combined_text) %>%
  step_normalize(all_predictors())

# ==============================================================================
# 5. MODEL SPECIFICATION AND WORKFLOW
# ==============================================================================

logistic_spec <- logistic_reg(
  penalty = tune(),
  mixture = tune()
) %>%
  set_engine("glmnet") %>%
  set_mode("classification")

thesis_workflow <- workflow() %>%
  add_recipe(text_recipe) %>%
  add_model(logistic_spec)

# ==============================================================================
# 6. HYPERPARAMETER TUNING
# ==============================================================================

tune_grid <- grid_regular(
  penalty(range = c(-5, 0)),
  mixture(range = c(0, 1)),
  levels = 10
)

plan(multisession, workers = parallel::detectCores() - 1)

tune_results <- thesis_workflow %>%
  tune_grid(
    resamples = cv_folds,
    grid = tune_grid,
    metrics = metric_set(accuracy, roc_auc, sens, spec),
    control = control_grid(save_pred = TRUE)
  )

# Return to sequential processing when done (optional but good practice)
plan(sequential)

# Select best model (use AUC for better generalization)
best_params <- tune_results %>%
  select_best(metric = "roc_auc")

cat("\nBest hyperparameters:\n")
print(best_params)

# Finalize and fit
final_workflow <- thesis_workflow %>%
  finalize_workflow(best_params)

final_fit <- final_workflow %>%
  fit(data = balanced_data)

# ==============================================================================
# 7. EVALUATE ON HELD-OUT TEST SET
# ==============================================================================

test_predictions <- final_fit %>%
  predict(test_data) %>%
  bind_cols(
    final_fit %>% predict(test_data, type = "prob")
  ) %>%
  bind_cols(test_data)

# Performance metrics
test_metrics <- test_predictions %>%
  metrics(truth = category, estimate = .pred_class)

cat("\nTest set performance:\n")
print(test_metrics)

# Confusion matrix
cat("\nConfusion matrix:\n")
test_predictions %>%
  conf_mat(truth = category, estimate = .pred_class) %>%
  print()

# Class-specific metrics
cat("\nSensitivity (EEE recall):", 
    test_predictions %>% 
      sens(truth = category, estimate = .pred_class) %>% 
      pull(.estimate), "\n")

cat("Specificity (Other recall):", 
    test_predictions %>% 
      spec(truth = category, estimate = .pred_class) %>% 
      pull(.estimate), "\n")

# ==============================================================================
# 8. PREDICT ON ALL UNLABELED DATA
# ==============================================================================

# Get all unlabeled theses (ambiguous Programs)
unlabeled_data <- thesis_data %>%
  filter(label_status == "unlabeled") %>%
  select(DOI, Program, Title, Description, combined_text)

cat("\nPredicting on", nrow(unlabeled_data), "unlabeled theses\n")

# Generate predictions
unlabeled_predictions <- final_fit %>%
  predict(unlabeled_data, type = "prob") %>%
  bind_cols(
    final_fit %>% predict(unlabeled_data, type = "class")
  ) %>%
  bind_cols(unlabeled_data)

# ==============================================================================
# 9. IDENTIFY HIGH-CONFIDENCE EEE CANDIDATES FOR REVIEW
# ==============================================================================

# Focus on high-confidence EEE predictions
eeb_candidates <- unlabeled_predictions %>%
  filter(.pred_class == "EEE") %>%
  arrange(desc(.pred_EEE)) %>%
  select(DOI, Program, Title, Description, .pred_EEE, .pred_class) %>%
  arrange(Program, Title)

cat("\nFound", nrow(eeb_candidates), "candidate EEE theses in unlabeled data\n")
# 264 candidates

# Export for manual review
readr::write_csv(eeb_candidates, here::here("data", "processed_data", "comparator-theses", "training-data", "ubc_eeb_candidate_theses_for_review_round1.csv"))

# ==============================================================================
# 10. STRATIFIED SAMPLING FOR EFFICIENT MANUAL REVIEW
# ==============================================================================

# ***NOTE*** This section was not done - no need.

# Sample candidates across confidence levels for manual review
# review_sample <- eeb_candidates %>%
#   mutate(
#     confidence_bin = cut(.pred_EEE, 
#                          breaks = c(0.5, 0.7, 0.85, 0.95, 1.0),
#                          labels = c("moderate", "high", "very_high", "extreme"))
#   ) %>%
#   group_by(confidence_bin) %>%
#   slice_sample(n = min(50, n())) %>%
#   ungroup() %>%
#   arrange(desc(.pred_EEE))
# 
# write_csv(review_sample, here::here("data", "processed_data", "comparator-theses", "training-data", "stratified_review_sample.csv"))
# 
# cat("\nCreated stratified sample of", nrow(review_sample), 
#     "theses for manual review\n")

# ==============================================================================
# 11. TOP PREDICTIVE TERMS (MODEL INTERPRETATION)
# ==============================================================================

# ***NOTE*** This section was not done - optional

# Extract most important terms
# top_terms <- final_fit %>%
#   extract_fit_parsnip() %>%
#   vi(lambda = best_params$penalty) %>%
#   mutate(
#     Direction = if_else(Sign == "POS", "Other", "EEE"),  # Fixed
#     abs_importance = abs(Importance)
#   ) %>%
#   group_by(Direction) %>%
#   slice_max(abs_importance, n = 20) %>%
#   ungroup()
# 
# cat("\nTop 20 terms predicting EEE:\n")
# top_terms %>%
#   filter(Direction == "EEE") %>%
#   select(Variable, Importance) %>%
#   print(n = 20)
# 
# cat("\nTop 20 terms predicting Other:\n")
# top_terms %>%
#   filter(Direction == "Other") %>%
#   select(Variable, Importance) %>%
#   print(n = 20)
# 
# # Visualize
# top_terms %>%
#   ggplot(aes(x = Importance, y = reorder(Variable, Importance), fill = Direction)) +
#   geom_col() +
#   facet_wrap(~Direction, scales = "free_y") +
#   labs(Title = "Top 20 Predictive Terms by Category",
#        y = NULL,
#        x = "Coefficient") +
#   theme_minimal()

# ggsave("top_predictive_terms.png", width = 12, height = 8)

# ==============================================================================
# 12. MANUAL REVIEW OF RECORDS
# ==============================================================================

####################
## ROUND 1 MANUAL REVIEW
####################

# now, go through spreadsheet of "eeb_candidates" ("ubc_eeb_candidate_theses_for_review.csv"), 
# there are 264 records in the first manual run
# created and saved csv "ubc_manually_reviewed_labels_round1.csv"

manual_labels_round1 <- readr::read_csv(here::here("data", "processed_data",
           "comparator-theses", "training-data", 
           "ubc_manually_reviewed_labels_round1.csv")) %>%
  select(DOI, verified_category) # Keep only needed columns

# all 264 were originally classified as EEE, but now:

table(manual_labels_round1$verified_category)
# EEE other 
# 208    56 

# Merge with original data
thesis_data_v2 <- thesis_data %>%
  left_join(manual_labels_round1, by = "DOI") %>%
  mutate(
    # Update category: use verified label if available, otherwise keep original
    category = coalesce(
      factor(verified_category, levels = c("EEE", "other")), 
      category
    ),
    # Update label_status: mark manually reviewed theses as labeled
    label_status = if_else(
      !is.na(verified_category), 
      if_else(verified_category == "EEE", "positive", "negative"),
      label_status
    )
  )

# Check the expansion
cat("Original labeled theses:", sum(!is.na(thesis_data$category)), "\n")
# Original labeled theses: 3712
cat("Expanded labeled theses:", sum(!is.na(thesis_data_v2$category)), "\n")
# Expanded labeled theses: 3976
cat("Newly added labels:", sum(!is.na(thesis_data_v2$category)) - sum(!is.na(thesis_data$category)), "\n")
# Newly added labels: 264

# Save for future use
write_csv(thesis_data_v2, here::here("data", "processed_data",
          "comparator-theses", "training-data",
          "ubc_thesis_data_with_manual_labels_v1.csv"))

#####
##### Now re-run the training again
##### 

labeled_data_v2 <- thesis_data_v2 %>%
  filter(!is.na(category)) %>%
  select(DOI, combined_text, category, Title, Description)

# Check class balance
labeled_data_v2 %>% count(category)

# Balance classes if needed (downsample majority class)
set.seed(1234)

min_class_size_v2 <- min(table(labeled_data_v2$category))

balanced_data_v2 <- labeled_data_v2 %>%
  group_by(category) %>%
  slice_sample(n = min_class_size_v2) %>%
  ungroup()

cat("Training with", nrow(balanced_data_v2), "balanced examples\n")
# Training with 680 balanced examples

cat("  EEE:", sum(balanced_data_v2$category == "EEE"), "\n")
# EEE: 340

cat("  Other:", sum(balanced_data_v2$category == "other"), "\n")
# Other: 340

# Train/test split, use 80 / 20
data_split_v2 <- initial_split(balanced_data_v2, prop = 0.80, strata = category)
train_data_v2 <- training(data_split_v2)
test_data_v2 <- testing(data_split_v2)

# Cross-validation folds
cv_folds_v2 <- vfold_cv(train_data_v2, v = 5, strata = category)

###-----

# Recipe uses ONLY combined_text - no Program field
text_recipe_v2 <- recipe(category ~ combined_text, data = train_data_v2) %>%
  step_tokenize(combined_text) %>%
  step_stopwords(combined_text, 
                 custom_stopword_source = stopwords::stopwords("en")) %>%
  step_tokenfilter(combined_text, min_times = 5, max_tokens = 5000) %>%
  step_tfidf(combined_text) %>%
  step_normalize(all_predictors())

###-----

logistic_spec_v2 <- logistic_reg(
  penalty = tune(),
  mixture = tune()
) %>%
  set_engine("glmnet") %>%
  set_mode("classification")

thesis_workflow_v2 <- workflow() %>%
  add_recipe(text_recipe_v2) %>%
  add_model(logistic_spec_v2)

###-----

tune_grid_v2 <- grid_regular(
  penalty(range = c(-5, 0)),
  mixture(range = c(0, 1)),
  levels = 10
)

plan(multisession, workers = parallel::detectCores() - 1)

tune_results_v2 <- thesis_workflow_v2 %>%
  tune_grid(
    resamples = cv_folds_v2,
    grid = tune_grid_v2,
    metrics = metric_set(accuracy, roc_auc, sens, spec),
    control = control_grid(save_pred = TRUE)
  )

# Return to sequential processing when done (optional but good practice)
plan(sequential)

# Select best model (use AUC for better generalization)
best_params_v2 <- tune_results_v2 %>%
  select_best(metric = "roc_auc")

cat("\nBest hyperparameters:\n")
print(best_params_v2)

# Finalize and fit
final_workflow_v2 <- thesis_workflow_v2 %>%
  finalize_workflow(best_params_v2)

final_fit_v2 <- final_workflow_v2 %>%
  fit(data = balanced_data_v2)

###-----
# predict

test_predictions_v2 <- final_fit_v2 %>%
  predict(test_data_v2) %>%
  bind_cols(
    final_fit_v2 %>% predict(test_data_v2, type = "prob")
  ) %>%
  bind_cols(test_data_v2)

# Performance metrics
test_metrics_v2 <- test_predictions_v2 %>%
  metrics(truth = category, estimate = .pred_class)

cat("\nTest set performance:\n")
print(test_metrics_v2)

# Confusion matrix
cat("\nConfusion matrix:\n")
test_predictions_v2 %>%
  conf_mat(truth = category, estimate = .pred_class) %>%
  print()

# Class-specific metrics
cat("\nSensitivity (EEE recall):", 
    test_predictions_v2 %>% 
      sens(truth = category, estimate = .pred_class) %>% 
      pull(.estimate), "\n")

cat("Specificity (Other recall):", 
    test_predictions_v2 %>% 
      spec(truth = category, estimate = .pred_class) %>% 
      pull(.estimate), "\n")

###-----

# Get all unlabeled theses (ambiguous Programs) using v2 data
unlabeled_data_v2 <- thesis_data_v2 %>%
  filter(label_status == "unlabeled") %>%
  select(DOI, Program, Title, Description, combined_text)

cat("\nPredicting on", nrow(unlabeled_data_v2), "unlabeled theses\n")
# Predicting on 296 unlabeled theses

# Generate predictions
unlabeled_predictions_v2 <- final_fit_v2 %>%
  predict(unlabeled_data_v2, type = "prob") %>%
  bind_cols(
    final_fit_v2 %>% predict(unlabeled_data_v2, type = "class")
  ) %>%
  bind_cols(unlabeled_data_v2)

### ----
# Focus on high-confidence EEE predictions
eeb_candidates_v2 <- unlabeled_predictions_v2 %>%
  filter(.pred_class == "EEE") %>%
  arrange(desc(.pred_EEE)) %>%
  select(DOI, Program, Title, Description, .pred_EEE, .pred_class) %>%
  arrange(Program, Title)

cat("\nFound", nrow(eeb_candidates_v2), "candidate EEE theses in unlabeled data\n")
# 103 candidates

# Export for manual review
readr::write_csv(eeb_candidates_v2, here::here("data", "processed_data", "comparator-theses", "training-data", "ubc_eeb_candidate_theses_for_review_round2.csv"))


####################
## ROUND 2 MANUAL REVIEW
####################

# Go through spreadsheet of "eeb_candidates" second round ("ubc_eeb_candidate_theses_for_review_round2.csv"), 
# there are 103 records in the second manual run
# created and saved csv "ubc_manually_reviewed_labels_round2.csv"

# Load manually reviewed labels from Round 2
manual_labels_round2 <- readr::read_csv(here::here("data", "processed_data",
                                                   "comparator-theses", "training-data", 
                                                   "ubc_manually_reviewed_labels_round2.csv")) %>%
  
  select(DOI, verified_category) # Keep only needed columns

# Check what was reviewed in Round 2
table(manual_labels_round2$verified_category)

# EEE other 
# 66    37 

# Merge with thesis_data_v2 to create thesis_data_v3
thesis_data_v3 <- thesis_data_v2 %>%
  select(-verified_category) %>%  # Remove old column if it exists
  left_join(manual_labels_round2, by = "DOI") %>%
  mutate(
    # Update category: use verified label if available, otherwise keep original
    category = coalesce(
      factor(verified_category, levels = c("EEE", "other")), 
      category
    ),
    # Update label_status: mark manually reviewed theses as labeled
    label_status = if_else(
      !is.na(verified_category), 
      if_else(verified_category == "EEE", "positive", "negative"),
      label_status
    )
  )


# Check the expansion
cat("Original labeled theses (v1):", sum(!is.na(thesis_data$category)), "\n")
# Original labeled theses (v1): 3712 

cat("After Round 1 (v2):", sum(!is.na(thesis_data_v2$category)), "\n")
# After Round 1 (v2): 3976

cat("After Round 2 (v3):", sum(!is.na(thesis_data_v3$category)), "\n")
# After Round 2 (v3): 4079

cat("Newly added in Round 2:", sum(!is.na(thesis_data_v3$category)) - sum(!is.na(thesis_data_v2$category)), "\n")
# Newly added in Round 2: 103

# Save for future use
write_csv(thesis_data_v3, here::here("data", "processed_data",
                                     "comparator-theses", "training-data",
                                     "ubc_thesis_data_with_manual_labels_v2.csv"))

#####
##### Now re-run the training again, round 2
##### 
set.seed(12345)

labeled_data_v3 <- thesis_data_v3 %>%
  filter(!is.na(category)) %>%
  select(DOI, combined_text, category, Title, Description)

# Check class balance
labeled_data_v3 %>% count(category)

# Balance classes if needed (downsample majority class)

min_class_size_v3 <- min(table(labeled_data_v3$category))

balanced_data_v3 <- labeled_data_v3 %>%
  group_by(category) %>%
  slice_sample(n = min_class_size_v3) %>%
  ungroup()

cat("Training with", nrow(balanced_data_v3), "balanced examples\n")
# Training with 812 balanced examples

cat("  EEE:", sum(balanced_data_v3$category == "EEE"), "\n")
# EEE: 406

cat("  Other:", sum(balanced_data_v3$category == "other"), "\n")
# Other: 406

# Train/test split, use 80 / 20
data_split_v3 <- initial_split(balanced_data_v3, prop = 0.80, strata = category)
train_data_v3 <- training(data_split_v3)
test_data_v3 <- testing(data_split_v3)

# Cross-validation folds
cv_folds_v3 <- vfold_cv(train_data_v3, v = 5, strata = category)

###-----

# Recipe uses ONLY combined_text - no Program field
text_recipe_v3 <- recipe(category ~ combined_text, data = train_data_v3) %>%
  step_tokenize(combined_text) %>%
  step_stopwords(combined_text, 
                 custom_stopword_source = stopwords::stopwords("en")) %>%
  step_tokenfilter(combined_text, min_times = 5, max_tokens = 5000) %>%
  step_tfidf(combined_text) %>%
  step_normalize(all_predictors())

###-----

logistic_spec_v3 <- logistic_reg(
  penalty = tune(),
  mixture = tune()
) %>%
  set_engine("glmnet") %>%
  set_mode("classification")

thesis_workflow_v3 <- workflow() %>%
  add_recipe(text_recipe_v3) %>%
  add_model(logistic_spec_v3)

###-----

tune_grid_v3 <- grid_regular(
  penalty(range = c(-5, 0)),
  mixture(range = c(0, 1)),
  levels = 10
)

plan(multisession, workers = parallel::detectCores() - 1)

tune_results_v3 <- thesis_workflow_v3 %>%
  tune_grid(
    resamples = cv_folds_v3,
    grid = tune_grid_v3,
    metrics = metric_set(accuracy, roc_auc, sens, spec),
    control = control_grid(save_pred = TRUE)
  )

# Return to sequential processing when done (optional but good practice)
plan(sequential)

# Select best model (use AUC for better generalization)
best_params_v3 <- tune_results_v3 %>%
  select_best(metric = "roc_auc")

cat("\nBest hyperparameters:\n")
print(best_params_v3)

# Finalize and fit
final_workflow_v3 <- thesis_workflow_v3 %>%
  finalize_workflow(best_params_v3)

final_fit_v3 <- final_workflow_v3 %>%
  fit(data = balanced_data_v3)

###-----
# predict

test_predictions_v3 <- final_fit_v3 %>%
  predict(test_data_v3) %>%
  bind_cols(
    final_fit_v3 %>% predict(test_data_v3, type = "prob")
  ) %>%
  bind_cols(test_data_v3)

# Performance metrics
test_metrics_v3 <- test_predictions_v3 %>%
  metrics(truth = category, estimate = .pred_class)

cat("\nTest set performance:\n")
print(test_metrics_v3)
# A tibble: 2 × 3
# .metric  .estimator .estimate
# <chr>    <chr>          <dbl>
#   1 accuracy binary         0.994
# 2 kap      binary         0.988

# Confusion matrix
cat("\nConfusion matrix:\n")
test_predictions_v3 %>%
  conf_mat(truth = category, estimate = .pred_class) %>%
  print()
# Truth
# Prediction EEE other
# EEE    82     1
# other   0    81

# Class-specific metrics
cat("\nSensitivity (EEE recall):", 
    test_predictions_v3 %>% 
      sens(truth = category, estimate = .pred_class) %>% 
      pull(.estimate), "\n")
# Sensitivity (EEE recall): 1 

cat("Specificity (Other recall):", 
    test_predictions_v3 %>% 
      spec(truth = category, estimate = .pred_class) %>% 
      pull(.estimate), "\n")
# Specificity (Other recall): 0.9878049

###-----

# Get all unlabeled theses (ambiguous Programs) using v3 data
unlabeled_data_v3 <- thesis_data_v3 %>%
  filter(label_status == "unlabeled") %>%
  select(DOI, Program, Title, Description, combined_text)

cat("\nPredicting on", nrow(unlabeled_data_v3), "unlabeled theses\n")
# Predicting on 193 unlabeled theses

# Generate predictions
unlabeled_predictions_v3 <- final_fit_v3 %>%
  predict(unlabeled_data_v3, type = "prob") %>%
  bind_cols(
    final_fit_v3 %>% predict(unlabeled_data_v3, type = "class")
  ) %>%
  bind_cols(unlabeled_data_v3)

### ----
# Focus on high-confidence EEE predictions
eeb_candidates_v3 <- unlabeled_predictions_v3 %>%
  filter(.pred_class == "EEE") %>%
  arrange(desc(.pred_EEE)) %>%
  select(DOI, Program, Title, Description, .pred_EEE, .pred_class) %>%
  arrange(Program, Title)

cat("\nFound", nrow(eeb_candidates_v3), "candidate EEE theses in unlabeled data\n")
# Found 19 candidate EEE theses in unlabeled data

# Export for manual review
readr::write_csv(eeb_candidates_v3, here::here("data", "processed_data", "comparator-theses", "training-data", "ubc_eeb_candidate_theses_for_review_round3.csv"))

####################
## ROUND 3 REVIEW
####################

set.seed(123456)

# Go through spreadsheet of "eeb_candidates" third round ("ubc_eeb_candidate_theses_for_review_round3.csv"), 
# there are 19 records in the second manual run
# created and saved csv "ubc_manually_reviewed_labels_round3.csv"

# Load manually reviewed labels from Round 2
manual_labels_round3 <- readr::read_csv(here::here("data", "processed_data",
                                                   "comparator-theses", "training-data", 
                                                   "ubc_manually_reviewed_labels_round3.csv")) %>%
  
  select(DOI, verified_category) # Keep only needed columns

# Check what was reviewed in Round 2
table(manual_labels_round3$verified_category)

# EEE other 
# 6    13 

# Merge with thesis_data_v3 to create thesis_data_v4
thesis_data_v4 <- thesis_data_v3 %>%
  select(-verified_category) %>%  # Remove old column if it exists
  left_join(manual_labels_round3, by = "DOI") %>%
  mutate(
    # Update category: use verified label if available, otherwise keep original
    category = coalesce(
      factor(verified_category, levels = c("EEE", "other")), 
      category
    ),
    # Update label_status: mark manually reviewed theses as labeled
    label_status = if_else(
      !is.na(verified_category), 
      if_else(verified_category == "EEE", "positive", "negative"),
      label_status
    )
  )


# Check the expansion
cat("Original labeled theses (v1):", sum(!is.na(thesis_data$category)), "\n")
# Original labeled theses (v1): 3712

cat("After Round 1 (v2):", sum(!is.na(thesis_data_v2$category)), "\n")
# After Round 1 (v2): 3976

cat("After Round 2 (v3):", sum(!is.na(thesis_data_v3$category)), "\n")
# After Round 2 (v3): 4079

cat("After Round 3 (v4):", sum(!is.na(thesis_data_v4$category)), "\n")
# After Round 3 (v4): 4098

cat("Newly added in Round 3:", sum(!is.na(thesis_data_v4$category)) - sum(!is.na(thesis_data_v3$category)), "\n")
# Newly added in Round 3: 19

# Save for future use
write_csv(thesis_data_v4, here::here("data", "processed_data",
                                     "comparator-theses", "training-data",
                                     "ubc_thesis_data_with_manual_labels_v3.csv"))

#####
##### Now re-run the training again, round 3
##### 

labeled_data_v4 <- thesis_data_v4 %>%
  filter(!is.na(category)) %>%
  select(DOI, combined_text, category, Title, Description)

# Check class balance
labeled_data_v4 %>% count(category)

# Balance classes if needed (downsample majority class)

min_class_size_v4 <- min(table(labeled_data_v4$category))

balanced_data_v4 <- labeled_data_v4 %>%
  group_by(category) %>%
  slice_sample(n = min_class_size_v4) %>%
  ungroup()

cat("Training with", nrow(balanced_data_v4), "balanced examples\n")
# Training with 824 balanced examples

cat("  EEE:", sum(balanced_data_v4$category == "EEE"), "\n")
# EEE: 412

cat("  Other:", sum(balanced_data_v4$category == "other"), "\n")
# Other: 412

# Train/test split, use 80 / 20
data_split_v4 <- initial_split(balanced_data_v4, prop = 0.80, strata = category)
train_data_v4 <- training(data_split_v4)
test_data_v4 <- testing(data_split_v4)

# Cross-validation folds
cv_folds_v4 <- vfold_cv(train_data_v4, v = 5, strata = category)

###-----

# Recipe uses ONLY combined_text - no Program field
text_recipe_v4 <- recipe(category ~ combined_text, data = train_data_v4) %>%
  step_tokenize(combined_text) %>%
  step_stopwords(combined_text, 
                 custom_stopword_source = stopwords::stopwords("en")) %>%
  step_tokenfilter(combined_text, min_times = 5, max_tokens = 5000) %>%
  step_tfidf(combined_text) %>%
  step_normalize(all_predictors())

###-----

logistic_spec_v4 <- logistic_reg(
  penalty = tune(),
  mixture = tune()
) %>%
  set_engine("glmnet") %>%
  set_mode("classification")

thesis_workflow_v4 <- workflow() %>%
  add_recipe(text_recipe_v4) %>%
  add_model(logistic_spec_v4)

###-----

tune_grid_v4 <- grid_regular(
  penalty(range = c(-5, 0)),
  mixture(range = c(0, 1)),
  levels = 10
)

plan(multisession, workers = parallel::detectCores() - 1)

tune_results_v4 <- thesis_workflow_v4 %>%
  tune_grid(
    resamples = cv_folds_v4,
    grid = tune_grid_v4,
    metrics = metric_set(accuracy, roc_auc, sens, spec),
    control = control_grid(save_pred = TRUE)
  )

# Return to sequential processing when done (optional but good practice)
plan(sequential)

# Select best model (use AUC for better generalization)
best_params_v4 <- tune_results_v4 %>%
  select_best(metric = "roc_auc")

cat("\nBest hyperparameters:\n")
print(best_params_v4)

# Finalize and fit
final_workflow_v4 <- thesis_workflow_v4 %>%
  finalize_workflow(best_params_v4)

final_fit_v4 <- final_workflow_v4 %>%
  fit(data = balanced_data_v4)

###-----
# predict

test_predictions_v4 <- final_fit_v4 %>%
  predict(test_data_v4) %>%
  bind_cols(
    final_fit_v4 %>% predict(test_data_v4, type = "prob")
  ) %>%
  bind_cols(test_data_v4)

# Performance metrics
test_metrics_v4 <- test_predictions_v4 %>%
  metrics(truth = category, estimate = .pred_class)

cat("\nTest set performance:\n")
print(test_metrics_v4)
# A tibble: 2 × 3
# .metric  .estimator .estimate
# <chr>    <chr>          <dbl>
#   1 accuracy binary         0.994
# 2 kap      binary         0.988

# Confusion matrix
cat("\nConfusion matrix:\n")
test_predictions_v4 %>%
  conf_mat(truth = category, estimate = .pred_class) %>%
  print()
# Truth
# Prediction EEE other
# EEE    83     1
# other   0    82

# Class-specific metrics
cat("\nSensitivity (EEE recall):", 
    test_predictions_v4 %>% 
      sens(truth = category, estimate = .pred_class) %>% 
      pull(.estimate), "\n")
# Sensitivity (EEE recall): 1 

cat("Specificity (Other recall):", 
    test_predictions_v4 %>% 
      spec(truth = category, estimate = .pred_class) %>% 
      pull(.estimate), "\n")

# Specificity (Other recall): 0.9879518

###-----

# Get all unlabeled theses (ambiguous Programs) using v4 data
unlabeled_data_v4 <- thesis_data_v4 %>%
  filter(label_status == "unlabeled") %>%
  select(DOI, Program, Title, Description, combined_text)

cat("\nPredicting on", nrow(unlabeled_data_v4), "unlabeled theses\n")
# Predicting on 174 unlabeled theses

# Generate predictions
unlabeled_predictions_v4 <- final_fit_v4 %>%
  predict(unlabeled_data_v4, type = "prob") %>%
  bind_cols(
    final_fit_v4 %>% predict(unlabeled_data_v4, type = "class")
  ) %>%
  bind_cols(unlabeled_data_v4)

### ----
# Focus on high-confidence EEE predictions
eeb_candidates_v4 <- unlabeled_predictions_v4 %>%
  filter(.pred_class == "EEE") %>%
  arrange(desc(.pred_EEE)) %>%
  select(DOI, Program, Title, Description, .pred_EEE, .pred_class) %>%
  arrange(Program, Title)

cat("\nFound", nrow(eeb_candidates_v4), "candidate EEE theses in unlabeled data\n")

# 9 candidates

# Export for manual review
readr::write_csv(eeb_candidates_v4, here::here("data", "processed_data", "comparator-theses", "training-data", "ubc_eeb_candidate_theses_for_review_round4.csv"))

####################
## ROUND 4 REVIEW
####################
set.seed(1234)

# Go through spreadsheet of "eeb_candidates" third round ("ubc_eeb_candidate_theses_for_review_round4.csv"), 
# there are 6 records in the second manual run
# created and saved csv "ubc_manually_reviewed_labels_round3.csv"

# Load manually reviewed labels from Round 2
manual_labels_round4 <- readr::read_csv(here::here("data", "processed_data",
                                                   "comparator-theses", "training-data", 
                                                   "ubc_manually_reviewed_labels_round4.csv")) %>%
  select(DOI, verified_category) # Keep only needed columns

# Check what was reviewed in Round 2
table(manual_labels_round4$verified_category)

# EEE other 
# 1     8  

# Merge with thesis_data_v4 to create thesis_data_v5
thesis_data_v5 <- thesis_data_v4 %>%
  select(-verified_category) %>%  # Remove old column if it exists
  left_join(manual_labels_round4, by = "DOI") %>%
  mutate(
    # Update category: use verified label if available, otherwise keep original
    category = coalesce(
      factor(verified_category, levels = c("EEE", "other")), 
      category
    ),
    # Update label_status: mark manually reviewed theses as labeled
    label_status = if_else(
      !is.na(verified_category), 
      if_else(verified_category == "EEE", "positive", "negative"),
      label_status
    )
  )


# Check the expansion
cat("Original labeled theses (v1):", sum(!is.na(thesis_data$category)), "\n")
# Original labeled theses (v1): 3712

cat("After Round 1 (v2):", sum(!is.na(thesis_data_v2$category)), "\n")
# After Round 1 (v2): 3976 

cat("After Round 2 (v3):", sum(!is.na(thesis_data_v3$category)), "\n")
# After Round 2 (v3): 4079

cat("After Round 3 (v4):", sum(!is.na(thesis_data_v4$category)), "\n")
# After Round 3 (v4): 4098

cat("After Round 4 (v5):", sum(!is.na(thesis_data_v5$category)), "\n")
# After Round 4 (v5): 4107

cat("Newly added in Round 4:", sum(!is.na(thesis_data_v5$category)) - sum(!is.na(thesis_data_v4$category)), "\n")
# Newly added in Round 4: 9

# Save for future use
write_csv(thesis_data_v5, here::here("data", "processed_data",
                                     "comparator-theses", "training-data",
                                     "ubc_thesis_data_with_manual_labels_v4.csv"))

#####
##### Now re-run the training again
##### 

labeled_data_v5 <- thesis_data_v5 %>%
  filter(!is.na(category)) %>%
  select(DOI, combined_text, category, Title, Description)

# Check class balance
labeled_data_v5 %>% count(category)

# Balance classes if needed (downsample majority class)

min_class_size_v5 <- min(table(labeled_data_v5$category))

balanced_data_v5 <- labeled_data_v5 %>%
  group_by(category) %>%
  slice_sample(n = min_class_size_v5) %>%
  ungroup()

cat("Training with", nrow(balanced_data_v5), "balanced examples\n")
# Training with 826 balanced examples

cat("  EEE:", sum(balanced_data_v5$category == "EEE"), "\n")
# EEE: 413

cat("  Other:", sum(balanced_data_v5$category == "other"), "\n")
# Other: 413

# Train/test split, use 80 / 20
data_split_v5 <- initial_split(balanced_data_v5, prop = 0.80, strata = category)
train_data_v5 <- training(data_split_v5)
test_data_v5 <- testing(data_split_v5)

# Cross-validation folds
cv_folds_v5 <- vfold_cv(train_data_v5, v = 5, strata = category)

###-----

# Recipe uses ONLY combined_text - no Program field
text_recipe_v5 <- recipe(category ~ combined_text, data = train_data_v5) %>%
  step_tokenize(combined_text) %>%
  step_stopwords(combined_text, 
                 custom_stopword_source = stopwords::stopwords("en")) %>%
  step_tokenfilter(combined_text, min_times = 5, max_tokens = 5000) %>%
  step_tfidf(combined_text) %>%
  step_normalize(all_predictors())

###-----

logistic_spec_v5 <- logistic_reg(
  penalty = tune(),
  mixture = tune()
) %>%
  set_engine("glmnet") %>%
  set_mode("classification")

thesis_workflow_v5 <- workflow() %>%
  add_recipe(text_recipe_v5) %>%
  add_model(logistic_spec_v5)

###-----

tune_grid_v5 <- grid_regular(
  penalty(range = c(-5, 0)),
  mixture(range = c(0, 1)),
  levels = 10
)

plan(multisession, workers = parallel::detectCores() - 1)

tune_results_v5 <- thesis_workflow_v5 %>%
  tune_grid(
    resamples = cv_folds_v5,
    grid = tune_grid_v5,
    metrics = metric_set(accuracy, roc_auc, sens, spec),
    control = control_grid(save_pred = TRUE)
  )

# Return to sequential processing when done (optional but good practice)
plan(sequential)

# Select best model (use AUC for better generalization)
best_params_v5 <- tune_results_v5 %>%
  select_best(metric = "roc_auc")

cat("\nBest hyperparameters:\n")
print(best_params_v5)

# Finalize and fit
final_workflow_v5 <- thesis_workflow_v5 %>%
  finalize_workflow(best_params_v5)

final_fit_v5 <- final_workflow_v5 %>%
  fit(data = balanced_data_v5)

###-----
# predict

test_predictions_v5 <- final_fit_v5 %>%
  predict(test_data_v5) %>%
  bind_cols(
    final_fit_v5 %>% predict(test_data_v5, type = "prob")
  ) %>%
  bind_cols(test_data_v5)

# Performance metrics
test_metrics_v5 <- test_predictions_v5 %>%
  metrics(truth = category, estimate = .pred_class)

cat("\nTest set performance:\n")
print(test_metrics_v5)
# A tibble: 2 × 3
# .metric  .estimator .estimate
# <chr>    <chr>          <dbl>
#   1 accuracy binary             1
# 2 kap      binary             1

# Confusion matrix
cat("\nConfusion matrix:\n")
test_predictions_v5 %>%
  conf_mat(truth = category, estimate = .pred_class) %>%
  print()
# Truth
# Prediction EEE other
# EEE    83     0
# other   0    83

# Class-specific metrics
cat("\nSensitivity (EEE recall):", 
    test_predictions_v5 %>% 
      sens(truth = category, estimate = .pred_class) %>% 
      pull(.estimate), "\n")
# Sensitivity (EEE recall): 1 

cat("Specificity (Other recall):", 
    test_predictions_v5 %>% 
      spec(truth = category, estimate = .pred_class) %>% 
      pull(.estimate), "\n")
# Specificity (Other recall): 1

###-----

# Get all unlabeled theses (ambiguous Programs) using v2 data
unlabeled_data_v5 <- thesis_data_v5 %>%
  filter(label_status == "unlabeled") %>%
  select(DOI, Program, Title, Description, combined_text)

cat("\nPredicting on", nrow(unlabeled_data_v5), "unlabeled theses\n")
# Predicting on 165 unlabeled theses

# Generate predictions
unlabeled_predictions_v5 <- final_fit_v5 %>%
  predict(unlabeled_data_v5, type = "prob") %>%
  bind_cols(
    final_fit_v5 %>% predict(unlabeled_data_v5, type = "class")
  ) %>%
  bind_cols(unlabeled_data_v5)

### ----
# Focus on high-confidence EEE predictions
eeb_candidates_v5 <- unlabeled_predictions_v5 %>%
  filter(.pred_class == "EEE") %>%
  arrange(desc(.pred_EEE)) %>%
  select(DOI, Program, Title, Description, .pred_EEE, .pred_class) %>%
  arrange(Program, Title)

cat("\nFound", nrow(eeb_candidates_v5), "candidate EEE theses in unlabeled data\n")
# 

# 5 candidates

## We'll stop here!

# ==============================================================================
# 14. SAVE MODEL FOR PRODUCTION
# ==============================================================================

# Once the final model is completed: 
# 
saveRDS(final_fit_v5, here::here("data", "processed_data",
                              "comparator-theses", "training-data",
                              "eee_text_classifier.rds"))

# Save preprocessing info
model_info <- list(
  model_file = "eee_text_classifier.rds",
  training_date = Sys.Date(),
  training_size = nrow(balanced_data_v5),
  n_eeb = sum(balanced_data_v5$category == "EEE"),
  n_other = sum(balanced_data_v5$category == "other"),
  test_accuracy = test_metrics_v5 %>%
    filter(.metric == "accuracy") %>%
    pull(.estimate),
  features = "Title + Description",
  note = "Model works on any thesis with Title & Description"
)

saveRDS(model_info, here::here("data", "processed_data",
                               "comparator-theses", "training-data",
                               "eee_text_classifier_model_info.rds"))

# cat("\nModel saved. To use on new data:\n")
# cat("  # New data must have 'Title' and 'Description' columns\n")
# cat("  new_data <- new_data %>%\n")
# cat("    mutate(combined_text = paste(Title, Description, sep = ' '))\n")
# cat("  model <- readRDS('eeb_text_classifier.rds')\n")
# cat("  predictions <- predict(model, new_data, type = 'prob')\n")
