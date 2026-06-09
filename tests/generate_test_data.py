#!/usr/bin/env python3
"""
Generate synthetic test data for pipeline testing.

Creates:
  tests/data/fasta/test_contigs.fna   — 2 long contigs (≥4000 bp) + 1 short (2000 bp)
  tests/data/fastq/test_R1.fastq.gz   — 500 paired-end reads, 150 bp
  tests/data/fastq/test_R2.fastq.gz

Usage:
  python tests/generate_test_data.py
"""

import gzip
import random
import sys
from pathlib import Path

SEED = 42
N_READS = 500
READ_LEN = 150

DATA_DIR = Path(__file__).parent / "data"


def random_dna(length: int, rng: random.Random) -> str:
    return "".join(rng.choices("ACGT", k=length))


def random_qual(length: int, rng: random.Random, min_q: int = 20, max_q: int = 40) -> str:
    return "".join(chr(33 + rng.randint(min_q, max_q)) for _ in range(length))


def write_fasta(path: Path, contigs: list[tuple[str, int]], rng: random.Random, line_width: int = 60) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as fh:
        for name, length in contigs:
            seq = random_dna(length, rng)
            fh.write(f">{name} length={length}\n")
            for i in range(0, len(seq), line_width):
                fh.write(seq[i : i + line_width] + "\n")
    print(f"  Created {path}  ({sum(l for _, l in contigs):,} bp total across {len(contigs)} contigs)")


def write_fastq_gz(r1_path: Path, r2_path: Path, n_reads: int, read_len: int, rng: random.Random) -> None:
    r1_path.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(r1_path, "wt") as r1, gzip.open(r2_path, "wt") as r2:
        for i in range(n_reads):
            seq1 = random_dna(read_len, rng)
            seq2 = random_dna(read_len, rng)
            qual = random_qual(read_len, rng)
            r1.write(f"@read_{i}/1\n{seq1}\n+\n{qual}\n")
            r2.write(f"@read_{i}/2\n{seq2}\n+\n{qual}\n")
    print(f"  Created {r1_path.name} + {r2_path.name}  ({n_reads} reads × {read_len} bp)")


def main() -> None:
    rng = random.Random(SEED)

    print("Generating test FASTA …")
    write_fasta(
        DATA_DIR / "fasta" / "test_contigs.fna",
        [
            ("test_contig_1_virus",   5000),   # passes FILTER_CONTIGS (≥4000 bp)
            ("test_contig_2_plasmid", 6000),   # passes FILTER_CONTIGS (≥4000 bp)
            ("test_contig_3_short",   2000),   # filtered out by FILTER_CONTIGS
        ],
        rng,
    )

    print("Generating test FASTQ …")
    write_fastq_gz(
        DATA_DIR / "fastq" / "test_R1.fastq.gz",
        DATA_DIR / "fastq" / "test_R2.fastq.gz",
        n_reads=N_READS,
        read_len=READ_LEN,
        rng=rng,
    )

    # Write a samplesheet that points to the generated data
    ss_path = DATA_DIR / "samplesheets" / "valid.csv"
    fasta_abs = (DATA_DIR / "fasta" / "test_contigs.fna").resolve()
    r1_abs    = (DATA_DIR / "fastq" / "test_R1.fastq.gz").resolve()
    r2_abs    = (DATA_DIR / "fastq" / "test_R2.fastq.gz").resolve()
    ss_path.write_text(
        "sample_id,fastq_1,fastq_2,contigs\n"
        f"test_sample,{r1_abs},{r2_abs},{fasta_abs}\n"
        f"sample_B,{r1_abs},{r2_abs},{fasta_abs}\n"
    )
    print(f"  Created {ss_path}")

    # Stub files for tests that need inputs with distinct filenames
    stub_fasta = DATA_DIR / "fasta" / "test_contigs_plasmid.fna"
    stub_fasta.write_text(">stub_plasmid length=100\nACGT\n")
    bam_dir = DATA_DIR / "bam"
    bam_dir.mkdir(parents=True, exist_ok=True)
    (bam_dir / "fake_sorted.bam").write_bytes(b"")
    (bam_dir / "fake_sorted.bam.bai").write_bytes(b"")
    print(f"  Created stub files: {stub_fasta.name}, fake_sorted.bam, fake_sorted.bam.bai")

    print("\nDone. Run pytest and nf-test as normal.")


if __name__ == "__main__":
    main()
