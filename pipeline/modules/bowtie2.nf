process BOWTIE2 {
    tag "${sample_id}"
    label 'medium'

    publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'

    input:
    tuple val(sample_id), path(r1), path(r2), path(index_files)

    output:
    tuple val(sample_id), path("${sample_id}.bam"), emit: bam
    path "${sample_id}_bowtie2.log",                emit: log

    script:
    // Derive the bowtie2 index prefix from the .1.bt2 file
    """
    idx_prefix=\$(ls *.1.bt2 2>/dev/null | sed 's/\\.1\\.bt2//' | head -1)
    bowtie2 \
        -p ${task.cpus} \
        -x \${idx_prefix} \
        -1 ${r1} -2 ${r2} \
        2> ${sample_id}_bowtie2.log \
    | samtools view -bS -o ${sample_id}.bam
    """
}
