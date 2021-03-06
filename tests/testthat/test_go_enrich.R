

# TODO: add e.g. chimp OrgDb and TxDb to 'Suggests' and try out here

#### test examples from vignette

root_names = c("biological_process", "molecular_function", "cellular_component")


## hyper

# defined bg
set.seed(123)
candi_gene_ids = c('NCAPG', 'APOL4', 'NGFR', 'NXPH4', 'C21orf59', 'CACNG2', 
    'AGTR1', 'ANO1', 'BTBD3', 'MTUS1', 'CALB1', 'GYG1', 'QUATSCH', 'PAX2')
bg_gene_ids = c('FGR', 'NPHP1', 'DRD2', 'ABCC10', 'PTBP2', 'JPH4', 'SMARCC2', 'FN1', 'NODAL', 'APOL4',
    'CYP1A2', 'ACSS1', 'CDHR1', 'SLC25A36', 'LEPR', 'PRPS2', 'TNFAIP3', 'NKX3-1', 'LPAR2', 'PGAM2', 'PAX2')
is_candidate = c(rep(1,length(candi_gene_ids)), rep(0,length(bg_gene_ids)))
input_hyper_bg = data.frame(gene_ids = c(candi_gene_ids, bg_gene_ids), is_candidate)
res_hyper_bg = go_enrich(input_hyper_bg, n_randsets=20, silent=TRUE)

test_that("hyper_defined_bg works fine",{
	expect_true(setequal(root_names, unique(res_hyper_bg[[1]][,1])))
	expect_true(setequal(res_hyper_bg[[2]][,2], c(0, 1)))
	expect_true(nrow(res_hyper_bg[[3]]) == 2)
	expect_equivalent(res_hyper_bg[[3]][1,1:2], c("go_annotations","Homo.sapiens"))
	expect_equivalent(res_hyper_bg[[3]][2,1:2], c("go_graph","integrated"))
})

# gene-len
set.seed(123)
res_hyper_len = go_enrich(input_hyper_bg, gene_len=TRUE, n_randsets=50, silent=TRUE)

test_that("hyper_gene_len works fine",{
	expect_true(setequal(root_names, unique(res_hyper_len[[1]][,1])))
	expect_true(setequal(res_hyper_len[[2]][,2], c(0, 1)))
	expect_equivalent(res_hyper_len[[3]][1,1:2], c("go_annotations","Homo.sapiens"))
	expect_equivalent(res_hyper_len[[3]][2,1:2], c("gene_coordinates","Homo.sapiens"))
})

# region
set.seed(123)
regions = c('8:81000000-83000000', '7:1300000-56800000', '7:74900000-148700000',
    '8:7400000-44300000', '8:47600000-146300000', '9:0-39200000', '9:69700000-140200000')
is_candidate = c(1, rep(0,6))
input_regions = data.frame(regions, is_candidate)
res_region = go_enrich(input_regions, n_randsets=30, regions=TRUE, silent=TRUE)

test_that("hyper_regions works fine",{
	expect_true(setequal(root_names, unique(res_region[[1]][,1])))
	expect_true(setequal(res_region[[2]][,2], c(0, 1)))
	expect_equivalent(res_region[[3]][1,1:2], c("go_annotations","Homo.sapiens"))
	expect_equivalent(res_region[[3]][2,1:2], c("gene_coordinates","Homo.sapiens"))
	expect_equivalent(res_region[[3]][3,1:2], c("go_graph","integrated"))

})


# region + circ_chrom
set.seed(123)

test_that("hyper_regions_circ works fine",{
	expect_warning((res_circ = go_enrich(input_regions[c(1,3:5),], n_randsets=20, regions=TRUE, silent=TRUE, circ_chrom=TRUE)),
	    "Unused chromosomes in background regions: chr7.\n  With circ_chrom=TRUE only background regions on the same chromosome as a candidate region are used.")
	expect_true(setequal(root_names, unique(res_circ[[1]][,1])))
	expect_true(setequal(res_circ[[2]][,2], c(0, 1)))
	expect_equivalent(res_circ[[3]][1,1:2], c("go_annotations","Homo.sapiens"))
	expect_equivalent(res_circ[[3]][2,1:2], c("gene_coordinates","Homo.sapiens"))
	expect_equivalent(res_circ[[3]][3,1:2], c("go_graph","integrated"))
})

## willi
set.seed(123)
high_score_genes = c('GCK', 'CALB1', 'PAX2', 'GYS1','SLC2A8', 'UGP2', 'BTBD3', 'MTUS1', 'SYP', 'PSEN1')
low_score_genes = c('CACNG2', 'ANO1', 'ZWINT', 'ENGASE', 'HK2', 'QUATSCH', 'PYGL', 'GYG1')
gene_scores = c(runif(length(high_score_genes), 0.5, 1), runif(length(low_score_genes), 0, 0.5))
input_willi = data.frame(gene_ids = c(high_score_genes, low_score_genes), gene_scores)
res_willi = go_enrich(input_willi, test='wilcoxon', n_randsets=20, silent=TRUE)

test_that("wilcox works fine",{
	expect_true(setequal(root_names, unique(res_willi[[1]][,1])))
	expect_true(all(res_willi[[2]][,2] %in% gene_scores)) # only score for QUATSCH is missing 
	expect_true(nrow(res_willi[[3]]) == 2)
	expect_equivalent(res_willi[[3]][1,1:2], c("go_annotations","Homo.sapiens"))
})


## binom
set.seed(123)
high_A_genes = c('G6PD', 'GCK', 'GYS1', 'HK2', 'PYGL', 'SLC2A8', 'UGP2', 'ZWINT', 'ENGASE')
low_A_genes = c('CACNG2', 'AGTR1', 'ANO1', 'BTBD3', 'MTUS1', 'CALB1', 'GYG1', 'PAX2', 'QUATSCH')
A_counts = c(sample(20:30, length(high_A_genes)), sample(5:15, length(low_A_genes)))
B_counts = c(sample(5:15, length(high_A_genes)), sample(20:30, length(low_A_genes)))
input_binom = data.frame(gene_ids=c(high_A_genes, low_A_genes), A_counts, B_counts)
res_binom = go_enrich(input_binom, test='binomial', n_randsets=20, silent=TRUE)

test_that("binom works fine",{
	expect_true(setequal(root_names, unique(res_binom[[1]][,1])))
	expect_true(all(res_binom[[2]][,2] %in% A_counts)) 
	expect_true(all(res_binom[[2]][,3] %in% B_counts)) 
	expect_true(nrow(res_binom[[3]]) == 2)
	expect_equivalent(res_binom[[3]][1,1:2], c("go_annotations","Homo.sapiens"))
})

## conti
set.seed(123)
high_substi_genes = c('G6PD', 'GCK', 'GYS1', 'HK2', 'PYGL', 'SLC2A8', 'UGP2', 'ZWINT', 'ENGASE', 'QUATSCH')
low_substi_genes = c('CACNG2', 'AGTR1', 'ANO1', 'BTBD3', 'MTUS1', 'CALB1', 'GYG1', 'PAX2', 'C21orf59')
subs_non_syn = c(sample(5:15, length(high_substi_genes), replace=TRUE), sample(0:5, length(low_substi_genes), replace=TRUE))
subs_syn = sample(5:15, length(c(high_substi_genes, low_substi_genes)), replace=TRUE)
vari_non_syn = c(sample(0:5, length(high_substi_genes), replace=TRUE), sample(0:10, length(low_substi_genes), replace=TRUE))
vari_syn = sample(5:15, length(c(high_substi_genes, low_substi_genes)), replace=TRUE)
input_conti = data.frame(gene_ids=c(high_substi_genes, low_substi_genes),
    subs_non_syn, subs_syn, vari_non_syn, vari_syn)
res_conti = go_enrich(input_conti, test='contingency', n_randsets=20, silent=TRUE)

test_that("conti works fine",{
	expect_true(setequal(root_names, unique(res_conti[[1]][,1])))
	expect_true(all(res_conti[[2]][,2] %in% subs_non_syn)) 
	expect_true(all(res_conti[[2]][,3] %in% subs_syn)) 
	expect_true(all(res_conti[[2]][,4] %in% vari_non_syn)) 
	expect_true(all(res_conti[[2]][,5] %in% vari_syn)) 
	expect_true(nrow(res_conti[[3]]) == 2)
	expect_equivalent(res_conti[[3]][1,1:2], c("go_annotations","Homo.sapiens"))
	expect_equivalent(res_conti[[3]][2,1:2], c("go_graph","integrated"))

})
