process FILTER_CONTIGS {
    tag "${sample_id}"
    label 'low'

    publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'

    input:
    tuple val(sample_id), path(contigs)

    output:
    tuple val(sample_id), path("${sample_id}_filtered.fna"), emit: filtered
    path "${sample_id}_filter_contigs.log",                  emit: log

    script:
    """
    seqkit seq \
        --min-len ${params.min_contig_length} \
        --out-file ${sample_id}_filtered.fna \
        ${contigs} \
        2> ${sample_id}_filter_contigs.log
    """
}
