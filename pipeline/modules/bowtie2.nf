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
    // Use pre-built index (.1.bt2 present) or build on-the-fly from a FNA reference.
    // Pre-built: --aligner bowtie2 (BUILD_INDEX ran bowtie2-build beforehand).
    // On-the-fly: --aligner auto (BUILD_INDEX produced a FNA copy; index built here).
    """
    if ls *.1.bt2 2>/dev/null | grep -q .; then
        idx_prefix=\$(ls *.1.bt2 | sed 's/\\.1\\.bt2//' | head -1)
    else
        fna=\$(ls *.fna 2>/dev/null | head -1)
        bowtie2-build --threads ${task.cpus} "\${fna}" bowtie2_idx 2>> ${sample_id}_bowtie2.log
        idx_prefix=bowtie2_idx
    fi
    bowtie2 \
        -p ${task.cpus} \
        -x "\${idx_prefix}" \
        -1 ${r1} -2 ${r2} \
        2>> ${sample_id}_bowtie2.log \
    | samtools view -bS -o ${sample_id}.bam
    """

    stub:
    """
    touch ${sample_id}.bam
    touch ${sample_id}_bowtie2.log
    """
}
