#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { MGE_IDENTIFICATION } from './subworkflows/mge_identification'
include { MGE_ABUNDANCE      } from './subworkflows/mge_abundance'

// ── PARAMETER VALIDATION ──────────────────────────────────────────────────────
def validate_params() {
    if (!params.input)       error "ERROR: --input samplesheet is required"
    if (!params.genomad_db)  error "ERROR: --genomad_db is required"

    if (params.reads_mode in ['host_removed', 'trimmed_host_removed']) {
        if (!params.host_genome_bitmask)
            error "ERROR: --host_genome_bitmask required for reads_mode '${params.reads_mode}'\n" +
                  "       Provide the absolute path to the .bitmask FILE, e.g. /nfs/hg38_bmtagger/hg38.bitmask"
        if (!params.host_genome_srprism)
            error "ERROR: --host_genome_srprism required for reads_mode '${params.reads_mode}'\n" +
                  "       Provide the srprism index PREFIX (no extension), e.g. /nfs/hg38_bmtagger/hg38.srprism"
        if (!file(params.host_genome_bitmask).exists())
            error "ERROR: --host_genome_bitmask file not found: ${params.host_genome_bitmask}"
        if (!file(params.host_genome_srprism + ".amp").exists())
            error "ERROR: --host_genome_srprism index not found: ${params.host_genome_srprism}.amp\n" +
                  "       Expected files: ${params.host_genome_srprism}.amp/.idx/.map/.pmp/.rmp/.ssd"
    }

    def valid_modes    = ['raw', 'host_removed', 'trimmed_host_removed']
    def valid_aligners = ['auto', 'strobealign', 'bwamem2', 'bowtie2']
    if (!(params.reads_mode in valid_modes))    error "ERROR: reads_mode must be one of ${valid_modes}"
    if (!(params.aligner    in valid_aligners)) error "ERROR: aligner must be one of ${valid_aligners}"
}

// ── SAMPLESHEET PARSING ───────────────────────────────────────────────────────
def parse_samplesheet(csv_path) {
    Channel
        .fromPath(csv_path)
        .splitCsv(header: true)
        .map { row ->
            def required = ['sample_id', 'fastq_1', 'fastq_2', 'contigs']
            required.each { col ->
                if (!row.containsKey(col) || !row[col])
                    error "Samplesheet missing column or value: ${col} (row: ${row})"
            }
            [row.sample_id, row.fastq_1, row.fastq_2, row.contigs]
        }
}

// ── WORKFLOW ──────────────────────────────────────────────────────────────────
workflow {

    validate_params()

    ch_samplesheet = parse_samplesheet(params.input)

    // Split into contigs channel and reads channel (joined by sample_id)
    ch_contigs   = ch_samplesheet.map { sample_id, r1, r2, contigs -> [sample_id, file(contigs)] }
    ch_raw_reads = ch_samplesheet.map { sample_id, r1, r2, contigs -> [sample_id, file(r1), file(r2)] }

    genomad_db = file(params.genomad_db)

    // ── STAGE 1: Identification ───────────────────────────────────────────────
    MGE_IDENTIFICATION(ch_contigs, genomad_db)

    // ── STAGE 2: Abundance ────────────────────────────────────────────────────
    MGE_ABUNDANCE(
        ch_raw_reads,
        MGE_IDENTIFICATION.out.mge_index,
        MGE_IDENTIFICATION.out.mge_fna,
        MGE_IDENTIFICATION.out.phage_fna,
        MGE_IDENTIFICATION.out.plasmid_fna
    )

    // ── MultiQC emit (consumed by de novo pipeline) ───────────────────────────
    if (params.multiqc_emit) {
        MGE_ABUNDANCE.out.flagstat.view { "MultiQC flagstat: ${it}" }
        MGE_ABUNDANCE.out.aln_log .view { "MultiQC aln_log:  ${it}" }
    }
}
