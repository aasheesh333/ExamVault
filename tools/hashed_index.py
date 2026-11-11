#!/usr/bin/env python3
"""Builds a one-way (hashed) roll-number index.

## Why hashed and not plaintext

Publishing the official candidate list as plain text is a copyright grey area, and
re-hosting the PDF is clearly not ours to do. So the published object contains no
roll numbers at all — only a salted SHA-256 digest per roll, truncated to 8 bytes
and sorted.

The result answers exactly one question per query ("is this specific roll
present?") and cannot be used to enumerate candidates: recovering 10 000 preimages
means brute-forcing the entire roll space for every entry, and the salt prevents
precomputing that.

The digest and normalisation here MUST match `HashedRollIndex` in the Flutter app
byte for byte. `hashed_index_test.dart` pins the Dart side against fixed vectors;
`.github/workflows/parity.yml` runs `--emit-vectors` from THIS file and feeds them
to `app/tool/parity_check.dart`, so a drift on the Python side fails CI instead of
silently answering "not selected" for every student.
"""

from __future__ import annotations

import gzip
import hashlib
import json
import secrets
import sys

DIGEST_BYTES = 8
MODE = "sha256-8-salted"


def normalise(value: str) -> str:
    """Strips whitespace, nbsp, zero-width and dashes, then uppercases.

    Mirrors `HashedRollIndex.normalise` in Dart exactly.
    """
    cleaned = (
        value.replace("\u200b", "")
        .replace("\u00a0", "")
        .replace("\u2013", "")
        .replace("\u2014", "")
    )
    return "".join(ch for ch in cleaned if not ch.isspace()).upper()


def digest(roll: str, salt: str) -> str:
    """`sha256("<salt>:<NORMALISED_ROLL>")` truncated to 8 bytes, hex."""
    payload = f"{salt}:{normalise(roll)}".encode()
    return hashlib.sha256(payload).digest()[:DIGEST_BYTES].hex()


def exam_salt(exam_id: str) -> str:
    """Deterministic, exam-specific salt.

    Two properties matter:

    * **Per exam.** A table precomputed for one exam is useless against another,
      so an attacker pays the full cost for every exam they want to enumerate.
    * **Stable.** A random salt per build would change the object on every refresh,
      producing a new content hash — and therefore a new URL — every 30 minutes
      even when the candidate list had not changed. That churns R2, defeats the
      `immutable` cache, and makes it impossible to pin anything in a test.

    The salt is not a secret (it ships in the object). It exists to stop one
    precomputation from covering every exam, not to make the digest reversible.
    """
    return hashlib.sha256(f"examvault/v2/{exam_id}".encode()).hexdigest()[:32]


def build(rolls: list[str], salt: str | None = None) -> tuple[bytes, dict]:
    """Returns (gzip bytes, metadata)."""
    salt = salt or secrets.token_hex(16)

    hashes = sorted({digest(r, salt) for r in rolls if normalise(r)})

    # Duplicate roll numbers collapse to one digest; report the discrepancy so a
    # producer bug is visible rather than silent.
    doc = {
        "v": 2,
        "mode": MODE,
        "salt": salt,
        "total": len(hashes),
        "hashes": hashes,
    }

    raw = json.dumps(doc, separators=(",", ":")).encode()
    # mtime=0: gzip stamps the header with the current time by default, which
    # makes identical input produce different bytes — and therefore a different
    # content-addressed URL — on every run. Pinning it keeps the object name a
    # pure function of the candidate list.
    return gzip.compress(raw, compresslevel=9, mtime=0), doc


# The canonical parity vectors. These are NOT test fixtures that may drift:
# they are the contract between the Python producer and the Dart engine
# (`HashedRollIndex`), pinned identically in `app/test/hashed_index_test.dart`
# and re-checked live by `.github/workflows/parity.yml` via `--emit-vectors`.
PARITY_SALT = "00112233445566778899aabbccddeeff"
PARITY_ROLLS = ["125130000008", " 1251 3000 0023 ", "125130000032"]
PARITY_NORMALISE = {
    " 1251\u00a03000\u200b0023 ": "125130000023",
    "ab\u2013cd": "ABCD",
    "ab\u2014cd": "ABCD",
    "ab cd": "ABCD",
    "\t0100823\n": "0100823",
    # An ASCII hyphen is NOT stripped (only U+2013/U+2014 are) — pinned so a
    # well-meaning "cleanup" on either side fails the gate instead of every
    # lookup in production.
    "12-51": "12-51",
    "": "",
}


def emit_vectors() -> dict:
    """Machine-readable parity vectors for the Dart side (`app/tool/parity_check.dart`).

    Also asserts the Python side against its own pinned expectations first, so a
    regression in `normalise()`/`digest()` fails here with a clear message even
    before the cross-language comparison runs.
    """
    for value, expected in PARITY_NORMALISE.items():
        actual = normalise(value)
        if actual != expected:
            raise SystemExit(
                f"hashed_index.normalise regressed: {value!r} -> {actual!r}, "
                f"expected {expected!r}"
            )

    return {
        "mode": MODE,
        "digest_bytes": DIGEST_BYTES,
        "salt": PARITY_SALT,
        "digests": {roll: digest(roll, PARITY_SALT) for roll in PARITY_ROLLS},
        "normalise": {value: normalise(value) for value in PARITY_NORMALISE},
    }


if __name__ == "__main__":
    if "--emit-vectors" in sys.argv:
        print(json.dumps(emit_vectors(), indent=2))
        sys.exit(0)

    # Self-check: a fixed vector the Dart test also asserts.
    SALT = PARITY_SALT
    sample = PARITY_ROLLS
    print("salt   ", SALT)
    for s in sample:
        print(f"  {s!r:<24} -> {digest(s, SALT)}")
    body, meta = build(sample, SALT)
    print("gzip   ", len(body), "bytes for", meta["total"], "hashes")
