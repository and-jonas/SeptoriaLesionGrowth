#=============================================================================== -

#HEADER ----

# Author: Lukas Roth, ETH Zürich
# Copyright (C) 2025  ETH Zürich, Lukas Roth (lukas.roth@usys.ethz.ch)

# Last edited: 2025-05-08, Jonas Anderegg, jonas.anderegg@usys.ethz.ch

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#  
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

#=============================================================================== -

rm(list = ls())
.libPaths("T:/R4Userlibs")

# install required packages
list.of.packages <- c("tidyverse", "asreml", "ggpubr", "ggplot2", "flextable", "officer")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, lib = "T:/R4Userlibs", dependencies = TRUE, repos='https://stat.ethz.ch/CRAN/')

# load packages
library(tidyverse)
library(asreml)
library(ggpubr)
library(ggplot2)
library(flextable)
library(officer)

# set the working directory
setwd("C:/Users/anjonas/RProjects/lesionProc")

# set paths
data_path <- "./data/"
out_path <- "./output/"
figure_path <- "./output/figures/"
out_data_path <- "./output/data/"

# load data
data <- read_csv(paste0(data_path, "lesion_dataset_stats.csv"))

# convert to factors
data <- data %>%
  mutate(across(1:8, as.factor))

# Random regression:
# We want to investigate fixed effects of covariates (age, mean_temp, ...) and interactions of genotypes with these covariates
# Genotype is random (we are interested in genetic variance), consequently all interaction terms are random as well
# Each genotype can deviate in intercept and response to the investigated covariates in a structured way (normal dist and correlated)

# Base model: Nullhypotheis: No genotype-specific interaction effects, just genotype main effect
m0 <- asreml(
  fixed= delta ~ year + batch + age + mean_temp + mean_rh + area + maxdist,
  random =
    ~ genotype_name + plot_UID + leaf_nr + lesion_nr +
    age:id(lesion_nr),
  data=data,
  maxiter=20
)
wald(m0)

# Hypothesis: Age related growth is genotype specific
m1_age <- asreml(
  fixed= delta ~ year + batch + age + mean_temp + mean_rh + area + maxdist,
  random =
    ~ genotype_name + plot_UID + leaf_nr + lesion_nr +
    age:id(genotype_name) + age:id(lesion_nr),
  data=data,
  maxiter=20
)
# Test
summary(m0)$bic
summary(m1_age)$bic
# log-likelihood test (allowed as models are nexted for random effects and fixed effects are the same)
lrt.asreml(m0, m1_age)
# Definitely significant, m1 is new base model

# Hypothesis: Environemental covariates (rh, temp) matter as well
# Try first rh. Use corgh(2) to allow for correlation of age and rh effects
m2_rh <- asreml(
  fixed= delta ~ year + batch+ age + mean_temp + mean_rh + area + maxdist,
  random =
    ~ genotype_name + plot_UID + leaf_nr + lesion_nr +
      ~str(~ age:genotype_name + mean_rh:genotype_name, ~corgh(2):id(genotype_name)) +
      + age:id(lesion_nr),
  data=data,
  maxiter=20
)
# Test
summary(m1_age)$bic
summary(m2_rh)$bic
lrt.asreml(m1_age, m2_rh)
# Not significant.

# Try temp.
m2_temp <- asreml(
  fixed= delta ~ year + batch + age + mean_temp + mean_rh + area + maxdist,
  random =
    ~ genotype_name + plot_UID + leaf_nr + lesion_nr +
      ~str(~ age:genotype_name + mean_temp:genotype_name, ~corgh(2):id(genotype_name)) +
     age:id(lesion_nr),
  data=data,
  maxiter=35
)
# Test
summary(m1_age)$bic
summary(m2_temp)$bic
lrt.asreml(m1_age, m2_temp)
# significant. m2 is new base model

# Give rh another try, now together with temp
m3_rh_temp <- asreml(
  fixed= delta ~ year + batch + age + mean_temp + mean_rh + area + maxdist,
  random =
    ~ genotype_name + leaf_nr + lesion_nr +
      ~str(~ age:genotype_name + mean_rh:genotype_name + mean_temp:genotype_name, ~corgh(3):id(genotype_name)) +
  age:id(lesion_nr),
  data=data,
  maxiter=20
)

# Components changes >1%, update model again
m3_rh_temp <- update(m3_rh_temp)
# Fine

# Test
summary(m2_temp)$bic
summary(m3_rh_temp)$bic
lrt.asreml(m2_temp, m3_rh_temp)
# Significant. m3 with both temp and rh is new base model
wald(m3_rh_temp)
plot(m3_rh_temp)

# export wald table of fixed effects
wald_df <- data.frame(
  Term = rownames(wald(m3_rh_temp)),
  wald(m3_rh_temp)
)
wald_df<- wald_df[c(1:8), ]
# rename columns
colnames(wald_df) = c("Term", "Df", "Sum of Squares", "Wald Statistic", "P-value")

# Format numbers
wald_df$`Sum of Squares` <- format(wald_df$`Sum of Squares`, digits = 1, scientific = F)
wald_df$`Wald Statistic` <- format(wald_df$`Wald Statistic`, digits = 4, scientific = FALSE)

# Format p-values and add significance stars
wald_df$`P-value` <- as.numeric(wald_df$`P-value`)  # ensure numeric first
wald_df$`P-value` <- ifelse(
  is.na(wald_df$`P-value`), NA,
  ifelse(wald_df$`P-value` < 0.0000000000000001, "< 2.2e-16",
         formatC(wald_df$`P-value`, format = "f", digits = 7)
  )
)

wald_df$sign[wald_df$`P-value` > 0.10] <- "   " 
wald_df$sign[wald_df$`P-value` < 0.10] <- "." 
wald_df$sign[wald_df$`P-value` < 0.05] <- "*" 
wald_df$sign[wald_df$`P-value` < 0.01] <- "**"
wald_df$sign[wald_df$`P-value` < 0.001] <- "***"
wald_df$`P-value` = paste(wald_df$`P-value`, wald_df$sign)
wald_df <- wald_df %>% dplyr::select(-sign)

ft <- flextable(wald_df)
ft <- autofit(ft)
doc <- read_docx()
doc <- body_add_flextable(doc, ft)
print(doc, target = paste(figure_path, "wald_results.docx"))

# export blups for further analyses
df_temp_resp <- as.data.frame(predict(m3_rh_temp, classify = "genotype_name")$pvals)
write.csv(df_temp_resp, paste0(out_data_path, "growth_blups.csv"))

# Make genotype-specific predictions
df_temp_resp <- predict(m3_rh_temp, classify = "genotype_name:mean_temp:mean_rh:age",
                        levels= list(
                          mean_temp = c(min(data$mean_temp), max(data$mean_temp)),
                            mean_rh = c(60, 80, 100),
                            age = c(10, 100, 200)
                        )
)$pvals

# Plot genotype responses
plt1 <- ggplot(data=df_temp_resp, aes(x=mean_temp, y=predicted.value, color=as.factor(age), linetype=as.factor(mean_rh))) +
  geom_line(size=1) +
  facet_grid(~genotype_name) +
  scale_color_brewer(type="qual") + 
  labs(
    color = "Lesion age (hours)", 
    linetype = "Mean relative humidity (%)"
  ) +
  ylab("Predicted lesion growth") +
  xlab("Mean interval temperature (°C)") +
  theme(legend.position = "bottom")
png(paste0(figure_path, "slopes_temp.png"), width = 12, height = 4, units = 'in', res = 400)
plot(plt1)
dev.off()

# Correlations of genotype-interaction effects
df_corrs <-
  data.frame(
    from = c("age", "age", "mean_rh"),
    to = c("mean_rh", "mean_temp", "mean_temp"),
    cor = c(
      summary(m3_rh_temp)$varcomp[4, 1],
      summary(m3_rh_temp)$varcomp[5, 1],
      summary(m3_rh_temp)$varcomp[6, 1]
    )
  )

# Extract varcomp table
varcomp <- summary(m3_rh_temp)$varcomp

# Extract correlation terms by name
cor_age_mean_rh <- varcomp[grep("!corgh\\(3\\)!2:!corgh\\(3\\)!1\\.cor", rownames(varcomp)), "component"]
cor_age_mean_temp <- varcomp[grep("!corgh\\(3\\)!3:!corgh\\(3\\)!1\\.cor", rownames(varcomp)), "component"]
cor_mean_rh_mean_temp <- varcomp[grep("!corgh\\(3\\)!3:!corgh\\(3\\)!2\\.cor", rownames(varcomp)), "component"]

# Assemble into a data.frame
df_corrs <- data.frame(
  from = c("age", "age", "mean_rh"),
  to = c("mean_rh", "mean_temp", "mean_temp"),
  cor = c(cor_age_mean_rh, cor_age_mean_temp, cor_mean_rh_mean_temp)
)

plt2 <- ggplot(data=df_corrs, aes(x=from, y=to, fill=cor)) +
  geom_tile() +
  geom_text(aes(label=round(cor, 3)), color="black")

# Get variance explained by varcomps
var_comp_names <- data.frame(
  varcomp = paste0("V", c(1,    5, 6, 7, 8, 9, 10, 11)),
  residual_term = c(F, F, F, F, T, T, T, T),
  varcomp_names = c(
    "genotype",
    "genotype x age",
    "genotype x rh",
    "genotype_name x temp",
    "leaf_nr",
    "lesion_nr",
    "age x lesion_nr",
    "residual"
  )
)
for (i in 1:nrow(var_comp_names)) {
  formula_ <- paste0("~ ", var_comp_names$varcomp[i], "/ (", paste0(var_comp_names$varcomp, collapse = " + "), ")")
    var_comp_names$perc_var[i] <- vpredict(m3_rh_temp, as.formula(formula_))$Estimate[[1]]
}
plt3 <- ggplot(data=var_comp_names, aes(x=reorder(varcomp_names, -perc_var), y=perc_var)) +
  geom_bar(stat="identity") +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(x="Variance component", y="Total variance explained")

plt4 <-ggplot(data=var_comp_names %>% filter(!residual_term), aes(x=reorder(varcomp_names, -perc_var), y=perc_var)) +
  geom_bar(stat="identity") +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(x="Variance component", y="G and GxE variance explained")

ggarrange(plt1, ggarrange(plt2, plt3, plt4, nrow=1), nrow=2)

# ============================================================================== -

# Get predicted slopes

# Temperature
df_temp_resp_G <- predict(m3_rh_temp, classify = "genotype_name:mean_temp",
                          levels= list(
                            mean_temp = c(0, 1)
                          )
)$pvals
df_temp_resp_G <- df_temp_resp_G %>% select(-std.error) %>% pivot_wider(names_from = mean_temp, values_from = predicted.value) %>%
  mutate(slope = `1` - `0`) %>% 
  rename(slope_temp = slope) %>% 
  dplyr::select(genotype_name, slope_temp)

# Relative Humidity
df_rh_resp_G <- predict(m3_rh_temp, classify = "genotype_name:mean_rh",
                          levels= list(
                            mean_rh = c(0, 1)
                          )
)$pvals
df_rh_resp_G <- df_rh_resp_G %>% select(-std.error) %>% pivot_wider(names_from = mean_rh, values_from = predicted.value) %>%
  mutate(slope = `1` - `0`) %>% 
  rename(slope_rh = slope) %>% 
  dplyr::select(genotype_name, slope_rh)


# Age
df_age_resp_G <- predict(m3_rh_temp, classify = "genotype_name:age",
                        levels= list(
                          age = c(0, 1)
                        )
)$pvals
df_age_resp_G <- df_age_resp_G %>% select(-std.error) %>% pivot_wider(names_from = age, values_from = predicted.value) %>%
  mutate(slope = `1` - `0`) %>% 
  rename(slope_age = slope) %>% 
  dplyr::select(genotype_name, slope_age)

slopes <- full_join(df_temp_resp_G, df_rh_resp_G) %>% 
  full_join(., df_age_resp_G)

write.csv(slopes, 
          paste0(out_data_path, "slopes_blups.csv"),
          row.names = F)

# ============================================================================== -