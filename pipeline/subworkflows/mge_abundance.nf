include { QC_TRIM           } from '../modules/qc_trim'
include { REMOVE_HOST_READS } from '../modules/remove_host_reads'
include { DETECT_READ_LENGTH} from '../modules/detect_read_length'
include { STROBEALIGN       } from '../modules/strobealign'
include { BWAMEM2           } from '../modules/bwamem2'
include { BOWTIE2           } from '../modules/bowtie2'
include { SAMTOOLS_SORT     } from '../modules/samtools_sort'
include { SAMTOOLS_FLAGSTAT } from '../modules/samtools_flagstat'
include { COVERM_PHAGE      } from '../modules/coverm_phage'
include { COVERM_PLASMID    } from '../modules/coverm_plasmid'

workflow MGE_ABUNDANCE {

    take:
    ch_raw_reads   // tuple val(sample_id), path(r1), path(r2)
    ch_mge_index   // tuple val(sample_id), path(index*), val(aligner)   from MGE_IDENTIFICATION
    ch_mge_fna     // tuple val(sample_id), path(mge_merged.fna)

    main:

    // ── READS PREPROCESSING ──────────────────────────────────────────────────
    if (params.reads_mode == 'trimmed_host_removed') {
        QC_TRIM(ch_raw_reads)
        REMOVE_HOST_READS(
            QC_TRIM.out.trimmed,
            params.host_genome_bitmask,
            params.host_genome_srprism
        )
        ch_reads_for_mapping = REMOVE_HOST_READS.out.host_removed
        ch_fastp_reports     = QC_TRIM.out.report

    } else if (params.reads_mode == 'host_removed') {
        REMOVE_HOST_READS(
            ch_raw_reads,
            params.host_genome_bitmask,
            params.host_genome_srprism
        )
        ch_reads_for_mapping = REMOVE_HOST_READS.out.host_removed
        ch_fastp_reports     = Channel.empty()

    } else {  // 'raw'
        ch_reads_for_mapping = ch_raw_reads
        ch_fastp_reports     = Channel.empty()
    }

    // ── ALIGNER ROUTING ──────────────────────────────────────────────────────
    // Join reads with their per-sample index
    ch_reads_with_index = ch_reads_for_mapping
        .join(ch_mge_index, by: 0)
        // result: tuple val(sample_id), path(r1), path(r2), path(index*), val(aligner)

    if (params.aligner == 'auto') {
        DETECT_READ_LENGTH(ch_reads_for_mapping)

        // Combine read-length result with the reads+index channel
        ch_with_len = DETECT_READ_LENGTH.out.read_length
            .join(ch_reads_with_index, by: 0)
            // tuple val(sample_id), val(avg_len), path(r1), path(r2), path(index*), val(aligner)

        ch_branched = ch_with_len.branch {
            strobealign: it[1].toInteger() >= params.strobealign_min_len
            bwamem2:     it[1].toInteger() >= params.bwamem2_min_len
            bowtie2:     true
        }

        // Emit aligner_selection.log per sample
        ch_aligner_selection_log = DETECT_READ_LENGTH.out.log

        // Map each branch to (sample_id, r1, r2, index_files)
        ch_strobealign_input = ch_branched.strobealign.map { it[0,2,3,4] }
        ch_bwamem2_input     = ch_branched.bwamem2    .map { it[0,2,3,4] }
        ch_bowtie2_input     = ch_branched.bowtie2    .map { it[0,2,3,4] }

        STROBEALIGN(ch_strobealign_input)
        BWAMEM2    (ch_bwamem2_input)
        BOWTIE2    (ch_bowtie2_input)

        ch_raw_bam = STROBEALIGN.out.bam
            .mix(BWAMEM2.out.bam)
            .mix(BOWTIE2.out.bam)

    } else {
        ch_aligner_selection_log = Channel.empty()

        ch_input = ch_reads_with_index.map { it[0,1,2,3] }  // drop aligner val

        if (params.aligner == 'strobealign') {
            STROBEALIGN(ch_input)
            ch_raw_bam = STROBEALIGN.out.bam
        } else if (params.aligner == 'bwamem2') {
            BWAMEM2(ch_input)
            ch_raw_bam = BWAMEM2.out.bam
        } else {
            BOWTIE2(ch_input)
            ch_raw_bam = BOWTIE2.out.bam
        }
    }

    // ── SORT + FLAGSTAT ───────────────────────────────────────────────────────
    SAMTOOLS_SORT(ch_raw_bam)
    SAMTOOLS_FLAGSTAT(SAMTOOLS_SORT.out.sorted_bam)

    // ── COLLECT ALL BAMs → COVERM ─────────────────────────────────────────────
    ch_sorted_bams = SAMTOOLS_SORT.out.sorted_bam
        .map { sample_id, bam, bai -> [bam, bai] }
        .collect()
        .map { files ->
            def bams = files.findAll { it.name.endsWith('.bam') }
            def bais = files.findAll { it.name.endsWith('.bai') }
            [bams, bais]
        }

    // Use first sample's mge_fna as the shared reference for CoverM
    ch_mge_fna_single = ch_mge_fna.map { sample_id, fna -> fna }.first()

    COVERM_PHAGE(
        ch_sorted_bams.map { it[0] },
        ch_sorted_bams.map { it[1] },
        ch_mge_fna_single
    )
    COVERM_PLASMID(
        ch_sorted_bams.map { it[0] },
        ch_sorted_bams.map { it[1] },
        ch_mge_fna_single
    )

    emit:
    phage_abundance   = COVERM_PHAGE.out.abundance
    plasmid_abundance = COVERM_PLASMID.out.abundance
    flagstat          = SAMTOOLS_FLAGSTAT.out.txt    // ch_flagstat_mge  (for MultiQC)
    aln_log           = ch_aligner_selection_log     // ch_aligner_log_mge (for MultiQC)
    fastp_reports     = ch_fastp_reports
}
