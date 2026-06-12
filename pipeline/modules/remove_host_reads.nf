process REMOVE_HOST_READS {
    tag "${sample_id}"
    label 'high'   // hg38 bitmask index loading requires ~24 GB RAM

    storeDir   "${projectDir}/../results/.bmtagger_storeDir/${params.reads_mode}/${sample_id}"
    publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'

    input:
    tuple val(sample_id), path(r1), path(r2)
    // val inputs: paths are NOT staged into work dir (NFS files stay in place)
    // Singularity accesses them via bind mount (autoMounts or params.singularity_bind_paths)
    val bitmask_file    // absolute path to hg38.bitmask FILE
    val srprism_prefix  // absolute path to srprism index PREFIX (e.g. /nfs/hg38_bmtagger/hg38.srprism)

    output:
    tuple val(sample_id), path("${sample_id}_hostfree_R1.fastq.gz"), path("${sample_id}_hostfree_R2.fastq.gz"), emit: host_removed
    path "${sample_id}_bmtagger.log", emit: log

    script:
    """
    # bmtagger requires uncompressed fastq
    zcat ${r1} > r1.fastq
    zcat ${r2} > r2.fastq

    mkdir -p tmp_bmtagger
    bmtagger.sh \
        -b ${bitmask_file} \
        -x ${srprism_prefix} \
        -T tmp_bmtagger \
        -q 1 \
        -X \
        -1 r1.fastq \
        -2 r2.fastq \
        -o host_removed \
        2> ${sample_id}_bmtagger.log

    gzip -c host_removed_1.fastq > ${sample_id}_hostfree_R1.fastq.gz
    gzip -c host_removed_2.fastq > ${sample_id}_hostfree_R2.fastq.gz

    rm -f r1.fastq r2.fastq host_removed_1.fastq host_removed_2.fastq
    """

    stub:
    """
    touch ${sample_id}_hostfree_R1.fastq.gz
    touch ${sample_id}_hostfree_R2.fastq.gz
    touch ${sample_id}_bmtagger.log
    """
}
