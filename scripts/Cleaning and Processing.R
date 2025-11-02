#read data

install.packages("readxl") 
library(readxl)
excel_sheets("d:/R_par/Rawd/pf2_1.xlsx")
excel_sheets("d:/R_par/Rawd/pf2_5.xlsx")

# read clean version of PF2.5 

data_pf2_5 <- read_excel("d:/R_par/Rawd/pf2_5.xlsx", sheet = 4)
View(data_pf2_5)
names(data_pf2_5)[1:2] <- c("Country", "Year")
colnames(data_pf2_5)

#read clean version of PF2.1

data_pf2_1A <- read_excel("d:/R_par/Rawd/pf2_1.xlsx", sheet = 1, skip = 10)
data_pf2_1B <- read_excel("d:/R_par/Rawd/pf2_1.xlsx", sheet = 2, skip = 10)
names(data_pf2_1A)[1] <- c("Country")
names(data_pf2_1B)[1] <- c("Country")
head(data_pf2_1A)
head(data_pf2_1B)

# Merge by Country
library(dplyr)
library(purrr)

merged <- list(
  data_pf2_1A,
  data_pf2_1B,
  data_pf2_5 %>% filter(Year == 2024 | is.na(Year))
) %>%
  reduce(full_join, by = "Country")
View(merged)

#calculate gender gap by Total paid leave available to mothers/ fathers Full-rate equivalent (weeks)

merged$Mother_FRE <- as.numeric(gsub("[^0-9\\.]", "", merged$`Total paid leave available to mothersFull-rate equivalent (weeks)`))
merged$Father_FRE <- as.numeric(gsub("[^0-9\\.]", "", merged$`Total paid leave reserved for fathersFull-rate equivalent (weeks)`))
merged$GenderGapFRE <- merged$Mother_FRE - merged$Father_FRE

#calculate independent variable
merged <- merged %>%
  mutate(across(c(Mother_FRE, Father_FRE, Father_specific_Parleave,
                  Parental_protected, Parental_paid),
                ~as.numeric(gsub("[^0-9\\.]", "", as.character(.)))))
merged <- merged %>%
  mutate(
    GenderGapFRE = Mother_FRE - Father_FRE,
    Father_quota_share = Father_specific_Parleave / (Mother_FRE + Father_FRE),
    Mother_payment_ratio = Parental_paid / Parental_protected
  )

# Clean merged dataset
merged_clean <- merged %>%
  # Drop summary/aggregate rows and empty country names
  filter(
    !is.na(Country),
    !Country %in% c(
      "EU average", "OECD average",
      "Sources: See tables PF2.1.C-PF2.1.E"
    )
  ) %>%
  # Remove countries with no key variables (too many NAs)
  filter(
    !(is.na(GenderGapFRE) & is.na(Father_quota_share) & is.na(Mother_payment_ratio))
  )

# drop rows with all policy data missing
merged_clean <- merged_clean %>%
  filter(
    rowSums(is.na(select(., GenderGapFRE, Father_quota_share, Mother_payment_ratio))) < 3
  )

merged_clean <- merged_clean %>%
  mutate(
    # Handle division safely: avoid Inf or NaN
    Father_quota_share = ifelse(
      (Mother_FRE + Father_FRE) > 0,
      Father_specific_Parleave / (Mother_FRE + Father_FRE),
      NA
    ),
    # Replace Inf with NA just in case
    Father_quota_share = ifelse(is.infinite(Father_quota_share), NA, Father_quota_share),
    
    # Cap at 1 since "paid ≤ protected"
    Mother_payment_ratio = pmin(Mother_payment_ratio, 1, na.rm = TRUE)
  )

summary(merged_clean[, c("GenderGapFRE", "Father_quota_share", "Mother_payment_ratio")])

merged_clean <- merged_clean %>%
  mutate(
    Father_quota_share = ifelse(Father_quota_share > 1, 1, Father_quota_share)
  )
summary(merged_clean$Father_quota_share)

# Correlation matrix
cor_matrix <- merged_clean %>%
  select(GenderGapFRE, Father_quota_share, Mother_payment_ratio) %>%
  cor(use = "pairwise.complete.obs")
print(round(cor_matrix, 3))
#regression
model <- lm(GenderGapFRE ~ Father_quota_share + Mother_payment_ratio, data = merged_clean)
summary(model)

library(ggplot2)
ggplot(merged_clean, aes(x = Father_quota_share, y = GenderGapFRE)) +
  geom_point() +
  geom_smooth(method = "lm", se = FALSE) +
  labs(x = "Father quota share", y = "Gender gap (FRE weeks)",
       title = "Relationship between Father Quota Share and Gender Gap")


#   PF2_5 regression
library(ggplot2)
# 1. Data cleaning
# List of policy columns
policy_cols <- c(
  "Maternity_weeks", "Maternity_prebirth", "Maternity_postbirth",
  "Parental_protected", "Parental_paid", "Parental_paid_long",
  "Homecare_protected", "Homecare_paid",
  "Total_Protected", "Total_paid", "Total_paid_long",
  "Patleave", "Patleave_paid",
  "Father_specific_Parleave", "Father_specific_Parleave_paid",
  "Total_Father_specific", "Total_Father_specific_paid"
)

# Convert to numeric
for (col in policy_cols) {
  data_pf2_5[[col]] <- as.numeric(as.character(data_pf2_5[[col]]))
}

# Replace NAs with 0 for policies (optional, keeps more data for plots)
data_pf2_5[policy_cols] <- lapply(data_pf2_5[policy_cols], function(x) {
  x[is.na(x)] <- 0
  return(x)
})
# 2. Create dependent variable
data_pf2_5$gap_diff <- data_pf2_5$Maternity_weeks - data_pf2_5$Patleave

# 3. Baseline regressions
baseline_vars <- c(
  "Maternity_weeks", "Parental_protected", "Parental_paid", 
  "Parental_paid_long", "Homecare_protected", "Homecare_paid",
  "Patleave", "Father_specific_Parleave"
)

baseline_results <- list()
for (var in baseline_vars) {
  formula <- as.formula(paste("gap_diff ~", var))
  model <- lm(formula, data = data_pf2_5)
  baseline_results[[var]] <- summary(model)
}

# Print all baseline summaries
lapply(baseline_results, function(x) x$coefficients)

# 4. Interaction regression
interaction_model <- lm(gap_diff ~ Parental_paid * Father_specific_Parleave, data = data_pf2_5)
summary(interaction_model)

# 5. Index regressions
# Mother and father policy indices
data_pf2_5$Mother_index <- data_pf2_5$Maternity_weeks + data_pf2_5$Parental_paid + data_pf2_5$Homecare_paid
data_pf2_5$Father_index <- data_pf2_5$Patleave + data_pf2_5$Father_specific_Parleave_paid

index_model <- lm(gap_diff ~ Mother_index * Father_index, data = data_pf2_5)
summary(index_model)

# 6. Visualization

# 6a. Baseline: single policy scatter with regression
ggplot(data_pf2_5, aes(x = Parental_paid, y = gap_diff)) +
  geom_point(alpha = 0.5) +
  geom_smooth(method = "lm", se = TRUE, color = "blue") +
  labs(x = "Paid Parental Leave Weeks", y = "Gender Gap Difference (weeks)") +
  theme_minimal()

# 6b. Interaction heatmap (Mother_index x Father_index)

ggplot(data_pf2_5, aes(x = Mother_index, y = Father_index, z = gap_diff)) +
  stat_summary_2d(fun = mean, bins = 25) +
  scale_fill_gradient2(low = "blue", mid = "white", high = "red",
                       midpoint = median(data_pf2_5$gap_diff)) +
  labs(x = "Mother Policy Index (binned)",
       y = "Father Policy Index (binned)",
       fill = "Mean Gap Diff") +
  theme_minimal()


# 6c.interaction scatter with color by father policy
ggplot(data_pf2_5, aes(x = Parental_paid, y = gap_diff, color = Father_specific_Parleave)) +
  geom_point(alpha = 0.7) +
  geom_smooth(method = "lm", se = FALSE, color = "black") +
  labs(x = "Mother Paid Parental Leave Weeks", y = "Gender Gap Difference", color = "Father Reserved Weeks") +
  theme_minimal()



