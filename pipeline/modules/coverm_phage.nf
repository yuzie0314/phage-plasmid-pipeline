process COVERM_PHAGE {
    label 'high'   // all BAMs collected

    publishDir "${params.outdir}/abundance", mode: 'copy'
    publishDir "${params.outdir}/logs",      mode: 'copy', pattern: '*.log'

    input:
    path bam_files   // collected sorted BAMs from all samples (*.bam)
    path bai_files   // corresponding .bai index files
    path mge_fna     // merged MGE reference (for --genome-fasta-files if needed)

    output:
    path "phage_abundance.tsv", emit: abundance
    path "coverm_phage.log",    emit: log

    script:
    """
    coverm genome \
        --bam-files ${bam_files} \
        --genome-fasta-files ${mge_fna} \
        --genome-fasta-extension fna \
        --methods rpkm tpm covered_fraction \
        --min-read-percent-identity ${params.coverm_min_identity_phage} \
        --threads ${task.cpus} \
        --output-file phage_abundance_raw.tsv \
        2> coverm_phage.log

    # Keep only phage contigs (headers contain 'virus' from geNomad naming)
    head -1 phage_abundance_raw.tsv > phage_abundance.tsv
    grep -i 'virus\|phage' phage_abundance_raw.tsv >> phage_abundance.tsv || true
    """

    stub:
    """
    touch phage_abundance.tsv
    touch coverm_phage.log
    """
}
