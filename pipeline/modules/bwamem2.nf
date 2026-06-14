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
    // Use pre-built index (.amb present) or build on-the-fly from a FNA reference.
    // Pre-built: --aligner bwamem2 (BUILD_INDEX ran bwa-mem2 index beforehand).
    // On-the-fly: --aligner auto (BUILD_INDEX produced a FNA copy; index built here).
    """
    if ls *.amb 2>/dev/null | grep -q .; then
        idx_prefix=\$(ls *.amb | sed 's/\\.amb//' | head -1)
    else
        fna=\$(ls *.fna 2>/dev/null | head -1)
        bwa-mem2 index -p bwamem2_idx "\${fna}" 2>> ${sample_id}_bwamem2.log
        idx_prefix=bwamem2_idx
    fi
    bwa-mem2 mem \
        -t ${task.cpus} \
        "\${idx_prefix}" ${r1} ${r2} \
        2>> ${sample_id}_bwamem2.log \
    | samtools view -bS -o ${sample_id}.bam
    """

    stub:
    """
    touch ${sample_id}.bam
    touch ${sample_id}_bwamem2.log
    """
}
