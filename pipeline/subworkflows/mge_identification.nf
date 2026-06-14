include { FILTER_CONTIGS } from '../modules/filter_contigs'
include { GENOMAD        } from '../modules/genomad'
include { MERGE_MGE      } from '../modules/merge_mge'
include { BUILD_INDEX    } from '../modules/build_index'

workflow MGE_IDENTIFICATION {

    take:
    ch_contigs   // tuple val(sample_id), path(contigs.fna)
    genomad_db   // path

    main:
    FILTER_CONTIGS(ch_contigs)

    GENOMAD(FILTER_CONTIGS.out.filtered, genomad_db)

    // Combine phage + plasmid + optional provirus for MERGE_MGE
    // When run_provirus = false, pass an empty placeholder so MERGE_MGE signature is stable
    ch_phage_plasmid = GENOMAD.out.phage.join(GENOMAD.out.plasmid, by: 0)

    if (params.run_provirus) {
        ch_merge_input = ch_phage_plasmid
            .join(GENOMAD.out.provirus, by: 0)
    } else {
        ch_merge_input = ch_phage_plasmid
            .map { sample_id, phage, plasmid ->
                [sample_id, phage, plasmid, file("${projectDir}/assets/empty.fna")]
            }
    }

    // In auto mode, strobealign (≥150 bp reads) is the most common path and
    // indexes on-the-fly from the FNA — no pre-built index needed. Build a
    // strobealign "index" (FNA copy, <1 s) so BUILD_INDEX always produces output.
    // BWAMEM2 and BOWTIE2 detect the FNA at runtime and build their own index.
    def build_aligner = (params.aligner == 'auto') ? 'strobealign' : params.aligner

    MERGE_MGE(ch_merge_input)

    BUILD_INDEX(MERGE_MGE.out.merged, build_aligner)

    emit:
    mge_index    = BUILD_INDEX.out.index   // tuple val(sample_id), path(index*), val(aligner)
    mge_fna      = MERGE_MGE.out.merged    // tuple val(sample_id), path(mge_merged.fna)
    phage_fna    = GENOMAD.out.phage
    plasmid_fna  = GENOMAD.out.plasmid
}
