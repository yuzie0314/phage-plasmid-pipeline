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

> **Note:** `.def` files use two base strategies:
> - **Biocontainers (quay.io)** — bwamem2, genomad, bowtie2, samtools, bmtagger: pulls a
>   pre-built Docker layer; fast build.
> - **micromamba (bioconda)** — fastp, seqkit, coverm, strobealign: installs from
>   Bioconda inside `mambaorg/micromamba:1.5.8`; builds take a few minutes longer but
>   are immune to Biocontainers tag churn.
>
> All builds require internet access. The micromamba images are ~300–500 MB each
> (vs. ~100–200 MB for the quay.io ones); build time is 5–10 min per image on a
> `c6i.2xlarge`.

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

### 2.5 Pull pre-built images directly (partial alternative)

Four images (bwamem2, genomad, bowtie2, samtools) have stable, verified Biocontainers
tags and can be pulled directly. The other five use `.def` builds (either micromamba
or have no public image) and **must** be built via Section 2.1 / 2.2.

```bash
SIF_DIR=/containers/sif
mkdir -p $SIF_DIR

# These four can be pulled directly:
singularity pull $SIF_DIR/bwamem2_2.2.1.sif   docker://quay.io/biocontainers/bwa-mem2:2.2.1--he513fc3_0
singularity pull $SIF_DIR/genomad_1.8.0.sif   docker://antoniopcamargo/genomad:1.8.0
singularity pull $SIF_DIR/bowtie2_2.5.3.sif   docker://quay.io/biocontainers/bowtie2:2.5.3--py39h6fed5c7_0
singularity pull $SIF_DIR/samtools_1.19.2.sif docker://quay.io/biocontainers/samtools:1.19.2--h50ea8bc_1

# These five must be built from their .def files (see Section 2.1 / 2.2):
#   fastp_0.23.4.sif      — micromamba/bioconda build
#   seqkit_2.8.1.sif      — micromamba/bioconda build
#   coverm_0.7.0.sif      — micromamba/bioconda build
#   strobealign_0.13.0.sif — micromamba/bioconda build
#   bmtagger_3.306.sif    — no public Biocontainers image
```

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

### 2.7 Recommended EC2 instances for build and database setup (AWS)

If you are building Singularity images and/or preparing databases on AWS, use the
tables below to choose the right instance. The main constraints are:

| Task | CPU | RAM | Disk |
|---|---|---|---|
| Singularity build (9 images) | moderate | 16 GB | ~50 GB build cache + ~20 GB SIF output |
| geNomad DB download | low | low | **~15 GB** |
| hg38 reference download | low | low | **~3.2 GB** uncompressed FASTA |
| bmtagger bitmask (`bmtool`) | moderate | **~24 GB peak** | **~16 GB** output |
| bmtagger srprism (`srprism mkindex -M 7168`) | moderate | ~8 GB | **~8 GB** output (6 files) |

---

#### Building Singularity images

Singularity builds are CPU and disk I/O bound; memory requirements are modest.

| Instance | vCPU | RAM | ~Cost/hr | Rationale |
|---|---|---|---|---|
| `m6i.xlarge` | 4 | 16 GB | $0.19 | Budget option for sequential builds |
| `c6i.2xlarge` | 8 | 16 GB | $0.34 | **Recommended** — compute-optimised; cut build time roughly in half vs. `xlarge` when building all 9 images |

EBS: attach a **50 GB gp3** volume minimum (build squashfs cache + final SIF files).

---

#### Preparing databases

The bmtagger bitmask build (`bmtool`) is the memory bottleneck — it loads the entire
hg38 reference into RAM and peaks at ~24 GB. All other steps need ≤ 8 GB.

| Instance | vCPU | RAM | ~Cost/hr | Rationale |
|---|---|---|---|---|
| `r6i.xlarge` | 4 | 32 GB | $0.25 | Minimum for `bmtool`; 32 GB gives ~8 GB headroom over the peak |
| `r6i.2xlarge` | 8 | 64 GB | $0.50 | **Recommended** — comfortable margin; run geNomad download and bmtagger index in parallel |

EBS: attach a **100 GB gp3** volume to accommodate hg38 (~3.2 GB), bitmask (~16 GB),
srprism index (~8 GB), geNomad DB (~15 GB), and working space (~57.8 GB total used).

---

#### One-stop setup (Singularity build + databases on a single instance)

If you want to complete everything in one session, use a memory-optimised instance
with enough CPU to keep build times reasonable:

| Instance | vCPU | RAM | ~Cost/hr | Notes |
|---|---|---|---|---|
| `r6i.2xlarge` | 8 | 64 GB | $0.50 | Build all SIF images first, then prepare databases — total wall time ~3–4 h |
| `r6i.4xlarge` | 16 | 128 GB | $1.01 | Faster parallel builds; worth it if your time is the bottleneck |

EBS: attach a **150 GB gp3** volume (SIF files ~20 GB + all databases ~42 GB + temp space).

> **Tip — use FSx directly**: if you plan to run the pipeline with FSx for Lustre,
> mount the FSx filesystem on the build instance and write SIF files and databases
> directly to `/fsx`. This avoids a separate copy step and makes the files immediately
> available to pipeline workers.

> **Tip — Spot instances**: Singularity builds and database downloads are interruptible
> (re-runnable). Use Spot instances to reduce costs by up to 70 %. Enable
> `--hibernation` or use a persistent EBS volume so progress is not lost on interruption.

---

## 3. Prepare Databases

### Database size summary

| Database / file | Size | Required when |
|---|---|---|
| geNomad DB | ~15 GB | always |
| hg38.fa (reference genome) | ~3.2 GB | `reads_mode != 'raw'` |
| hg38.bitmask | ~16 GB | `reads_mode != 'raw'` |
| hg38.srprism.* (6 files) | ~8 GB | `reads_mode != 'raw'` |
| **Total (all databases)** | **~42 GB** | |

---

### geNomad database (~15 GB)

```bash
singularity exec $SIF_DIR/genomad_1.8.0.sif \
    genomad download-database /nfs/databases/genomad_db/
```

Pass to the pipeline: `--genomad_db /nfs/databases/genomad_db/`

### hg38 bmtagger index (only when `reads_mode != 'raw'`)

The pipeline needs two separate index types built from the same hg38 reference.
Both are accessed as NFS paths inside Singularity — they are **never copied** into
the Nextflow work directory.

| File | Size | Note |
|---|---|---|
| hg38.fa | ~3.2 GB | input reference |
| hg38.bitmask | ~16 GB | output of `bmtool` |
| hg38.srprism.* | ~8 GB | output of `srprism mkindex` (6 files) |

```bash
# Assumes hg38.fa is already available at /nfs/databases/hg38/hg38.fa
# Disk required: ~27 GB  RAM required: ~24 GB (bmtool bitmask step)

BMTAGGER_DIR=/nfs/databases/hg38_bmtagger
mkdir -p $BMTAGGER_DIR

# Step 1 — Build bitmask index (output: hg38.bitmask, ~16 GB)
singularity exec --bind /nfs $SIF_DIR/bmtagger_3.306.sif \
    bmtool \
        -d /nfs/databases/hg38/hg38.fa \
        -o $BMTAGGER_DIR/hg38.bitmask \
        -A 0 -w 18

# Step 2 — Build srprism index (output prefix: hg38.srprism, ~8 GB across 6 files)
#   Produces: hg38.srprism.amp, .idx, .map, .pmp, .rmp, .ssd
singularity exec --bind /nfs $SIF_DIR/bmtagger_3.306.sif \
    srprism mkindex \
        -i /nfs/databases/hg38/hg38.fa \
        -o $BMTAGGER_DIR/hg38.srprism \
        -M 7168
```

> The `-o $BMTAGGER_DIR/hg38.srprism` sets the **prefix** for all srprism files.
> bmtagger's `-x` flag reads this same prefix and auto-resolves the extensions.

Pass the exact file path and prefix to the pipeline:

```bash
# --host_genome_bitmask = path to the .bitmask FILE
# --host_genome_srprism = srprism index PREFIX (no extension)
--host_genome_bitmask /nfs/databases/hg38_bmtagger/hg38.bitmask \
--host_genome_srprism /nfs/databases/hg38_bmtagger/hg38.srprism
```

**NFS bind mount**: the pipeline uses `singularity.autoMounts = true` by default.
If your HPC's NFS mount point is not auto-detected, add:

```bash
--singularity_bind_paths '/nfs'
# or, for multiple paths:
--singularity_bind_paths '/nfs,/scratch'
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
    --host_genome_bitmask /nfs/databases/hg38_bmtagger/hg38.bitmask \
    --host_genome_srprism /nfs/databases/hg38_bmtagger/hg38.srprism \
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
| `manifest unknown` during build | Stale / wrong Biocontainers tag | Build from the updated `.def` file (Section 2.1); these now use micromamba/bioconda for fastp, seqkit, coverm, strobealign |
| `mount .../resolv.conf → /etc/resolv.conf error: destination doesn't exist` | Some minimal Docker base images omit `/etc/resolv.conf`; Singularity tries to bind-mount it during `%post` | Fixed in `bwamem2_2.2.1.def` via `%setup touch "${SINGULARITY_ROOTFS}/etc/resolv.conf"` |
| `requested access to the resource is denied` during pull | `docker.io/biocontainers` is a legacy registry requiring auth for new pulls | Use the `.def` build instead (Section 2.1); affected images: seqkit, fastp |
| `REMOVE_HOST_READS` OOM | bitmask index needs ~24 GB | Increase `high` label memory in `conf/base.config` |
| `GENOMAD` fails on empty filtered contigs | All contigs < `min_contig_length` | Lower `--min_contig_length` or check your assembly |
| `COVERM_*` hangs | Collecting too many large BAMs | Check disk space; consider per-sample CoverM if >200 samples |
| Wrong aligner selected | `auto` mis-detected read length | Set `--aligner` explicitly |
| `.sif` not found | `sif_dir` path wrong | Check path and use `--sif_dir` flag |
