"""
Tests for pipeline/bin/validate_samplesheet.py

Groups:
  - valid input passes cleanly
  - structural errors (missing column, empty value, duplicate id, invalid chars)
  - file-level errors (wrong extension)
  - S3 path handling
  - edge cases
"""

import sys
from pathlib import Path

import pytest

# Add pipeline/bin to path so we can import the validator directly
sys.path.insert(0, str(Path(__file__).parents[2] / "pipeline" / "bin"))
from validate_samplesheet import validate  # noqa: E402

DATA = Path(__file__).parents[1] / "data"


# ─── helpers ──────────────────────────────────────────────────────────────────

def _make_csv(tmp_path: Path, content: str) -> Path:
    p = tmp_path / "sheet.csv"
    p.write_text(content)
    return p


def _make_valid_csv(tmp_path: Path, *, n_samples: int = 1) -> Path:
    """Build a valid samplesheet pointing at real temp files."""
    r1 = tmp_path / "R1.fastq.gz"; r1.touch()
    r2 = tmp_path / "R2.fastq.gz"; r2.touch()
    fa = tmp_path / "contigs.fna";  fa.touch()
    rows = "\n".join(
        f"sample_{i},{r1},{r2},{fa}" for i in range(n_samples)
    )
    return _make_csv(tmp_path, f"sample_id,fastq_1,fastq_2,contigs\n{rows}\n")


# ─── valid inputs ─────────────────────────────────────────────────────────────

class TestValidInput:
    def test_single_sample_passes(self, tmp_path):
        csv = _make_valid_csv(tmp_path)
        assert validate(str(csv)) == 0

    def test_multiple_samples_pass(self, tmp_path):
        csv = _make_valid_csv(tmp_path, n_samples=3)
        assert validate(str(csv)) == 0

    def test_s3_paths_pass(self, tmp_path):
        csv = _make_csv(tmp_path, (
            "sample_id,fastq_1,fastq_2,contigs\n"
            "sample_A,"
            "s3://bucket/A_R1.fastq.gz,"
            "s3://bucket/A_R2.fastq.gz,"
            "s3://bucket/A_contigs.fna\n"
        ))
        assert validate(str(csv)) == 0

    def test_sample_id_with_hyphens_and_underscores(self, tmp_path):
        r1 = tmp_path / "R1.fastq.gz"; r1.touch()
        r2 = tmp_path / "R2.fastq.gz"; r2.touch()
        fa = tmp_path / "c.fna";       fa.touch()
        csv = _make_csv(tmp_path, (
            "sample_id,fastq_1,fastq_2,contigs\n"
            f"Sample-01_v2,{r1},{r2},{fa}\n"
        ))
        assert validate(str(csv)) == 0

    def test_mixed_local_and_s3(self, tmp_path):
        r1 = tmp_path / "R1.fastq.gz"; r1.touch()
        r2 = tmp_path / "R2.fastq.gz"; r2.touch()
        fa = tmp_path / "c.fna";       fa.touch()
        csv = _make_csv(tmp_path, (
            "sample_id,fastq_1,fastq_2,contigs\n"
            f"local_sample,{r1},{r2},{fa}\n"
            "s3_sample,"
            "s3://bucket/B_R1.fastq.gz,"
            "s3://bucket/B_R2.fastq.gz,"
            "s3://bucket/B_contigs.fna\n"
        ))
        assert validate(str(csv)) == 0


# ─── structural errors ────────────────────────────────────────────────────────

class TestStructuralErrors:
    def test_missing_fastq2_column_fails(self):
        csv = DATA / "samplesheets" / "missing_column.csv"
        assert validate(str(csv)) == 1

    def test_empty_fastq1_value_fails(self):
        csv = DATA / "samplesheets" / "empty_value.csv"
        assert validate(str(csv)) == 1

    def test_duplicate_sample_id_fails(self):
        csv = DATA / "samplesheets" / "duplicate_id.csv"
        assert validate(str(csv)) == 1

    def test_invalid_sample_id_chars_fails(self):
        csv = DATA / "samplesheets" / "invalid_chars.csv"
        assert validate(str(csv)) == 1

    def test_empty_sample_id_fails(self, tmp_path):
        csv = _make_csv(tmp_path, (
            "sample_id,fastq_1,fastq_2,contigs\n"
            ",/data/R1.fastq.gz,/data/R2.fastq.gz,/data/c.fna\n"
        ))
        assert validate(str(csv)) == 1

    def test_header_only_passes(self, tmp_path):
        """An empty samplesheet (header only) is technically valid — zero samples."""
        csv = _make_csv(tmp_path, "sample_id,fastq_1,fastq_2,contigs\n")
        assert validate(str(csv)) == 0

    def test_all_four_columns_must_be_present(self, tmp_path):
        for missing in ("sample_id", "fastq_1", "fastq_2", "contigs"):
            cols = [c for c in ("sample_id", "fastq_1", "fastq_2", "contigs") if c != missing]
            csv = _make_csv(tmp_path, ",".join(cols) + "\nval,val,val\n")
            assert validate(str(csv)) == 1, f"Missing '{missing}' should fail"


# ─── file-level errors ────────────────────────────────────────────────────────

class TestFileErrors:
    def test_wrong_fastq_extension_fails(self):
        csv = DATA / "samplesheets" / "wrong_extension.csv"
        assert validate(str(csv)) == 1

    def test_local_file_not_found_fails(self, tmp_path):
        csv = _make_csv(tmp_path, (
            "sample_id,fastq_1,fastq_2,contigs\n"
            "sample_A,"
            "/nonexistent/R1.fastq.gz,"
            "/nonexistent/R2.fastq.gz,"
            "/nonexistent/c.fna\n"
        ))
        assert validate(str(csv)) == 1

    def test_fq_gz_extension_accepted(self, tmp_path):
        r1 = tmp_path / "R1.fq.gz"; r1.touch()
        r2 = tmp_path / "R2.fq.gz"; r2.touch()
        fa = tmp_path / "c.fasta";  fa.touch()
        csv = _make_csv(tmp_path, (
            "sample_id,fastq_1,fastq_2,contigs\n"
            f"sample_A,{r1},{r2},{fa}\n"
        ))
        assert validate(str(csv)) == 0

    def test_fa_gz_contig_extension_accepted(self, tmp_path):
        r1 = tmp_path / "R1.fastq.gz"; r1.touch()
        r2 = tmp_path / "R2.fastq.gz"; r2.touch()
        fa = tmp_path / "c.fa.gz";     fa.touch()
        csv = _make_csv(tmp_path, (
            "sample_id,fastq_1,fastq_2,contigs\n"
            f"sample_A,{r1},{r2},{fa}\n"
        ))
        assert validate(str(csv)) == 0

    def test_malformed_s3_uri_fails(self, tmp_path):
        csv = _make_csv(tmp_path, (
            "sample_id,fastq_1,fastq_2,contigs\n"
            "sample_A,"
            "s3://bucket with spaces/R1.fastq.gz,"
            "s3://bucket/R2.fastq.gz,"
            "s3://bucket/c.fna\n"
        ))
        assert validate(str(csv)) == 1


# ─── error message content ────────────────────────────────────────────────────

class TestErrorMessages:
    def test_duplicate_id_error_mentions_sample(self, tmp_path, capsys):
        csv = DATA / "samplesheets" / "duplicate_id.csv"
        validate(str(csv))
        captured = capsys.readouterr()
        assert "duplicate" in captured.err.lower() or "sample_A" in captured.err

    def test_missing_column_error_mentions_column(self, capsys):
        csv = DATA / "samplesheets" / "missing_column.csv"
        validate(str(csv))
        captured = capsys.readouterr()
        assert "fastq_2" in captured.err

    def test_valid_input_prints_ok(self, tmp_path, capsys):
        csv = _make_valid_csv(tmp_path)
        validate(str(csv))
        captured = capsys.readouterr()
        assert "OK" in captured.out or "ok" in captured.out.lower()
