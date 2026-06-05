# Installation Guide

## Requirements

| Dependency | Minimum version | Check |
|---|---|---|
| Nextflow | 23.04.0 | `nextflow -version` |
| Singularity / Apptainer | 3.8 / 1.0 | `singularity --version` |
| Java | 11 | `java -version` |
| Python | 3.8 | `python3 --version` (for samplesheet validation only) |

---

## 1. Install Nextflow

```bash
curl -s https://get.nextflow.io | bash
chmod +x nextflow
sudo mv nextflow /usr/local/bin/
nextflow -version
```

---

## 2. Build Singularity Images Locally

### Overview

All Singularity definition files are in `pipeline/singularity/`, named
`toolName_version.def`. Each builds to a matching `toolName_version.sif`.

```
pipeline/singularity/
├── seqkit_2.8.1.def        → seqkit_2.8.1.sif
├── genomad_1.8.0.def       → genomad_1.8.0.sif
├── fastp_0.23.4.def        → fastp_0.23.4.sif
├── bmtagger_3.306.def      → bmtagger_3.306.sif
├── strobealign_0.13.0.def  → strobealign_0.13.0.sif
├── bwamem2_2.2.1.def       → bwamem2_2.2.1.sif
├── bowtie2_2.5.3.def       → bowtie2_2.5.3.sif
├── samtools_1.19.2.def     → samtools_1.19.2.sif
└── coverm_0.7.0.def        → coverm_0.7.0.sif
```

> **Note:** Most `.def` files pull a pre-built Docker image from a public registry
> (Biocontainers / quay.io). Singularity converts the Docker layer cache to a
> read-only `.sif`. You only need internet access during the first build.

---

### Prerequisites for local build

**Root / fakeroot access is required** to build from a definition file.
Check which mode your system supports:

```bash
# Option A — you have sudo
sudo singularity build --help | grep -i 'fakeroot\|version'

# Option B — your system has fakeroot support (no sudo needed)
singularity build --fakeroot test.sif test.def

# Option C — HPC without fakeroot: use --remote (Sylabs Cloud, free tier)
singularity build --remote test.sif test.def
```

If neither sudo nor fakeroot is available, use `--remote` (see Section 2.4).

---

### 2.1 Build a single image

```bash
SIF_DIR=/containers/sif          # change to your preferred path
mkdir -p $SIF_DIR
DEF_DIR=pipeline/singularity

# With sudo:
sudo singularity build $SIF_DIR/seqkit_2.8.1.sif $DEF_DIR/seqkit_2.8.1.def

# With fakeroot (no sudo):
singularity build --fakeroot $SIF_DIR/seqkit_2.8.1.sif $DEF_DIR/seqkit_2.8.1.def
```

---

### 2.2 Build all images at once (recommended)

```bash
SIF_DIR=/containers/sif
mkdir -p $SIF_DIR
DEF_DIR=pipeline/singularity

for def in $DEF_DIR/*.def; do
    sif_name=$(basename "$def" .def).sif
    echo "==> Building $sif_name"
    sudo singularity build "$SIF_DIR/$sif_name" "$def"
done

echo "All images built in $SIF_DIR"
ls -lh $SIF_DIR
```

With fakeroot (no sudo):

```bash
for def in $DEF_DIR/*.def; do
    sif_name=$(basename "$def" .def).sif
    singularity build --fakeroot "$SIF_DIR/$sif_name" "$def"
done
```

---

### 2.3 Verify a built image

```bash
# Run the %test block defined in each .def
singularity test $SIF_DIR/seqkit_2.8.1.sif

# Or run a quick shell check
singularity exec $SIF_DIR/genomad_1.8.0.sif genomad --version
singularity exec $SIF_DIR/coverm_0.7.0.sif  coverm --version
```

---

### 2.4 Build via Sylabs Cloud (no local root required)

If your HPC provides neither sudo nor fakeroot:

```bash
# 1. Create a free account at https://cloud.sylabs.io
# 2. Generate an access token and authenticate:
singularity remote login

# 3. Build remotely (the cloud builds and streams the .sif back):
singularity build --remote $SIF_DIR/genomad_1.8.0.sif $DEF_DIR/genomad_1.8.0.def
```

> Remote builds do not support all `%post` steps (e.g. network calls during build).
> All `.def` files in this pipeline use `Bootstrap: docker` and are remote-build compatible.

---

### 2.5 Pull pre-built images directly (alternative)

If you prefer to skip the `.def` build step, pull directly from Biocontainers and rename:

```bash
SIF_DIR=/containers/sif
mkdir -p $SIF_DIR

singularity pull $SIF_DIR/seqkit_2.8.1.sif       docker://biocontainers/seqkit:v2.8.1_cv1
singularity pull $SIF_DIR/genomad_1.8.0.sif       docker://antoniopcamargo/genomad:1.8.0
singularity pull $SIF_DIR/fastp_0.23.4.sif        docker://biocontainers/fastp:v0.23.4_cv1
singularity pull $SIF_DIR/strobealign_0.13.0.sif  docker://quay.io/biocontainers/strobealign:0.13.0--h4ac6f70_0
singularity pull $SIF_DIR/bwamem2_2.2.1.sif       docker://quay.io/biocontainers/bwa-mem2:2.2.1--he513fc3_0
singularity pull $SIF_DIR/bowtie2_2.5.3.sif       docker://quay.io/biocontainers/bowtie2:2.5.3--py39h6fed5c7_0
singularity pull $SIF_DIR/samtools_1.19.2.sif     docker://quay.io/biocontainers/samtools:1.19.2--h50ea8bc_1
singularity pull $SIF_DIR/coverm_0.7.0.sif        docker://quay.io/biocontainers/coverm:0.7.0--h9ee0642_0
```

> `bmtagger_3.306.sif` has no public Biocontainers image — build it from
> `bmtagger_3.306.def` (Section 2.1 / 2.4).

---

### 2.6 Point the pipeline at your SIF directory

After building, set `sif_dir` in one of three ways (in order of precedence):

```bash
# A) Command-line flag (highest priority)
nextflow run pipeline/main.nf --sif_dir /containers/sif ...

# B) In nextflow.config
params {
    sif_dir = '/containers/sif'
}

# C) In conf/singularity.config (hard-coded for a fixed cluster)
params {
    sif_dir = '/nfs/shared/sif'
}
```

---

## 3. Prepare Databases

### geNomad database

```bash
singularity exec $SIF_DIR/genomad_1.8.0.sif \
    genomad download-database /nfs/databases/genomad_db/
```

Pass to the pipeline: `--genomad_db /nfs/databases/genomad_db/`

### hg38 bmtagger index (only when `reads_mode != 'raw'`)

```bash
# 1. Download hg38 (use your preferred source, e.g. UCSC or NCBI)
#    Assumes hg38.fa is already available at /nfs/databases/hg38/hg38.fa

# 2. Build bitmask index (~24 GB RAM required)
singularity exec $SIF_DIR/bmtagger_3.306.sif \
    bmtool -d /nfs/databases/hg38/hg38.fa \
           -o /nfs/databases/hg38_bmtagger/hg38.bitmask \
           -A 0 -w 18

# 3. Build srprism index
singularity exec $SIF_DIR/bmtagger_3.306.sif \
    srprism mkindex \
           -i /nfs/databases/hg38/hg38.fa \
           -o /nfs/databases/hg38_bmtagger/hg38.srprism \
           -M 7168
```

Pass to the pipeline:

```
--host_genome_bitmask /nfs/databases/hg38_bmtagger/
--host_genome_srprism /nfs/databases/hg38_bmtagger/
```

---

## 4. Prepare a Samplesheet

```bash
cp pipeline/assets/samplesheet_template.csv my_samples.csv
# edit my_samples.csv with your sample paths

python3 pipeline/bin/validate_samplesheet.py my_samples.csv
```

---

## 5. Run the Pipeline

Minimal run (raw reads, auto aligner):

```bash
nextflow run pipeline/main.nf \
    -profile singularity \
    --input      my_samples.csv \
    --genomad_db /nfs/databases/genomad_db/ \
    --outdir     ./results \
    --sif_dir    /containers/sif
```

With host removal and trimming:

```bash
nextflow run pipeline/main.nf \
    -profile singularity \
    --input               my_samples.csv \
    --genomad_db          /nfs/databases/genomad_db/ \
    --reads_mode          trimmed_host_removed \
    --host_genome_bitmask /nfs/databases/hg38_bmtagger/ \
    --host_genome_srprism /nfs/databases/hg38_bmtagger/ \
    --outdir              ./results \
    --sif_dir             /containers/sif
```

Force a specific aligner or enable provirus detection:

```bash
    --aligner     bwamem2      # auto | strobealign | bwamem2 | bowtie2
    --run_provirus true
```

Resume a failed run:

```bash
nextflow run pipeline/main.nf -resume [... same params ...]
```

---

## 6. Expected Outputs

```
results/
├── genomad/{sample_id}/          # geNomad summaries and sequences
├── annotation/                   # per-sample geNomad annotation TSV
├── abundance/
│   ├── phage_abundance.tsv       # samples × phage contigs (RPKM, TPM, covered_fraction)
│   └── plasmid_abundance.tsv
└── logs/
    ├── aligner_selection.log     # sample_id | avg_len | aligner_used
    └── {sample_id}_flagstat.txt
```

---

## 7. MultiQC Integration (into de novo pipeline)

This subworkflow does **not** run MultiQC itself. It emits two channels
for the parent de novo pipeline to consume:

| Channel | Content |
|---|---|
| `MGE_ABUNDANCE.out.flagstat` | per-sample `samtools flagstat` output |
| `MGE_ABUNDANCE.out.aln_log` | per-sample aligner selection log |

In the de novo `main.nf`:

```groovy
ch_multiqc_input = ch_fastp_reports
    .mix( MGE_ABUNDANCE.out.flagstat )
    .mix( MGE_ABUNDANCE.out.aln_log  )
    .collect()
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `singularity build` exits with permission error | No sudo / fakeroot | Use `--fakeroot` or `--remote` (Section 2.3 / 2.4) |
| `REMOVE_HOST_READS` OOM | bitmask index needs ~24 GB | Increase `high` label memory in `conf/base.config` |
| `GENOMAD` fails on empty filtered contigs | All contigs < `min_contig_length` | Lower `--min_contig_length` or check your assembly |
| `COVERM_*` hangs | Collecting too many large BAMs | Check disk space; consider per-sample CoverM if >200 samples |
| Wrong aligner selected | `auto` mis-detected read length | Set `--aligner` explicitly |
| `.sif` not found | `sif_dir` path wrong | Check path and use `--sif_dir` flag |
