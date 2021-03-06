#' @title Retrieve all upstream promotor sequences from a genome
#' @description Given a genome assembly file and an corresponding annotation 
#' file users can retrieve all upstream promotor sequences of all genes from a genome. 
#' @param organism a character string specifying the scientific name of the organism.
#' @param genome_file file path to the genome assembly file.
#' @param annotation_file file path to the annotation file of the genome assembly
#' in \code{gtf} format.
#' @param annotation_format format of the annotation file. Options are:
#' \itemize{
#' \item \code{annotation_format = "gtf"}
#' \item \code{annotation_format = "gff"}
#' \item \code{annotation_format = "gff3"}
#' }
#' @param file_name file path to the output file storing the promotor sequences.
#' @param promotor_width width of upstream promotors. This is -\code{promotor_width} bp from the
#' transcription start site (TSS) of the gene.
#' @param replaceUnstranded logical value indicating whether or not unstranded sequences shall receive a default strand. Default is \code{replaceUnstranded = TRUE}.
#' @author Hajk-Georg Drost
#' @details This function extracts genomic sequences of a specified \code{promotor_width} upstream of the transcription start sites of all genes annotated in the corresponding 
#' \code{annotation_file} file. The promotor sequenes are then 
#' @examples \dontrun{
#' # download genome assembly of Arabidopsis lyrata
#' Aly_genome <- biomartr::getGenome(db = "refseq", 
#'                                  organism = "Arabidopsis lyrata",
#'                                  path = file.path("refseq", "genome"),
#'                                  gunzip = TRUE)
#' # download annotation file of genome assembly of Arabidopsis lyrata
#' Aly_gff <- biomartr::getGFF(db = "refseq", 
#'                            organism = "Arabidopsis lyrata",
#'                            path = file.path("refseq", "annotation"),
#'                            gunzip = TRUE)
#'                            
#' # retrieve upstream promotor sequences of length 1000bp
#' promotor_seqs <- extract_upstream_promotor_seqs(
#'                                organism = "Arabidopsis lyrata",
#'                                genome_file = Aly_genome,
#'                                annotation_file = Aly_gff,
#'                                annotation_format = "gff",
#'                                promotor_width = 1000)
#'
#' }
#' @export

extract_upstream_promotor_seqs <- function(organism,
                                            genome_file,
                                            annotation_file,
                                            annotation_format,
                                            file_name = NULL,
                                            promotor_width,
                                            replaceUnstranded = "+") {
  
  if (!is.element(annotation_format, c("gtf", "gff", "gff3")))
    stop("Please specify annotation_file = 'gtf', annotation_file = 'gff' or annotation_file = 'gff3' since no other format is supported yet.", call. = FALSE)
  
  message("Starting extraction of upstream promotor sequences of length ", promotor_width, " for all ", organism, " genes ...")
  message("Importing annotation file ", annotation_file, " in ", annotation_format, " format.")
  
  if (!file.exists(genome_file))
    stop("Please provide a valid path to the genome assembly file.", call. = FALSE)
  
  if (!file.exists(genome_file))
    stop("Please provide a valid path to the annotation file.", call. = FALSE)
  
  tryCatch({
  annotation <-
    rtracklayer::import(annotation_file)
  }, error = function(e) stop("The function 'rtracklayer::import()' was unable to import the specified annotation file. Could it be that your file is still in *.gz format. Please unzip your files before use.", call. = FALSE))
  
  if (!file.exists(paste0(genome_file, ".fai"))) {
    message("Generate genome index file for ", genome_file)
    tryCatch(
      Rsamtools::indexFa(genome_file),
      error = function(e) {
        warning("The function Rsamtools::indexFa() is not able to generate a fasta index.", call. = FALSE)
        message("Running samtools directly to generate genome index file for ", genome_file)
        is_samtools_installed()
        system(paste("samtools faidx ", genome_file))
      }
    )
  }
  
  fasta_idx <- Rsamtools::FaFile(genome_file)
  
  message("If present, then unassigned strand information ('*') will be replaced by '", replaceUnstranded,"'.")
  # if strand information is missing replace with "+" or "-", defined in replaceUnstranded
  if (sum(as.character(annotation@strand@values) %in% c("+", "-")) == 0) {
    if (!is.element(replaceUnstranded, c("+", "-"))) {
      stop("The parameter \"replaceUnstranded\" can only assigned to the values \"+\" or \"-\"")
    }
    annotation@strand[which(as.character(annotation@strand) %in% "*")] <-
      replaceUnstranded
  }
  
  message("Running quality control on imported annotation file by removing multipart transcripts that have different strand information ...")
  
  type <- gene_biotype <- source <- NULL
  annotation_df <- dplyr::filter(as.data.frame(annotation), type == "gene", gene_biotype == "protein_coding", source %in% c("phytozomev11", "DevSeq"))
  
  if (!"gene_id" %in% names(annotation_df))
    stop("It seems like your ", annotation_format, " file does not have the column name 'gene_id' which is required to callpse transcripts accroding to a gene locus.", call. = FALSE)
      
  # gene_id <- '.' <- NULL
  # annotation_clean <- dplyr::do(dplyr::group_by(annotation_df, gene_id), remove_multipart_transcripts(.))
  # 
  message("Generating TxDbFromGRanges ...")
  
  tryCatch({
  gr_db <-
    GenomicFeatures::makeTxDbFromGRanges(
      GenomicRanges::makeGRangesFromDataFrame(
        annotation_df,
        keep.extra.columns = TRUE,
        seqnames.field = "seqnames"
      )
    )
  }, error = function(e) stop("The function 'GenomicFeatures::makeTxDbFromGRanges()' was unable to generate a TxDbFromGRanges. There might be a corrupt entry in the specified annotation file ", annotation_file, "'.", call. = FALSE))
  
  message("Extracting gene loci ...")
  genes <- GenomicFeatures::genes(x = gr_db)
  
  message("Extracting promotor loci ", promotor_width, "bp upstream of TSS ..")
  
  tryCatch({
  seqs <-
    GenomicFeatures::extractUpstreamSeqs(x = fasta_idx, genes = genes, width = promotor_width)
  }, error = function(e) stop("The function 'GenomicFeatures::extractUpstreamSeqs()' was unable to extract upstream promotor sequences from your 'genome_file'. Could it be that your file is still in *.gz format. Please unzip your files before use.", call. = FALSE))
  
  if (is.null(file_name))
    file_name <- file.path(getwd(), paste0(unlist(stringr::str_replace_all(organism, " ", "_")), "_all_genes_promotor_seqs_", promotor_width, ".fa"))
  
  message("Storing promotor seqs of all ", organism, " genes at ", file_name)
  Biostrings::writeXStringSet(
    x = seqs,
    filepath = file_name
  )
  
  RSQLite::dbDisconnect(gr_db$conn)
  return(file_name)
}
