#!/usr/bin/env python3
"""
Validate a samplesheet CSV before passing it to the pipeline.

Checks:
  1. Required columns present (sample_id, fastq_1, fastq_2, contigs)
  2. No empty values in required columns
  3. sample_id values are unique
  4. sample_id contains only alphanumeric characters, underscores, and hyphens
  5. File paths are either local (must exist) or S3 URIs (format check only)
  6. fastq_1 / fastq_2 end with .fastq.gz or .fq.gz
  7. contigs ends with .fna, .fa, or .fasta (optionally .gz)
"""

import argparse
import csv
import re
import sys
from pathlib import Path

REQUIRED_COLUMNS = ['sample_id', 'fastq_1', 'fastq_2', 'contigs']
FASTQ_SUFFIXES   = ('.fastq.gz', '.fq.gz', '.fastq', '.fq')
CONTIG_SUFFIXES  = ('.fna', '.fa', '.fasta', '.fna.gz', '.fa.gz', '.fasta.gz')
SAMPLE_ID_RE     = re.compile(r'^[A-Za-z0-9_\-]+$')
S3_RE            = re.compile(r'^s3://[A-Za-z0-9.\-_/]+$')


def err(msg: str) -> None:
    print(f'ERROR: {msg}', file=sys.stderr)


def validate(csv_path: str) -> int:
    errors = 0
    seen_ids: set[str] = set()

    with open(csv_path, newline='') as fh:
        reader = csv.DictReader(fh)

        # Check required columns
        missing = [c for c in REQUIRED_COLUMNS if c not in (reader.fieldnames or [])]
        if missing:
            err(f'Missing required columns: {missing}')
            return 1

        for lineno, row in enumerate(reader, start=2):  # 1-based, header = line 1

            sample_id = row['sample_id'].strip()

            # 1. No empty values
            for col in REQUIRED_COLUMNS:
                if not row[col].strip():
                    err(f'Line {lineno}: empty value in column "{col}"')
                    errors += 1

            # 2. sample_id uniqueness
            if sample_id in seen_ids:
                err(f'Line {lineno}: duplicate sample_id "{sample_id}"')
                errors += 1
            seen_ids.add(sample_id)

            # 3. sample_id characters
            if not SAMPLE_ID_RE.match(sample_id):
                err(f'Line {lineno}: sample_id "{sample_id}" contains invalid characters '
                    f'(allowed: A-Z a-z 0-9 _ -)')
                errors += 1

            # 4. Path checks
            for col in ('fastq_1', 'fastq_2', 'contigs'):
                path_str = row[col].strip()
                if not path_str:
                    continue  # already flagged above

                is_s3 = path_str.startswith('s3://')

                if is_s3:
                    if not S3_RE.match(path_str):
                        err(f'Line {lineno}: malformed S3 URI in "{col}": {path_str}')
                        errors += 1
                else:
                    if not Path(path_str).exists():
                        err(f'Line {lineno}: local file not found for "{col}": {path_str}')
                        errors += 1

                # 5. Extension checks
                lowered = path_str.lower()
                if col in ('fastq_1', 'fastq_2'):
                    if not any(lowered.endswith(s) for s in FASTQ_SUFFIXES):
                        err(f'Line {lineno}: "{col}" does not end with a recognised '
                            f'fastq suffix {FASTQ_SUFFIXES}: {path_str}')
                        errors += 1
                else:  # contigs
                    if not any(lowered.endswith(s) for s in CONTIG_SUFFIXES):
                        err(f'Line {lineno}: "contigs" does not end with a recognised '
                            f'fasta suffix {CONTIG_SUFFIXES}: {path_str}')
                        errors += 1

    if errors:
        print(f'\nValidation FAILED — {errors} error(s) found in {csv_path}',
              file=sys.stderr)
        return 1

    print(f'Validation OK — {len(seen_ids)} sample(s) in {csv_path}')
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('samplesheet', help='Path to samplesheet CSV')
    args = parser.parse_args()
    sys.exit(validate(args.samplesheet))


if __name__ == '__main__':
    main()
