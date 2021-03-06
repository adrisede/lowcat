% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/io_and_formats.R
\name{run_se_to_cuts_parallel}
\alias{run_se_to_cuts_parallel}
\title{Read single-end BAM files to GenomicRanges objects in parallel}
\usage{
run_se_to_cuts_parallel(bam_files, sample_names = NULL, n_cores = 6)
}
\arguments{
\item{bam_files}{a vector of bam file locations}

\item{sample_names}{Sample names. If NULL, will use BAM file names.}

\item{n_cores}{The number of cores to use in parallel. Use "auto" to detect and use all cores. Default is 6.}
}
\value{
a list of GenomicRanges objects
}
\description{
Read single-end BAM files to GenomicRanges objects in parallel
}
