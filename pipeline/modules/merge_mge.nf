process MERGE_MGE {
    tag "${sample_id}"
    label 'low'

    publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'

    input:
    tuple val(sample_id), path(phage_fna), path(plasmid_fna), path(provirus_fna)
    // provirus_fna is pipeline/assets/empty.fna when run_provirus = false (contributes nothing to cat)

    output:
    tuple val(sample_id), path("${sample_id}_mge_merged.fna"), emit: merged
    path "${sample_id}_merge_mge.log",                          emit: log

    script:
    """
    cat ${phage_fna} ${plasmid_fna} ${provirus_fna} > ${sample_id}_mge_merged.fna
    echo "Merged phage + plasmid${provirus_fna.size() > 0 ? ' + provirus' : ''} → ${sample_id}_mge_merged.fna" \
        > ${sample_id}_merge_mge.log
    seqkit stats -T ${sample_id}_mge_merged.fna >> ${sample_id}_merge_mge.log
    """

    stub:
    """
    touch ${sample_id}_mge_merged.fna
    touch ${sample_id}_merge_mge.log
    """
}
