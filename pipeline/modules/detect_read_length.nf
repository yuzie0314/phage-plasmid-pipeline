process DETECT_READ_LENGTH {
    tag "${sample_id}"
    label 'low'

    publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'

    input:
    tuple val(sample_id), path(r1), path(r2)

    output:
    tuple val(sample_id), env(avg_len), emit: read_length
    path "${sample_id}_read_length.log", emit: log

    script:
    """
    avg_len=\$(seqkit head -n 200000 ${r1} | seqkit stats -T | awk 'NR==2{print int(\$7)}')
    echo "${sample_id}\t\${avg_len}" > ${sample_id}_read_length.log
    """

    stub:
    """
    avg_len=150
    echo "${sample_id}\t\${avg_len}" > ${sample_id}_read_length.log
    """
}
