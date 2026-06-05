process BUILD_INDEX {
    tag "${sample_id}"
    label 'medium'

    publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'

    input:
    tuple val(sample_id), path(mge_fna)
    val aligner   // 'strobealign' | 'bwamem2' | 'bowtie2'

    output:
    tuple val(sample_id), path("${sample_id}_mge_index*"), val(aligner), emit: index
    path "${sample_id}_build_index.log",                                  emit: log

    script:
    if (aligner == 'strobealign')
        """
        # strobealign indexes on-the-fly; copy reference as the 'index'
        cp ${mge_fna} ${sample_id}_mge_index.fna
        echo "strobealign: using reference directly (no pre-index step)" \
            > ${sample_id}_build_index.log
        """
    else if (aligner == 'bwamem2')
        """
        bwa-mem2 index -p ${sample_id}_mge_index ${mge_fna} \
            2> ${sample_id}_build_index.log
        """
    else   // bowtie2
        """
        bowtie2-build --threads ${task.cpus} \
            ${mge_fna} ${sample_id}_mge_index \
            2> ${sample_id}_build_index.log
        """
}
