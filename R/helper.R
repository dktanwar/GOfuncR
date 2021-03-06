

# input: some arguments provided to go_enrich
# output: database data.frame with type, db, version for GO-graph, GO-annotations, and gene-coords
eval_db_input = function(organismDb, godir, orgDb, annotations, txDb, regions, gene_len, gene_coords){
    
    # annotation, coord databases/files
    if (regions || gene_len){
        if (!is.null(txDb) && is.null(orgDb)){
            stop("Please provide an 'orgDb' package for annotations and/or Entrez-ID to gene-symbol conversion if 'txDb' is defined.")
        }
        if (!is.null(orgDb) && is.null(txDb) && is.null(gene_coords)){
            stop("Please provide a 'txDb' object from bioconductor or a 'gene_coords' data.frame (if 'orgDb' is defined for GO-annotations, then either 'txDb' or 'gene_coords' is used to obtain gene-coordinates.")
        }
    }
    if (!is.null(gene_coords) && !(gene_len || regions)){
        stop("Parameter 'gene_coords' is only used when 'gene_len=TRUE' or 'regions=TRUE'.")
    }
    if (!is.null(txDb) && !(gene_len || regions)){
        stop("Parameter 'txDb' is only used when 'gene_len=TRUE' or 'regions=TRUE'.")
    }
    
    # 1) annotations 
    # if orgDb/annotations is defined use that one instead of default organismDb
    if (!is.null(annotations)){
        anno_db = "custom"
        a_version = "custom"
    } else if (!is.null(orgDb)){
        anno_db = orgDb
        a_version = load_db(anno_db)
    } else {
        anno_db = organismDb
        a_version = load_db(anno_db)
    }
    databases = data.frame(type="go_annotations", db=anno_db, version=a_version, stringsAsFactors=FALSE)
    
    # 2) coordinates
    # only if blocks or gene-len
    if (regions || gene_len){
        if (!is.null(gene_coords)){
            coord_db = "custom"
            c_version = "custom"        
        } else if (!is.null(txDb)){
            coord_db = txDb
            c_version = load_db(coord_db)
        } else {
            coord_db = organismDb
            c_version = load_db(coord_db)
        }
    } else {
        coord_db = NA
        c_version = NA
    }
    databases = rbind(databases, list("gene_coordinates", coord_db, c_version))

    # 3) symbol to entrez conversion
    # only if coords are needed and TxDb is used
    if (!(is.na(coord_db)) &&  !(is.null(txDb))){
        entrez_db = orgDb
        e_version = load_db(orgDb)
    } else {
        entrez_db = NA
        e_version = NA
    }
    databases = rbind(databases, list("symbol_to_entrez", entrez_db, e_version))
    
    # 4) GO-graph
    if (is.null(godir)){
        databases = rbind(databases, list("go_graph", "integrated", "07-Oct-2019"))
    } else {
        databases = rbind(databases, list("go_graph", "custom", godir))
    }

    return(databases)
}


# input: some arguments provided e.g. to get_anno_genes, get_child_nodes, get_parent_nodes
# output: term and graph_path, potentially user-defined
eval_onto_input = function(term_df=NULL, graph_path_df=NULL, godir=NULL){
    # ontology
    if ((is.null(term_df)) && !(is.null(graph_path_df))){
        stop("Please also provide 'term_df' (when 'graph_path_df' is specified also 'term_df' is needed)")
    }
    if (!(is.null(term_df))){
        # A) term and graph_path provided directly
        if (is.null(graph_path_df)){
            stop("Please also provide 'graph_path_df' (when 'term_df' is specified also 'graph_path_df' is needed)")
        }
        if(!(is.null(godir))){
            stop("Please provide either 'term_df' and 'graph_path_df' or 'godir'")
        }
        term = term_df
        graph_path = graph_path_df
    } else if (!(is.null(godir))){
        # B) custom ontology directory
        term = read.table(paste0(godir, "/term.txt"), sep="\t", quote="", comment.char="", as.is=TRUE)
        graph_path = read.table(paste0(godir, "/graph_path.txt"),
            sep="\t", quote="", comment.char="", as.is=TRUE)
    } # else C) use integrated term and graph_path
    
    return(list(term, graph_path))
}

# input: some arguments provided e.g. to get_anno_categories, get_names
# output: term, potentially user-defined
eval_term = function(term_df, godir){
    if (!(is.null(term_df)) && !(is.null(godir))){
        stop("Please provide either 'term_df' or 'godir'")
    }
    if (!(is.null(term_df))){
        term = term_df
    } else if (!(is.null(godir))){
        term = read.table(paste0(godir, "/term.txt"), sep="\t", quote="", comment.char="", as.is=TRUE)
    } # else term is taken from sysdata
    
    return(term)
}

# load database
load_db = function(db, silent=FALSE){
    if (!suppressWarnings(suppressMessages(require(db, character.only=TRUE)))){
        stop("database '" ,db, "' is not installed. Please install it from bioconductor:\nif (!requireNamespace('BiocManager', quietly = TRUE))\n\tinstall.packages('BiocManager')\nBiocManager::install('",db ,"')")
    }
    vers = as.character(packageVersion(db))
    return(invisible(vers))
}

# find overlaps of genes, ranges and convert to data.frame chr, start, end, gene
get_genes_from_regions = function(gene_coords, ranges){
    genes = IRanges::subsetByOverlaps(gene_coords, ranges)
    out = data.frame(chr=seqnames(genes), start=start(genes), end=end(genes), gene=elementMetadata(genes)[,1])
    return(out)
}

# convert EntrezID from TxDb to symbol using orgDb
entrez_to_symbol = function(entrez, orgDb){
    symbol = suppressMessages(select(orgDb, keys=as.character(entrez), columns=c("ENTREZID","SYMBOL"), keytype="ENTREZID"))
    # just double-check
    if(any(symbol[,1] != entrez)) {stop("Unexpected order in entrez_to_symbol.")}
    return(symbol)
}

# take the lowest transcript start and the highest end (cols in: gene, chr, start, end)
combine_tx = function(coords){
    c1 = aggregate(TXSTART ~ SYMBOL + TXCHROM, coords, min)
    c2 = aggregate(TXEND ~ SYMBOL + TXCHROM, coords, max)
    out = merge(c1, c2)[,c(2:4,1)] # move gene to last column
    return(out)
}

# get chr, start, stop, symbol for all genes in coord_db
# txDb only has entrez, not gene-symbol, need orgDb for conversion
# eval_db_input checks that TxDb and OrgDb depend on each other
get_all_coords = function(coord_db="Homo.sapiens", entrez_db=NA, silent=FALSE){
    load_db(coord_db, silent)
    if (!silent){
        message("find gene coordinates using database '", coord_db,"'...")
    }
    if (is.na(entrez_db)){
        # OrganismDb
        symbols = keys(get(coord_db), keytype="SYMBOL")
        coords = suppressMessages(select(get(coord_db), keys=symbols, columns=c("TXCHROM", "TXSTART", "TXEND", "SYMBOL"), keytype="SYMBOL"))
    } else {
        # OrgDb/TxDb (combine possible different Entrez per Symbol)
        load_db(entrez_db, silent)
        entrez = keys(get(coord_db), keytype="GENEID")
        coords = suppressMessages(select(get(coord_db), keys=entrez, columns=c("TXCHROM", "TXSTART", "TXEND", "GENEID"), keytype="GENEID"))
        coords[,1] = entrez_to_symbol(coords[,1], get(entrez_db))[,2]
        colnames(coords)[1] = "SYMBOL"
    }
    # maximum transcript range
    coords = combine_tx(coords)
    # remove genes that are still duplicated (on different chroms, mostly X/Y)
    coords = coords[!(coords[,4] %in% coords[duplicated(coords[,4]),4]) ,]
    
    return(coords)
}

# get chr, start, stop, symbol for input symbols
# txDb only has only entrez, not gene-symbol, need orgDb for conversion
# eval_db_input checks that TxDb and OrgDb depend on each other
get_gene_coords = function(symbols, coord_db="Homo.sapiens", entrez_db=NA, silent=FALSE){
    load_db(coord_db, silent)
    if (!silent){
        message("find gene coordinates using database '", coord_db,"'...")
    }
    if (is.na(entrez_db)){
        # OrganismDb
        coords = suppressMessages(select(get(coord_db), keys=symbols, columns=c("TXCHROM", "TXSTART", "TXEND", "SYMBOL"), keytype="SYMBOL"))
    } else {
        # OrgDb/TxDb (combine possible different Entrez per Symbol)
        load_db(entrez_db, silent)
        entrez = suppressMessages(select(get(entrez_db), keys=symbols, columns=c("ENTREZID", "SYMBOL"), keytype="SYMBOL"))
        en_coords = suppressMessages(select(get(coord_db), keys=entrez[,2], columns=c("TXCHROM", "TXSTART", "TXEND", "GENEID"), keytype="GENEID"))
        coords = merge(entrez, en_coords, by.x="ENTREZID", by.y="GENEID")[,2:5]
    }
    # maximum transcript range
    coords = combine_tx(coords)
    # remove genes that are still duplicated (on different chroms, mostly X/Y)
    coords = coords[!(coords[,4] %in% coords[duplicated(coords[,4]),4]) ,]
    
    return(coords)
}

# get term.txt IDs for GO-IDs
go_to_term = function(go_ids, term){
    go_ids = as.character(go_ids)
    # remove obsolete terms
    term = term[term[,5]==0,]
    # get term-IDs of GOs
    go_ids_term = term[match(go_ids, term[,4]), 1]
    return(go_ids_term)
}

# get GO-IDs of term.txt IDs
term_to_go = function(term_ids, term){
    go_ids = term[match(term_ids, term[,1]) ,4]
    return(go_ids)
}

# check if res is really go_enrich()[[1]]
check_res = function(res){
    if (!(is.list(res) && all(names(res) == c("results","genes","databases","min_p")))){
        stop("Please use an object returned from go_enrich as input (list with 4 elements).")
    }
}

# infer go_enrich test given input_genes = res[[2]]
# TODO: maybe remove parameter 'test' for go_enrich too
infer_test = function(input_genes){
    if (ncol(input_genes) == 2){
        if(all(input_genes[,2] %in% c(1,0))){
            test = "hyper"
        } else {
            test = "wilcoxon"
        }
    } else if(ncol(input_genes) == 3){
        test = "binomial"
    } else if(ncol(input_genes) == 5){
        test = "contingency"
    } else {
        stop("Identification of test failed.")
    }
    return(test)
}

# infer ontology, load term and graph_path if custom
# given databases = go_enrich()[[3]]
load_onto = function(databases){
    onto = databases[databases[,1] == "go_graph", ]
    if (onto[1,2] == "custom"){
        message("Read custom ontology graph...")
        godir = onto[1,3]
        term = read.table(paste0(godir,"/term.txt"),sep="\t",quote="",comment.char="",as.is=TRUE)
        graph_path = read.table(paste0(godir,"/graph_path.txt"),sep="\t",quote="",comment.char="",as.is=TRUE)
    } # else, take from sysdata
    return(list(term, graph_path))
}

# get annotated genes and their scores from go_enrich() given GO-IDs
# use term and graph_path directly to avoid re-reading custom ontology
get_anno_scores = function(res, go_ids, term, graph_path, annotations=NULL){
    in_genes = res[[2]]
    anno_db = res[[3]][1,2]
    if (anno_db == "custom" && is.null(annotations)){
        stop("Apparently go_enrich was run with custom annotations. Please provide those custom annotations to this function too.")
    }
    # check if background genes are defined (optional for hyper)
    test = infer_test(in_genes)
    if (test == "hyper" & all(in_genes[,2] == 1)){
        genes = NULL
    } else {
        genes = in_genes[,1]
    }
    # genes=NULL will return annotations for all genes
    anno = get_anno_genes(go_ids, database=anno_db, genes, annotations, term, graph_path)
    if (is.null(anno)){
        return(invisible(NULL)) # no annotations - warning from get_anno_genes
    }
    # add scores to nodes
    anno_scores = cbind(anno, in_genes[match(anno[,2], in_genes[,1]), 2:ncol(in_genes)])
    colnames(anno_scores)[3:ncol(anno_scores)] = colnames(in_genes)[2:ncol(in_genes)]
    # for default background, bg-genes are not in res[[2]], match yields NA, convert to 0
    if (test == "hyper"){
        anno_scores[is.na(anno_scores[,3]), 3] = 0 # default 0 for hyper (NA if background not defined)
    }

    return(anno_scores)
}

