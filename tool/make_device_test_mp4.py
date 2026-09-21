"""Creates a small deterministic test MP4 for the Phase 2G-C device transfer
verification (test artifact only — never shipped).

Structure: ftyp box + a free/moov placeholder + an mdat box filled with a
repeating pattern. It is not a playable movie; the transfer verification only
needs REAL bytes served over REAL HTTP with a REAL Content-Length, so the
engine writes, counts and renames them. Integrity is proven by size + pattern
checksum, not by decodability.
"""
import os
import struct
import sys
import tempfile

TARGET_KIB = 2048  # 2 MiB mdat payload


def main() -> None:
    target = os.path.join(tempfile.gettempdir(), "specta_device_test.mp4")

    ftyp_payload = b"mp42isom"
    ftyp = struct.pack(">I", 8 + len(ftyp_payload)) + b"ftyp" + ftyp_payload

    filler = b"SPECTA2GC" * (TARGET_KIB * 1024 // 9 + 1)
    mdat_payload = filler[: TARGET_KIB * 1024]
    mdat = struct.pack(">I", 8 + len(mdat_payload)) + b"mdat" + mdat_payload

    with open(target, "wb") as handle:
        handle.write(ftyp + mdat)

    size = os.path.getsize(target)
    print(target)
    print(f"size={size}")
    print(f"expected_size={8 + len(ftyp_payload) + 8 + len(mdat_payload)}")
    sys.exit(0)


if __name__ == "__main__":
    main()
