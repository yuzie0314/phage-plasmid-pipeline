process COVERM_MGE {
    label 'high'   // all BAMs collected

    publishDir "${params.outdir}/abundance", mode: 'copy'
    publishDir "${params.outdir}/logs",      mode: 'copy', pattern: '*.log'

    input:
    path bam_files      // collected sorted BAMs from all samples
    path bai_files      // corresponding .bai index files
    path mge_fna        // collected per-sample FNA files for contig ID filtering
    val  mge_type       // 'phage' | 'plasmid'
    val  min_identity   // coverm --min-read-percent-identity value

    output:
    path "${mge_type}_abundance.tsv", emit: abundance
    path "coverm_${mge_type}.log",    emit: log

    script:
    """
    cat ${mge_fna} | grep "^>" | sed 's/^>//' | cut -d' ' -f1 > ${mge_type}_ids.txt

    coverm contig \
        --bam-files ${bam_files} \
        --methods rpkm tpm covered_fraction \
        --min-read-percent-identity ${min_identity} \
        --threads ${task.cpus} \
        --output-file ${mge_type}_abundance_raw.tsv \
        2> coverm_${mge_type}.log

    head -1 ${mge_type}_abundance_raw.tsv > ${mge_type}_abundance.tsv
    grep -Ff ${mge_type}_ids.txt ${mge_type}_abundance_raw.tsv >> ${mge_type}_abundance.tsv || true
    """

    stub:
    """
    touch ${mge_type}_abundance.tsv
    touch coverm_${mge_type}.log
    """
}
