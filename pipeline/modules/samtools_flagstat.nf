process SAMTOOLS_FLAGSTAT {
    tag "${sample_id}"
    label 'low'

    publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.txt'

    input:
    tuple val(sample_id), path(sorted_bam), path(bai)

    output:
    tuple val(sample_id), path("${sample_id}_flagstat.txt"), emit: txt

    script:
    """
    samtools flagstat \
        -@ ${task.cpus} \
        ${sorted_bam} \
        > ${sample_id}_flagstat.txt
    """
}
