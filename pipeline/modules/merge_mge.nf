process MERGE_MGE {
    tag "${sample_id}"
    label 'low'

    publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'

    input:
    tuple val(sample_id), path(phage_fna), path(plasmid_fna)
    // provirus_fna passed separately (optional); callers cat it in when params.run_provirus = true

    output:
    tuple val(sample_id), path("${sample_id}_mge_merged.fna"), emit: merged
    path "${sample_id}_merge_mge.log",                          emit: log

    script:
    """
    cat ${phage_fna} ${plasmid_fna} > ${sample_id}_mge_merged.fna
    echo "Merged phage (${phage_fna}) + plasmid (${plasmid_fna}) → ${sample_id}_mge_merged.fna" \
        > ${sample_id}_merge_mge.log
    seqkit stats -T ${sample_id}_mge_merged.fna >> ${sample_id}_merge_mge.log
    """
}
