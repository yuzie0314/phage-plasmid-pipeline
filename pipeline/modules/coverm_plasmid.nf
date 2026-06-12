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
    # Extract plasmid contig IDs from all per-sample plasmid FNAs
    cat ${mge_fna} | grep "^>" | sed 's/^>//' | cut -d' ' -f1 > plasmid_ids.txt

    coverm contig \
        --bam-files ${bam_files} \
        --methods rpkm tpm covered_fraction \
        --min-read-percent-identity ${params.coverm_min_identity_plasmid} \
        --threads ${task.cpus} \
        --output-file plasmid_abundance_raw.tsv \
        2> coverm_plasmid.log

    # Keep only plasmid contigs
    head -1 plasmid_abundance_raw.tsv > plasmid_abundance.tsv
    grep -Ff plasmid_ids.txt plasmid_abundance_raw.tsv >> plasmid_abundance.tsv || true
    """

    stub:
    """
    touch plasmid_abundance.tsv
    touch coverm_plasmid.log
    """
}
