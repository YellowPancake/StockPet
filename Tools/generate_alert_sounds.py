#!/usr/bin/env python3
"""Build the selected CC0 bull and bear alert sounds.

The source previews are kept in ``sound-previews`` so the exact selected
recordings and edits remain reproducible.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "StockPet" / "Resources" / "Sounds"
PREVIEW_DIR = ROOT / "sound-previews"


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def convert(
    ffmpeg: str,
    source: Path,
    target: Path,
    start: str,
    end: str,
    fade_start: str,
    fade_duration: str,
) -> None:
    duration = str(float(end) - float(start))
    run(
        [
            ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(source),
            "-af",
            (
                f"atrim=start={start}:end={end},"
                "asetpts=PTS-STARTPTS,"
                "afade=t=in:st=0:d=0.02,"
                f"afade=t=out:st={fade_start}:d={fade_duration},"
                "loudnorm=I=-20:TP=-3:LRA=5,"
                f"atrim=end={duration}"
            ),
            "-t",
            duration,
            "-ar",
            "44100",
            "-ac",
            "1",
            "-c:a",
            "pcm_s16le",
            str(target),
        ]
    )


def main() -> None:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise SystemExit("ffmpeg is required to generate alert sounds.")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    bull_source = PREVIEW_DIR / "cow-A-real-short.mp3"
    bear_source = PREVIEW_DIR / "bear-A-short-growl.mp3"
    for source in (bull_source, bear_source):
        if not source.exists():
            raise SystemExit(f"Missing selected source sound: {source}")

    convert(
        ffmpeg,
        bull_source,
        OUTPUT_DIR / "bull-moo.wav",
        start="0.40",
        end="1.73",
        fade_start="1.18",
        fade_duration="0.15",
    )
    convert(
        ffmpeg,
        bear_source,
        OUTPUT_DIR / "bear-growl.wav",
        start="0",
        end="0.73",
        fade_start="0.58",
        fade_duration="0.15",
    )

    print(f"Generated selected CC0 alert sounds in {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
