process QC_TRIM {
    tag "${sample_id}"
    label 'medium'

    publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
    publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.json'

    input:
    tuple val(sample_id), path(r1), path(r2)

    output:
    tuple val(sample_id), path("${sample_id}_trimmed_R1.fastq.gz"), path("${sample_id}_trimmed_R2.fastq.gz"), emit: trimmed
    path "${sample_id}_fastp.json", emit: report
    path "${sample_id}_fastp.log",  emit: log

    script:
    def extra = params.fastp_extra_args ?: ''
    """
    fastp \
        --in1 ${r1} \
        --in2 ${r2} \
        --out1 ${sample_id}_trimmed_R1.fastq.gz \
        --out2 ${sample_id}_trimmed_R2.fastq.gz \
        --json ${sample_id}_fastp.json \
        --thread ${task.cpus} \
        --detect_adapter_for_pe \
        ${extra} \
        2> ${sample_id}_fastp.log
    """

    stub:
    """
    touch ${sample_id}_trimmed_R1.fastq.gz
    touch ${sample_id}_trimmed_R2.fastq.gz
    touch ${sample_id}_fastp.json
    touch ${sample_id}_fastp.log
    """
}
