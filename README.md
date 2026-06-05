# Phage / Plasmid Detection & Abundance Pipeline

A **Nextflow + Singularity** subworkflow for detecting bacteriophage and plasmid sequences from metagenomic data and quantifying their abundance across samples.

> **Upstream dependency:** contigs are provided by an existing de novo pipeline (MEGAHIT, per-sample). This subworkflow takes contigs + raw reads as input — it does **not** perform QC or assembly.

---

## Pipeline Overview

```
Samplesheet (sample_id, fastq_1, fastq_2, contigs)
      │
      ├── IDENTIFICATION (per sample)
      │     FILTER_CONTIGS (≥4000 bp)
      │         └── GENOMAD → phage / plasmid / provirus sequences
      │               └── MERGE_MGE → BUILD_INDEX
      │
      └── ABUNDANCE (per sample → all samples)
            reads_mode:  raw | host_removed | trimmed_host_removed
                └── DETECT_READ_LENGTH → auto-select aligner
                      ├── ≥150 bp → STROBEALIGN
                      ├── ≥100 bp → BWAMEM2
                      └──  <100 bp → BOWTIE2
                            └── SAMTOOLS_SORT + SAMTOOLS_FLAGSTAT
                                  └── COVERM_PHAGE (id=0.85)
                                      COVERM_PLASMID (id=0.90)
```

---

## Requirements

| Tool | Version | Purpose |
|---|---|---|
| Nextflow | ≥ 23.04.0 | Workflow engine |
| Singularity / Apptainer | ≥ 3.8 / 1.0 | Container runtime |
| Java | ≥ 11 | Required by Nextflow |
| Python | ≥ 3.8 | Samplesheet validation only |

---

## Quick Start

```bash
# 1. Validate your samplesheet
python pipeline/bin/validate_samplesheet.py my_samples.csv

# 2. Run (raw reads, auto aligner)
nextflow run pipeline/main.nf \
    -profile singularity \
    --input      my_samples.csv \
    --genomad_db /nfs/databases/genomad_db/ \
    --outdir     ./results \
    --sif_dir    /containers/sif
```

See [docs/install.md](docs/install.md) for full installation, database setup, and Singularity image build instructions.

---

## Inputs

### Samplesheet

```csv
sample_id,fastq_1,fastq_2,contigs
sample_A,/data/A_R1.fastq.gz,/data/A_R2.fastq.gz,/data/A_contigs.fna
sample_B,s3://bucket/B_R1.fastq.gz,s3://bucket/B_R2.fastq.gz,s3://bucket/B_contigs.fna
```

- `sample_id`: unique identifier (alphanumeric, `-`, `_`)
- `fastq_1/2`: raw reads (local path or `s3://`)
- `contigs`: per-sample assembly from de novo pipeline (local or `s3://`)

### Key Parameters

| Parameter | Default | Description |
|---|---|---|
| `--input` | — | Path to samplesheet CSV |
| `--genomad_db` | — | Path to geNomad DB directory (NFS mount) |
| `--outdir` | `./results` | Output directory |
| `--sif_dir` | `/containers/sif` | Directory containing `.sif` files |
| `--reads_mode` | `raw` | `raw` / `host_removed` / `trimmed_host_removed` |
| `--host_genome_bitmask` | — | Absolute path to hg38 `.bitmask` FILE (bmtagger) |
| `--host_genome_srprism` | — | Absolute path to srprism index PREFIX, e.g. `/nfs/hg38_bmtagger/hg38.srprism` |
| `--singularity_bind_paths` | — | Comma-separated NFS paths to bind into containers, e.g. `/nfs,/scratch` |
| `--aligner` | `auto` | `auto` / `strobealign` / `bwamem2` / `bowtie2` |
| `--min_contig_length` | `4000` | Minimum contig length before geNomad |
| `--run_provirus` | `false` | Enable provirus detection |
| `--coverm_min_identity_phage` | `0.85` | CoverM identity threshold for phage |
| `--coverm_min_identity_plasmid` | `0.90` | CoverM identity threshold for plasmid |

---

## Outputs

```
results/
├── genomad/{sample_id}/
│   ├── {sample_id}_virus_summary.tsv
│   ├── {sample_id}_plasmid_summary.tsv
│   ├── {sample_id}_virus_sequences.fna
│   └── {sample_id}_plasmid_sequences.fna
├── annotation/
│   └── {sample_id}_genomad_annotation.tsv
├── abundance/
│   ├── phage_abundance.tsv       # samples × phage contigs (RPKM, TPM, covered_fraction)
│   └── plasmid_abundance.tsv
└── logs/
    ├── aligner_selection.log     # sample_id | avg_len | aligner_used
    └── {sample_id}_flagstat.txt
```

---

## Singularity Images

Definition files are in `pipeline/singularity/` with naming convention `toolName_version.def` → `toolName_version.sif`.

```bash
# Build all images
for def in pipeline/singularity/*.def; do
    sudo singularity build /containers/sif/$(basename $def .def).sif $def
done
```

| Image | Version |
|---|---|
| seqkit_2.8.1.sif | seqkit 2.8.1 |
| genomad_1.8.0.sif | geNomad 1.8.0 |
| fastp_0.23.4.sif | fastp 0.23.4 |
| bmtagger_3.306.sif | BMTagger 3.306 |
| strobealign_0.13.0.sif | strobealign 0.13.0 |
| bwamem2_2.2.1.sif | bwa-mem2 2.2.1 |
| bowtie2_2.5.3.sif | Bowtie2 2.5.3 |
| samtools_1.19.2.sif | SAMtools 1.19.2 |
| coverm_0.7.0.sif | CoverM 0.7.0 |

---

## Testing

### 1. Validate samplesheet (Python, no tools needed)

```bash
pytest tests/validate_samplesheet/
```

### 2. Stub tests — channel logic only (Nextflow, no Singularity)

```bash
python tests/generate_test_data.py          # generate synthetic FASTA + FASTQ

cd pipeline
nf-test test ../tests/modules/
nf-test test ../tests/subworkflows/
```

### 3. Full integration test (requires Singularity + built images)

```bash
nextflow run pipeline/main.nf \
    -profile singularity,test \
    --sif_dir /containers/sif \
    --genomad_db /nfs/databases/genomad_db/
```

---

## MultiQC Integration

This subworkflow does **not** run MultiQC. It emits two channels for the parent de novo pipeline:

```groovy
// in your de novo main.nf
ch_multiqc_input = ch_fastp_reports
    .mix( MGE_ABUNDANCE.out.flagstat )   // samtools flagstat per sample
    .mix( MGE_ABUNDANCE.out.aln_log  )   // aligner selection log per sample
    .collect()
```

---

## Repository Structure

```
pipeline/
├── main.nf
├── nextflow.config
├── nf-test.config
├── conf/
│   ├── base.config          # resource labels: low / medium / high
│   ├── test.config          # test profile (minimal resources)
│   ├── singularity.config   # container paths
│   └── awsbatch.config
├── modules/                 # 14 processes (one per file)
├── subworkflows/
│   ├── mge_identification.nf
│   └── mge_abundance.nf
├── singularity/             # .def files for all containers
├── assets/
│   └── samplesheet_template.csv
└── bin/
    └── validate_samplesheet.py

tests/
├── generate_test_data.py    # synthetic test data generator
├── conftest.py              # pytest auto-generate fixture
├── data/samplesheets/       # static CSVs for negative-case tests
├── modules/                 # nf-test stub tests per module
├── subworkflows/            # nf-test stub tests for subworkflows
└── validate_samplesheet/    # pytest tests (28 cases)

docs/
├── CLAUDE.md                # pipeline design spec
├── install.md               # full installation guide
└── phage_plasmid_pipeline.drawio
```

---

## Design Decisions

| Question | Decision |
|---|---|
| Assembly | Not in scope — contigs from upstream de novo pipeline |
| Contig filter | `params.min_contig_length = 4000` applied before geNomad |
| Reads preprocessing | Configurable: `raw` / `host_removed` / `trimmed_host_removed` |
| Aligner | Auto-detect per sample by avg read length; manual override available |
| CoverM thresholds | Per-MGE-type: phage 0.85 / plasmid 0.90 |
| MultiQC | No separate run; emit to parent pipeline |
| Provirus | Optional, off by default |
