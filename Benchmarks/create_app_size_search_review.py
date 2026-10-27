#!/usr/bin/env python3
"""retain current production-adapter samples beside the approved quality-90 references."""

import argparse
import html
import json
import shutil
import subprocess
from pathlib import Path

from run_encoder_benchmark import digest, gif_metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--gifski", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--magick", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    fixtures = json.loads((args.run / "fixtures.json").read_text())
    reference_summary = json.loads((Path(__file__).resolve().parent /
        "reviews/size-search-quality-floor-2026-10-24/summary.json").read_text())
    sections, records = [], []
    commands = []
    def convert(command):
        commands.append(command)
        subprocess.run(command, check=True, capture_output=True)
    def frame_at(path, seconds, target):
        metadata = gif_metadata(path)
        boundary, index = 0, 0
        for index, delay in enumerate(metadata["frame_delays_centiseconds"]):
            boundary += delay
            if boundary > seconds * 100:
                break
        command = [str(args.magick), f"{path}[0-{index}]", "-coalesce"]
        if index:
            command += ["-delete", f"0-{index - 1}"]
        convert(command + [str(target)])
    for fixture in fixtures:
        if "10s" not in fixture["name"]:
            continue
        profile = fixture["name"].split("-10s")[0]
        expected_hash = reference_summary["profiles"][profile][0]["source_frame_set_sha256"]
        if fixture["fixture_sha256"] != expected_hash:
            raise ValueError("fixture does not match the approved reference")
        directory = args.run / ("review-" + fixture["name"])
        command = [str(args.run / "app-size-search"), str(args.gifski), fixture["source"], str(directory), "review"]
        report = json.loads(subprocess.check_output(command, text=True))
        figures = []
        reference = ("mostly-static-ui-gifski-1.34.0.gif" if profile == "mostly-static-ui"
                     else "high-motion-gifski-1.34.0.gif")
        figures.append(f'<figure><figcaption>approved quality-90 reference · direct CLI</figcaption><img src="../gifski-magick-35-2026-10-24/gifs/{reference}" alt="approved {profile} reference"></figure>')
        for index, attempt in enumerate(report["attempts"]):
            filename = f"{profile}-{attempt['scale']}pct-{attempt['fps']}fps.gif"
            target = args.output / filename
            shutil.copyfile(directory / f"attempt-{index}.gif", target)
            record = {"profile": profile, "source_frame_set_sha256": fixture["fixture_sha256"], "file": filename, "sha256": digest(target),
                      "settings": attempt, "metadata": gif_metadata(target)}
            records.append(record)
            if args.magick:
                work = directory / f"contact-{index}"
                work.mkdir()
                original = work / "original.png"
                actual = work / "actual.png"
                reference_png = work / "reference.png"
                reference_path = (Path(__file__).resolve().parent /
                    "reviews/size-search-quality-floor-2026-10-24/gifs" /
                    f"{profile}__{attempt['scale']:03d}pct__{attempt['fps']:02d}fps.gif")
                frame_at(Path(fixture["source"]), 5, original)
                frame_at(target, 5, actual)
                frame_at(reference_path, 5, reference_png)
                panels = []
                for title, path in [("synthetic source", Path(fixture["fixture"]) / "frame_0120.png"),
                                    ("ImageIO original", original),
                                    ("approved direct CLI", reference_png), ("current adapter", actual)]:
                    panel = work / (title.replace(" ", "-") + ".png")
                    convert([str(args.magick), str(path), "-resize", f"{attempt['width']}x{attempt['height']}!", str(panel)])
                    panels.append((title, panel))
                for zoom in (1, 2):
                    contact = args.output / f"{profile}-{attempt['scale']}pct-{attempt['fps']}fps-5s-{zoom}x.png"
                    command = [str(args.magick), "montage", "-background", "#222222", "-fill", "white",
                               "-font", "/System/Library/Fonts/Supplemental/Arial.ttf", "-pointsize", "14"]
                    for title, panel in panels:
                        command += ["-label", title, str(panel)]
                    command += ["-filter", "point", "-resize", f"{attempt['width'] * zoom}x{attempt['height'] * zoom}!",
                                "-geometry", f"{attempt['width'] * zoom}x{attempt['height'] * zoom}+8+24",
                                "-tile", "2x2", str(contact)]
                    convert(command)
                record["contact_time_seconds"] = 5
                record["contact_zoom_factors"] = [1, 2]
            caption = f"current adapter · {attempt['scale']}% / {attempt['fps']} fps / q90 · {attempt['bytes']:,} bytes"
            figures.append(f'<figure><figcaption>{html.escape(caption)}</figcaption><img src="{filename}" alt="{html.escape(caption)}"></figure>')
        sections.append(f'<section><h2>{html.escape(profile)}</h2>{"".join(figures)}</section>')
    (args.output / "summary.json").write_text(json.dumps(records, indent=2) + "\n")
    if args.magick:
        provenance = {"commands": commands,
                      "magick_version": subprocess.check_output([str(args.magick), "-version"], text=True)}
        (args.output / "contact-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>current app size-search review</title>
<style>body{font:16px system-ui;max-width:1400px;margin:auto;padding:24px;background:#181818;color:#eee}section{display:flex;gap:24px;flex-wrap:wrap}h2{width:100%}figure{margin:0 0 24px;max-width:100%;overflow:auto}figcaption{margin-bottom:8px}img{display:block;max-width:none;border:1px solid #555}button{font:inherit;margin:0 8px 16px 0;padding:8px}p{max-width:75ch}a{color:#ffad72}</style>
<h1>current app size-search review</h1><p>these synthetic animations use the current production Swift adapter at the four architect-approved scale/rate pairs and quality90. the first animation in each profile is the previously approved direct-CLI quality reference. compare text, cursor edges, gradients, and temporal artifacts at native size. these outputs do not imply new architect approval.</p>
<button id="pause">pause all</button><button id="zoom">show at 2×</button>
''' + "".join(sections) + '''<script>
const pictures=[...document.querySelectorAll('img')];let paused=false;let zoom=false;
for(const p of pictures){p.dataset.src=p.src;p.onload=()=>{if(!p.dataset.width){p.dataset.width=p.naturalWidth;p.width=p.naturalWidth;}};}
function setPause(value){paused=value;for(const p of pictures){if(paused){const c=document.createElement('canvas');c.width=p.naturalWidth;c.height=p.naturalHeight;c.getContext('2d').drawImage(p,0,0);p.src=c.toDataURL();}else{p.src=p.dataset.src;}}document.querySelector('#pause').textContent=paused?'resume all':'pause all';}
document.querySelector('#pause').onclick=()=>setPause(!paused);
document.querySelector('#zoom').onclick=()=>{zoom=!zoom;for(const p of pictures){p.width=Number(p.dataset.width||p.naturalWidth)*(zoom?2:1);}document.querySelector('#zoom').textContent=zoom?'show at native size':'show at 2×';};
if(matchMedia('(prefers-reduced-motion: reduce)').matches){window.addEventListener('load',()=>setPause(true));}
</script></html>'''
    (args.output / "index.html").write_text(page)
    print(args.output)


if __name__ == "__main__":
    main()
