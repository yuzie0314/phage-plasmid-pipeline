process STROBEALIGN {
    tag "${sample_id}"
    label 'medium'

    publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'

    input:
    tuple val(sample_id), path(r1), path(r2), path(index_files)

    output:
    tuple val(sample_id), path("${sample_id}.bam"), emit: bam
    path "${sample_id}_strobealign.log",             emit: log

    script:
    // index_files is the reference fna (strobealign indexes on-the-fly)
    def ref = index_files.find { it.name.endsWith('.fna') } ?: index_files[0]
    """
    strobealign \
        --threads ${task.cpus} \
        ${ref} ${r1} ${r2} \
        2> ${sample_id}_strobealign.log \
    | samtools view -bS -o ${sample_id}.bam
    """

    stub:
    """
    touch ${sample_id}.bam
    touch ${sample_id}_strobealign.log
    """
}
