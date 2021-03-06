Scripts for reproducing results of "A Comparative Analysis of Reference-Free and Conventional Transcriptome Signatures for Prostate Cancer Prognosis".

1. infer_gene-based_risk_signature.R: Infers a risk signature using conventional gene expression counting. 

2. infer_gene-free_risk_signature.R: Infers a risk signature from a set of RNA contigs obtained by, running DE-kupl without Differential expression analysis module.

3. infer_gene-based_relaspe_signature.R: The same as script 1 but in relapse condition.

4. infer_gene-free_relaspe_signature.R: The same as script 2 but in relapse condition.


All four scripts starts from a count table in the Discovery Set (TCGA-PRAD cohor), then normalisation is performed as count perbillion for k-mers or count per million for genes. Features are ranked according to their F1-score computed by cross validation using a Naive Bayes classifier (NB) and the top 500 features are retained. Among the top 500, features are selected using lasso logistic regression combined with stability selection. The signature is then used to build a predictor in the two independent RNA-seq datasets (ICGC-PRAD and Stelloo cohors) for validation.

5. box_plot_risk_signature.R: This script draws the box plot of risk signature in Discovery set and Validation set.

6. box_plot_relapse_signature.R: This script draws the box plot of relapse signature in Discovery set and Validation set.

7. useful_functions.R: collection of functions that are used for infer signature in both tumor risk and relapse models.
