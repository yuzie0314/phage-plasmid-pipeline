process SAMTOOLS_SORT {
    tag "${sample_id}"
    label 'low'

    publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'

    input:
    tuple val(sample_id), path(bam)

    output:
    tuple val(sample_id), path("${sample_id}_sorted.bam"), path("${sample_id}_sorted.bam.bai"), emit: sorted_bam
    path "${sample_id}_samtools_sort.log", emit: log

    script:
    """
    samtools sort \
        -@ ${task.cpus} \
        -o ${sample_id}_sorted.bam \
        ${bam} \
        2> ${sample_id}_samtools_sort.log
    samtools index ${sample_id}_sorted.bam 2>> ${sample_id}_samtools_sort.log
    """
}
