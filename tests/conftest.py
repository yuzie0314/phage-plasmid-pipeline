"""
Pytest session fixture: auto-generates synthetic test data if not present.
Runs once per pytest session before any test.
"""

import subprocess
import sys
from pathlib import Path

import pytest

_DATA_DIR = Path(__file__).parent / "data"
_SENTINEL_FILES = [
    _DATA_DIR / "fasta"  / "test_contigs.fna",
    _DATA_DIR / "fastq"  / "test_R1.fastq.gz",
    _DATA_DIR / "fastq"  / "test_R2.fastq.gz",
    _DATA_DIR / "samplesheets" / "valid.csv",
]


@pytest.fixture(scope="session", autouse=True)
def generate_test_data() -> None:
    if any(not f.exists() for f in _SENTINEL_FILES):
        generator = Path(__file__).parent / "generate_test_data.py"
        subprocess.run([sys.executable, str(generator)], check=True)
