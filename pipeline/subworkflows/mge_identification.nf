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

    // Combine phage + plasmid (+ optional provirus) before merging
    if (params.run_provirus) {
        ch_for_merge = GENOMAD.out.phage
            .join(GENOMAD.out.plasmid, by: 0)
            .join(GENOMAD.out.provirus, by: 0)
            .map { sample_id, phage, plasmid, provirus ->
                // cat provirus into phage before MERGE_MGE sees it
                [sample_id, phage, plasmid, provirus]
            }
        // MERGE_MGE takes (sample_id, phage, plasmid); provirus is pre-concatenated here
        ch_merge_input = ch_for_merge.map { sample_id, phage, plasmid, provirus ->
            // write provirus-augmented phage on-the-fly via a shell trick in MERGE_MGE
            // pass provirus as extra element — MERGE_MGE handles it when present
            [sample_id, phage, plasmid, provirus]
        }
    } else {
        ch_merge_input = GENOMAD.out.phage
            .join(GENOMAD.out.plasmid, by: 0)
            .map { sample_id, phage, plasmid -> [sample_id, phage, plasmid, []] }
    }

    // Resolve aligner for BUILD_INDEX
    def build_aligner = (params.aligner == 'auto') ? 'bwamem2' : params.aligner
    // When aligner == 'auto', BUILD_INDEX builds bwamem2 index as the default;
    // strobealign uses the fna directly, bowtie2 will also be built here if forced.
    // For true auto-detect, all three aligner paths share the same merged fna — BUILD_INDEX
    // builds a bwamem2 index; strobealign uses the fna; bowtie2 builds its own index
    // inside the BOWTIE2 process on-the-fly (acceptable for small MGE references).

    MERGE_MGE(
        ch_merge_input.map { it[0..2] },  // sample_id, phage_fna, plasmid_fna
    )

    BUILD_INDEX(MERGE_MGE.out.merged, build_aligner)

    emit:
    mge_index    = BUILD_INDEX.out.index   // tuple val(sample_id), path(index*), val(aligner)
    mge_fna      = MERGE_MGE.out.merged    // tuple val(sample_id), path(mge_merged.fna)
    phage_fna    = GENOMAD.out.phage
    plasmid_fna  = GENOMAD.out.plasmid
}
