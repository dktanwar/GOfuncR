
# get genes from genomic regions

# 'genes' is the input-dataframe for go_enrich, in this case it's genomic regions like 9:123-1225
# output: list of
    # classic single genes go_enrich input-dataframe
    # gene_coords chr, start, end, gene for all genes (test+bg)
# side-effect: write regions to file for FUNC

# if coord_db = TxDb, then orgDb is used as entrez_db to convert TxDb-entrez-id to gene-symbols
# eval_db_input checks that TxDb and OrgDb depend on each other
# if gene_coords are provided as dataframe by user, use that instead of coord_db

blocks_to_genes = function(directory, genes, coord_db="Homo.sapiens", entrez_db=NA, gene_coords=NULL, circ_chrom=FALSE, silent=FALSE){

    # check regions are valid, remove unused chroms for circ_chrom,
    # get two bed-dataframes back (candidate and background)
    regions = check_regions(genes, circ_chrom)
    test_regions = regions[[1]]
    bg_regions = regions[[2]]
    
    # convert to GRanges
    test_range = GRanges(test_regions[,1], IRanges::IRanges(test_regions[,2], test_regions[,3]))
    bg_range = GRanges(bg_regions[,1], IRanges::IRanges(bg_regions[,2], bg_regions[,3]))

    # get all gene coordinates
    if (!is.null(gene_coords)){
        if (!silent){
            message("find genes in input-regions using custom 'gene_coords'...")
        }
    } else {
        # load databases and check if OrganismDb or OrgDb/TxDb
        load_db(coord_db, silent)
        if (is.na(entrez_db)){
            # OrganismDb
            gene_identifier = "SYMBOL"
        } else {
            # orgDb (entrez_db) + TxDb (coord_db)
            gene_identifier = "GENEID"
        }
        # get all genes from coord_db
        gene_coords = get_all_coords(coord_db=coord_db, entrez_db=entrez_db, silent=silent)
        if (!silent){
            message("find genes in input-regions using database '", coord_db,"'...")
        }
    }
    # convert to GRanges for IRanges::subsetByOverlaps
    all_genes = GRanges(gene_coords[,1], IRanges::IRanges(gene_coords[,2], gene_coords[,3]), SYMBOL=gene_coords[,4])
    
    # get overlapping genes
    test_genes = get_genes_from_regions(all_genes, test_range)
    bg_genes = get_genes_from_regions(all_genes, bg_range)
    
    # check that candidate and background contain genes
    if (nrow(test_genes) == 0){
        stop("Candidate regions do not contain any genes.")
    }
    if (nrow(bg_genes) == 0){
        stop("Background regions do not contain any genes.")
    }
    
    ## write candidate and background bed-files for C++
    # merge candidate into background for randomsets
    full_bg_range = suppressWarnings(reduce(c(test_range, bg_range)))
    full_bg_regions = data.frame(chr=seqnames(full_bg_range), start=start(full_bg_range), end=end(full_bg_range))
    # avoid scientific notation in regions (read in c++)
    test_regions = format(test_regions, scientific=FALSE, trim=TRUE)
    full_bg_regions = format(full_bg_regions, scientific=FALSE, trim=TRUE)
    # write regions to files
    write.table(test_regions,file=paste(directory, "_test_regions.bed",sep=""),col.names=FALSE,row.names=FALSE,quote=FALSE,sep="\t")
    write.table(full_bg_regions,file=paste(directory, "_bg_regions.bed",sep=""),col.names=FALSE,row.names=FALSE,quote=FALSE,sep="\t")

    # combine gene coords of background and test regions (to create input for FUNC in go_enrich)
    gene_coords = unique(rbind(test_genes, bg_genes))

    # convert to classic go_enrich input avoiding double-assignment of candidate/background
    genes_df = data.frame(genes=gene_coords$gene, score=rep(0,nrow(gene_coords)))
    genes_df[,1] = as.character(genes_df[,1])
    genes_df[genes_df$genes %in% test_genes[,4], 2] = 1
    
    return(list(genes_df, gene_coords))
}




# input: 
    # dataframe with genomic regions (chr:from-to) and 1/0
    # circ_chrom-option T/F
# output: list with elements
    # test-regions (bed)
    # background_regions (merged with test-regions) (bed)
check_regions = function(genes, circ_chrom){
    
    # check that background region is specified
    if (all(genes[,2]==1)){
        stop("All values of the genes[,2] input are 1. Using chromosomal regions as input requires defining background regions with 0.")
    }
    
    # convert coordinates from 'genes'-names to bed-format
    genes[,1] = as.character(genes[,1])
    bed = do.call(rbind, strsplit(genes[,1], "[:-]"))
    bed = as.data.frame(bed)
    bed[,2:3] = apply(bed[,2:3], 2, as.numeric)
    bed[,1] = as.character(bed[,1])
    
    # add 'chr' if missing (coord_db has it too)
    if (!startsWith(bed[1,1], "chr")){
        bed[,1] = paste0("chr", bed[,1])
    }
    
    # check that start < stop
    reverse_indi = bed[,2] > bed[,3]
    if(sum(reverse_indi) > 0){
        reverse = paste(genes[,1][reverse_indi], collapse=", ")
        stop("Invalid regions: ", reverse, ".\n  In 'chr:start-stop' start < stop is required.")
    }
        
    # split in test and background
    test_reg = bed[genes[,2]==1,]
    bg_reg = bed[genes[,2]==0,] 
    
    ## test that regions are non-overlapping (separately for candidate and background)
    # candidate
    overlap_indis = check_overlap(test_reg)
    if (length(overlap_indis) > 0){
        over = paste(genes[genes[,2]==1,1][overlap_indis], collapse=", ")
        stop("Candidate regions overlap: ", over)
    }
    # background
    overlap_indis = check_overlap(bg_reg)
    if (length(overlap_indis) > 0){
        over = paste(genes[genes[,2]==0,1][overlap_indis], collapse=", ")
        stop("Background regions overlap: ", over)
    }
        
    # sort  (mixedorder does not work with multiple columns) 
    test_reg = test_reg[order(test_reg[,2]),] 
    bg_reg = bg_reg[order(bg_reg[,2]),] 
    test_reg = test_reg[mixedorder(test_reg[,1]),] 
    bg_reg = bg_reg[mixedorder(bg_reg[,1]),] 
    
    # if rolling chrom: remove unused bg chroms and warn, check that all candidate chroms have bg
    if(circ_chrom == TRUE){             
        if(!(all(bg_reg[,1] %in% test_reg[,1]))){
            not_used = unique(bg_reg[!(bg_reg[,1] %in% test_reg[,1]),1])
            not_used = paste(not_used, collapse=", ")
            warning("Unused chromosomes in background regions: ", not_used, ".\n  With circ_chrom=TRUE only background regions on the same chromosome as a candidate region are used.")
            bg_reg = bg_reg[bg_reg[,1] %in% test_reg[,1],]
        }           
        if(!(all(test_reg[,1] %in% bg_reg[,1]))){
            wo_bg = unique(test_reg[!(test_reg[,1] %in% bg_reg[,1]),1])
            wo_bg = paste(wo_bg, collapse=", ")
            stop("No background region for chromosomes: ",  wo_bg, ".\n  With circ_chrom=TRUE only background regions on the same chromosome as a candidate region are used.")
        }
    } else {  # normal blocks option
        # sort candidate regions by length (better chances that random placement works with small bg-regions)
        test_reg = test_reg[order(test_reg[,3] - test_reg[,2], decreasing=TRUE),]
    }

    return(list(test_reg, bg_reg))    
}


# take a bed-format dataframe and check if regions overlap
# return a vector of row-indices that overlap any other region
check_overlap = function(regions_bed){
    overlap_indis = c()
    for (i in seq_len(nrow(regions_bed))){
        # if (chrom=chrom & (start inside | end inside | including)) any other region
        chrom_match = regions_bed[i,1] == regions_bed[,1]
        start_inside = regions_bed[i,2] > regions_bed[,2] & regions_bed[i,2] < regions_bed[,3]
        end_inside = regions_bed[i,3] > regions_bed[,2] & regions_bed[i,3] < regions_bed[,3]
        include = regions_bed[i,2] < regions_bed[,2] & regions_bed[i,3] > regions_bed[,3]
        if (any(chrom_match & (start_inside | end_inside | include))){
            overlap_indis = c(overlap_indis, i)
        }
    }
    return(overlap_indis)
}


