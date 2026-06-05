process COVERM_PLASMID {
    label 'high'   // all BAMs collected

    publishDir "${params.outdir}/abundance", mode: 'copy'
    publishDir "${params.outdir}/logs",      mode: 'copy', pattern: '*.log'

    input:
    path bam_files
    path bai_files
    path mge_fna

    output:
    path "plasmid_abundance.tsv", emit: abundance
    path "coverm_plasmid.log",    emit: log

    script:
    """
    coverm genome \
        --bam-files ${bam_files} \
        --genome-fasta-files ${mge_fna} \
        --genome-fasta-extension fna \
        --methods rpkm tpm covered_fraction \
        --min-read-percent-identity ${params.coverm_min_identity_plasmid} \
        --threads ${task.cpus} \
        --output-file plasmid_abundance_raw.tsv \
        2> coverm_plasmid.log

    # Keep only plasmid contigs (headers contain 'plasmid' from geNomad naming)
    head -1 plasmid_abundance_raw.tsv > plasmid_abundance.tsv
    grep -i 'plasmid' plasmid_abundance_raw.tsv >> plasmid_abundance.tsv || true
    """

    stub:
    """
    touch plasmid_abundance.tsv
    touch coverm_plasmid.log
    """
}
