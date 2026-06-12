process COVERM_PHAGE {
    label 'high'   // all BAMs collected

    publishDir "${params.outdir}/abundance", mode: 'copy'
    publishDir "${params.outdir}/logs",      mode: 'copy', pattern: '*.log'

    input:
    path bam_files   // collected sorted BAMs from all samples (*.bam)
    path bai_files   // corresponding .bai index files
    path mge_fna     // collected per-sample virus_sequences.fna files for contig ID filtering

    output:
    path "phage_abundance.tsv", emit: abundance
    path "coverm_phage.log",    emit: log

    script:
    """
    # Extract phage contig IDs from all per-sample virus FNAs
    cat ${mge_fna} | grep "^>" | sed 's/^>//' | cut -d' ' -f1 > phage_ids.txt

    coverm contig \
        --bam-files ${bam_files} \
        --methods rpkm tpm covered_fraction \
        --min-read-percent-identity ${params.coverm_min_identity_phage} \
        --threads ${task.cpus} \
        --output-file phage_abundance_raw.tsv \
        2> coverm_phage.log

    # Keep only phage contigs
    head -1 phage_abundance_raw.tsv > phage_abundance.tsv
    grep -Ff phage_ids.txt phage_abundance_raw.tsv >> phage_abundance.tsv || true
    """

    stub:
    """
    touch phage_abundance.tsv
    touch coverm_phage.log
    """
}
