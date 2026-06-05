process BWAMEM2 {
    tag "${sample_id}"
    label 'medium'

    publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'

    input:
    tuple val(sample_id), path(r1), path(r2), path(index_files)

    output:
    tuple val(sample_id), path("${sample_id}.bam"), emit: bam
    path "${sample_id}_bwamem2.log",                emit: log

    script:
    // Derive the index prefix from the .amb file (always present after bwa-mem2 index)
    """
    idx_prefix=\$(ls *.amb 2>/dev/null | sed 's/\\.amb//' | head -1)
    bwa-mem2 mem \
        -t ${task.cpus} \
        \${idx_prefix} ${r1} ${r2} \
        2> ${sample_id}_bwamem2.log \
    | samtools view -bS -o ${sample_id}.bam
    """
}
