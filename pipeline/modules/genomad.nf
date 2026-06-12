process GENOMAD {
    tag "${sample_id}"
    label 'medium'

    // geNomad runs on contigs (assembly), independent of reads_mode.
    // Use a shared storeDir so results are reused across all reads_mode runs.
    storeDir "${projectDir}/../results/.genomad_storeDir"

    publishDir "${params.outdir}/genomad/${sample_id}", mode: 'copy', pattern: '*_summary.tsv'
    publishDir "${params.outdir}/genomad/${sample_id}", mode: 'copy', pattern: '*_sequences.fna'
    publishDir "${params.outdir}/annotation",           mode: 'copy', pattern: '*_genomad_annotation.tsv'
    publishDir "${params.outdir}/logs",                 mode: 'copy', pattern: '*.log'

    input:
    tuple val(sample_id), path(filtered_contigs)
    path genomad_db

    output:
    tuple val(sample_id), path("${sample_id}_virus_sequences.fna"),    emit: phage
    tuple val(sample_id), path("${sample_id}_plasmid_sequences.fna"),  emit: plasmid
    tuple val(sample_id), path("${sample_id}_provirus_sequences.fna"), emit: provirus, optional: true
    path "${sample_id}_virus_summary.tsv",                              emit: virus_summary
    path "${sample_id}_plasmid_summary.tsv",                            emit: plasmid_summary
    path "${sample_id}_genomad_annotation.tsv",                         emit: annotation
    path "${sample_id}_genomad.log",                                    emit: log

    script:
    def provirus_flag = params.run_provirus ? '--enable-score-calibration' : ''
    """
    genomad end-to-end \
        ${filtered_contigs} \
        genomad_out \
        ${genomad_db} \
        --threads ${task.cpus} \
        --splits 8 \
        ${provirus_flag} \
        2> ${sample_id}_genomad.log

    # Rename outputs to sample-prefixed names
    mv genomad_out/${filtered_contigs.baseName}_summary/  \
       ${filtered_contigs.baseName}_summary/ 2>/dev/null || true

    cp genomad_out/${filtered_contigs.baseName}_find_proviruses/${filtered_contigs.baseName}_provirus.fna \
       ${sample_id}_provirus_sequences.fna 2>/dev/null || true

    # Flatten geNomad output paths to flat files with sample_id prefix
    find . -name '*virus_summary.tsv'    | head -1 | xargs -I{} cp {} ${sample_id}_virus_summary.tsv
    find . -name '*plasmid_summary.tsv'  | head -1 | xargs -I{} cp {} ${sample_id}_plasmid_summary.tsv
    find . -name '*virus.fna'     ! -name '*provirus*' | head -1 | xargs -I{} cp {} ${sample_id}_virus_sequences.fna
    find . -name '*plasmid.fna'          | head -1 | xargs -I{} cp {} ${sample_id}_plasmid_sequences.fna
    ln genomad_out/${filtered_contigs.baseName}_annotate/${filtered_contigs.baseName}_genes.tsv \
       ${sample_id}_genomad_annotation.tsv
    """

    stub:
    """
    touch ${sample_id}_virus_sequences.fna
    touch ${sample_id}_plasmid_sequences.fna
    touch ${sample_id}_virus_summary.tsv
    touch ${sample_id}_plasmid_summary.tsv
    touch ${sample_id}_genomad_annotation.tsv
    touch ${sample_id}_genomad.log
    """
}
