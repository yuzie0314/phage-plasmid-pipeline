# CLAUDE.md — Phage/Plasmid Detection & Abundance Pipeline
> This file guides Claude Code on project context, conventions, and task assignments.
> Update the **Task Assignment** section before each Claude Code session
## 🌐 語言設定
- 請永遠用**繁體中文**回覆我
- 程式碼、變數名稱、函數名稱用英文
- git方面更動用英文
- 程式碼註解用英文
- repo 文件全英文
- 所有解釋、分析、建議用繁體中文

---

## Project Overview

A **Nextflow + Singularity** subworkflow for detecting bacteriophage and plasmid sequences
from metagenomic data, then quantifying their abundance across samples.

**Upstream dependency**: contigs are provided by an existing de novo pipeline (MEGAHIT,
per-sample). This subworkflow does **not** perform QC or assembly — it takes contigs
and raw reads as inputs.

**Key design principles**
- Input: per-sample contigs (from de novo pipeline) + raw reads
- Reads preprocessing: configurable via `params.reads_mode` (see below)
- Singularity container per process (no conda)
- geNomad DB: local NFS mount (read-only)
- hg38 bmtagger index: local NFS mount (read-only)
- Auto-detect avg read length per sample (subsample 200k) → select optimal aligner
- CoverM identity threshold: per-MGE-type (phage 0.85 / plasmid 0.90)
- Provirus detection: optional (`params.run_provirus = false`)
- MultiQC: no separate run; emit samtools flagstat + aligner log into de novo pipeline MultiQC
- Output format mirrors MAG abundance table for unified downstream analysis

---

## Repository Structure

```
pipeline/
├── main.nf
├── nextflow.config
├── conf/
│   ├── base.config             # resource labels: low / medium / high
│   ├── awsbatch.config         # AWS Batch executor (optional)
│   └── singularity.config      # container paths per process
├── modules/
│   ├── filter_contigs.nf       # process: FILTER_CONTIGS (≥ params.min_contig_length)
│   ├── genomad.nf              # process: GENOMAD
│   ├── merge_mge.nf            # process: MERGE_MGE
│   ├── build_index.nf          # process: BUILD_INDEX (aligner-aware)
│   ├── qc_trim.nf              # process: QC_TRIM (fastp) [used when reads_mode includes trim]
│   ├── remove_host_reads.nf    # process: REMOVE_HOST_READS (bmtagger + hg38)
│   ├── detect_read_length.nf   # process: DETECT_READ_LENGTH (seqkit, 200k subsample)
│   ├── strobealign.nf          # process: STROBEALIGN
│   ├── bwamem2.nf              # process: BWAMEM2
│   ├── bowtie2.nf              # process: BOWTIE2
│   ├── samtools_sort.nf        # process: SAMTOOLS_SORT
│   ├── samtools_flagstat.nf    # process: SAMTOOLS_FLAGSTAT (shares samtools.sif)
│   ├── coverm_phage.nf         # process: COVERM_PHAGE   (identity 0.85)
│   └── coverm_plasmid.nf       # process: COVERM_PLASMID (identity 0.90)
├── subworkflows/
│   ├── mge_identification.nf   # FILTER_CONTIGS → GENOMAD → MERGE_MGE → BUILD_INDEX
│   └── mge_abundance.nf        # reads preprocessing → DETECT → branch → map → CoverM
├── assets/
│   └── samplesheet_template.csv
└── bin/
    └── validate_samplesheet.py # samplesheet format validation
```

---

## Samplesheet Format

```csv
sample_id,fastq_1,fastq_2,contigs
sample_A,/data/sampleA_R1.fastq.gz,/data/sampleA_R2.fastq.gz,/data/sampleA_contigs.fna
sample_B,s3://bucket/sampleB_R1.fastq.gz,s3://bucket/sampleB_R2.fastq.gz,s3://bucket/sampleB_contigs.fna
```

- `sample_id`: unique identifier, used as prefix for all output files
- `fastq_1/2`: raw reads (local path or s3://)
- `contigs`: per-sample contigs.fna from de novo pipeline (local path or s3://)
- Mixed local/S3 paths within one samplesheet are supported

---

## Parameters (nextflow.config)

```groovy
params {
    // Input
    input               = null          // path to samplesheet.csv
    input_type          = 'local'       // 'local' | 's3'

    // Output
    outdir              = './results'   // local path or s3://bucket/results

    // Databases (NFS mounts, read-only)
    genomad_db          = null          // NFS path to genomad_db/
    host_genome_bitmask = null          // NFS path to hg38 .bitmask index (bmtagger)
    host_genome_srprism = null          // NFS path to hg38 .srprism index (bmtagger)

    // Contig filtering
    min_contig_length   = 4000          // applied in FILTER_CONTIGS before GENOMAD

    // Reads preprocessing mode
    // 'raw'                    → raw reads directly into mapping
    // 'host_removed'           → bmtagger → mapping
    // 'trimmed_host_removed'   → fastp → bmtagger → mapping
    reads_mode          = 'raw'

    // Aligner selection
    aligner             = 'auto'        // 'auto' | 'strobealign' | 'bwamem2' | 'bowtie2'
    strobealign_min_len = 150
    bwamem2_min_len     = 100

    // Optional modules
    run_provirus        = false

    // CoverM (per-MGE-type — do not use a single global value)
    coverm_min_identity_phage   = 0.85  // phage: high diversity, novel sequences
    coverm_min_identity_plasmid = 0.90  // plasmid: conservative

    // MultiQC (emit to de novo pipeline — do not run separately)
    multiqc_emit        = true
}
```

---

## Pipeline Flow Summary

```
Samplesheet (sample_id, fastq_1, fastq_2, contigs)
      │
      ├─── ch_contigs (sample_id, contigs.fna)
      │         └─ FILTER_CONTIGS (≥ params.min_contig_length)
      │                   └─ GENOMAD (NFS genomad_db)
      │                         ├─ ch_phage_contigs
      │                         ├─ ch_plasmid_contigs
      │                         └─ ch_provirus [if params.run_provirus]
      │                               └─ MERGE_MGE
      │                                     └─ BUILD_INDEX → ch_mge_index
      │
      └─── ch_raw_reads (sample_id, R1, R2)
                │
                ├─ reads_mode = 'raw'
                │       └─ ch_reads_for_mapping
                │
                ├─ reads_mode = 'host_removed'
                │       └─ REMOVE_HOST_READS (bmtagger, hg38 NFS)
                │               └─ ch_reads_for_mapping
                │
                └─ reads_mode = 'trimmed_host_removed'
                        └─ QC_TRIM (fastp)
                                └─ REMOVE_HOST_READS (bmtagger, hg38 NFS)
                                        └─ ch_reads_for_mapping

ch_reads_for_mapping + ch_mge_index
      └─ DETECT_READ_LENGTH (seqkit head -n 200000)
               └─ .branch{}
                     ├─ ≥ 150 bp → STROBEALIGN
                     ├─ ≥ 100 bp → BWAMEM2
                     └─ < 100 bp → BOWTIE2
                           └─ .mix() → SAMTOOLS_SORT + SAMTOOLS_FLAGSTAT
                                 └─ ch_sorted_bams (.collect())
                                       ├─ COVERM_PHAGE   (identity 0.85)
                                       └─ COVERM_PLASMID (identity 0.90)
```

---

## Aligner Auto-Detection Logic

```groovy
// Only runs when params.aligner == 'auto'
// Input: ch_reads_for_mapping (after preprocessing per reads_mode)

ch_reads_for_mapping
  | DETECT_READ_LENGTH    // seqkit head -n 200000 ${r1} | seqkit stats -T
  | branch {
      strobealign: avg_len.toInteger() >= params.strobealign_min_len
      bwamem2:     avg_len.toInteger() >= params.bwamem2_min_len
      bowtie2:     true
  }

// params.aligner != 'auto': skip DETECT_READ_LENGTH, route all to specified aligner

// Emit for MultiQC custom content:
// aligner_selection.log  →  sample_id | avg_len | aligner_used
```

---

## Output File Structure

```
results/
├── genomad/
│   └── {sample_id}/
│       ├── {sample_id}_virus_summary.tsv
│       ├── {sample_id}_plasmid_summary.tsv
│       ├── {sample_id}_virus_sequences.fna
│       ├── {sample_id}_plasmid_sequences.fna
│       └── {sample_id}_provirus_sequences.fna   [if run_provirus]
├── abundance/
│   ├── phage_abundance.tsv      # samples × phage contigs (RPKM + TPM + covered_fraction)
│   └── plasmid_abundance.tsv    # samples × plasmid contigs
├── annotation/
│   └── {sample_id}_genomad_annotation.tsv
└── logs/
    ├── aligner_selection.log    # sample_id | avg_len | aligner_used
    └── {sample_id}_flagstat.txt
```

---

## Singularity Containers (conf/singularity.config)

| Process | Container |
|---|---|
| FILTER_CONTIGS | seqkit.sif |
| GENOMAD | genomad.sif |
| QC_TRIM | fastp.sif |
| REMOVE_HOST_READS | bmtagger.sif |
| DETECT_READ_LENGTH | seqkit.sif |
| STROBEALIGN | strobealign.sif |
| BWAMEM2 | bwamem2.sif |
| BOWTIE2 | bowtie2.sif |
| SAMTOOLS_SORT / SAMTOOLS_FLAGSTAT | samtools.sif |
| COVERM_PHAGE / COVERM_PLASMID | coverm.sif |

---

## Resource Labels (conf/base.config)

```groovy
process {
    withLabel: 'low'    { cpus = 4;  memory = '8.GB';  time = '2.h'  }
    withLabel: 'medium' { cpus = 16; memory = '32.GB'; time = '12.h' }
    withLabel: 'high'   { cpus = 32; memory = '64.GB'; time = '24.h' }
}
```

| Process | Label | Note |
|---|---|---|
| FILTER_CONTIGS, DETECT_READ_LENGTH, MERGE_MGE, SAMTOOLS_SORT, SAMTOOLS_FLAGSTAT | low | |
| QC_TRIM, GENOMAD, BUILD_INDEX, STROBEALIGN, BWAMEM2, BOWTIE2 | medium | |
| REMOVE_HOST_READS | high | hg38 bitmask ~24 GB RAM |
| COVERM_PHAGE, COVERM_PLASMID | high | all BAMs collected |

---

## Key Conventions

1. One `process` block per `.nf` file
2. Channel prefix: `ch_` (e.g. `ch_raw_reads`, `ch_reads_for_mapping`, `ch_sorted_bams`)
3. Sample-level process input: `tuple val(sample_id), path(...)`
4. `publishDir`: `"${params.outdir}/<subdir>"`, `mode: 'copy'`
5. `errorStrategy = 'retry'`, `maxRetries = 2`
6. Each process emits a `.log` to `${params.outdir}/logs/`
7. `reads_mode` branching logic lives in `subworkflows/mge_abundance.nf`, not in `main.nf`

---

## MultiQC Integration (into de novo pipeline)

Do **not** add a separate MultiQC process in this subworkflow.
Emit the following channels for the de novo pipeline to consume:

```groovy
// from mge_abundance subworkflow
emit:
  flagstat  = SAMTOOLS_FLAGSTAT.out.txt   // ch_flagstat_mge
  aln_log   = ch_aligner_selection_log    // ch_aligner_log_mge
```

The de novo pipeline adds these to its existing MultiQC input:
```groovy
ch_multiqc_input = ch_fastp_reports
    .mix( ch_flagstat_mge )
    .mix( ch_aligner_log_mge )
    .collect()
```

geNomad summary and CoverM TSVs are published as standalone files only (not in MultiQC).

---

## Task Assignment

<!-- Fill in before each Claude Code session -->

### Current Task
> [ ] TODO: describe task

### Context
> [ ] TODO: which modules exist, what inputs are ready, any constraints

### Acceptance Criteria
> [ ] TODO: expected outputs, edge cases to handle, tests to pass

---

## Resolved Design Decisions

| Question | Decision |
|---|---|
| Assembly | Not in scope — contigs provided by de novo pipeline |
| Contig input | Per-sample `{sample_id}_contigs.fna`, via samplesheet `contigs` column |
| Contig length filter | FILTER_CONTIGS process in this subworkflow, `params.min_contig_length = 4000` |
| Reads input | Raw reads via samplesheet, same file as contigs (`sample_id` join) |
| Reads preprocessing | Configurable: `raw` / `host_removed` / `trimmed_host_removed` |
| Host removal | bmtagger + hg38, NFS mount, two index params (bitmask + srprism) |
| Read length detection | seqkit, subsample 200k reads |
| Assembly strategy | N/A (upstream) |
| geNomad DB hosting | Local NFS, read-only mount |
| CoverM identity threshold | Per-MGE-type: phage 0.85 / plasmid 0.90 |
| MultiQC | No separate run; emit flagstat + aligner log to de novo MultiQC |
| Provirus | Optional, `params.run_provirus = false` |
| Aligner | Auto-detect per sample; manual override via `params.aligner` |
