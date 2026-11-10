"""Build the "Modeling tab explained" video from the frames + narration.

    1. MATLAB:   makeExplainerFrames           -> build/frames/*.png, build/narration.tsv
    2. Python:   python build_video.py [out.mp4] [--ffmpeg PATH]

Voice-over: Windows built-in text-to-speech (tts.ps1, offline).
Video: ffmpeg (on PATH, or `pip install imageio-ffmpeg`, or --ffmpeg).
Each frame is shown for as long as its narration lasts; soft subtitles
(English) are embedded too.
"""
import argparse
import re
import shutil
import subprocess
import sys
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUILD = HERE / "build"
# silence around each clip: a picture's first clip / its last clip get the longer pause,
# clips inside one picture (an arrow appearing) only a short one
PAD_FIRST, PAD_INNER_BEFORE = 0.5, 0.1
PAD_LAST, PAD_INNER_AFTER = 1.1, 0.3

# written for the ear in narration.tsv -> compact form in the subtitles
SUBS = [(r"\bS O C\b", "SOC"), (r"\bO C V\b", "OCV"), (r"\bR D C\b", "R_dc"),
        (r"\bC C, C V\b", "CC-CV"), (r"\bA H\b", "AH"), (r"\bR C\b", "RC"),
        (r"\bm c p\b", "m·cp"), (r"\bh A\b", "h·A"), (r"\btau (\d)\b", r"τ\1"),
        (r"\bbatt ambient\b", "batt_ambient"), (r" degrees C\b", " °C")]
# for the voice only
SAY = [(r"\bR0\b", "R zero"), (r"\bR1\b", "R one"), (r"\bR2\b", "R two"), (r"\bV0\b", "V zero"),
       (r"\bSOC0\b", "S O C zero"), (r"\bmilliohms\b", "milli-ohms")]


def find_ffmpeg(arg):
    if arg:
        return arg
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        sys.exit("ffmpeg not found: install it, or `pip install imageio-ffmpeg`, or pass --ffmpeg")


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def srt_time(t):
    ms = int(round(t * 1000))
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"


def chunks(text, maxlen=95):
    """sentences, long ones split at commas, for the subtitle lines"""
    out = []
    for s in re.split(r"(?<=[.!?])\s+", text.strip()):
        while len(s) > maxlen:
            cut = s.rfind(", ", 0, maxlen)
            if cut < 30:
                cut = s.rfind(" ", 0, maxlen)
            out.append(s[:cut + 1].strip())
            s = s[cut + 1:].strip()
        if s:
            out.append(s)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out", nargs="?", default=str(HERE.parent.parent / "docs" / "Modeling_Tab_Explained.mp4"))
    ap.add_argument("--ffmpeg")
    ap.add_argument("--voice", default="Microsoft Zira Desktop")
    a = ap.parse_args()
    ff = find_ffmpeg(a.ffmpeg)

    rows = [ln.split("\t") for ln in (BUILD / "narration.tsv").read_text(encoding="utf-8").splitlines() if ln.strip()]
    audio = BUILD / "audio"
    for p in (audio,):
        shutil.rmtree(p, ignore_errors=True)
        p.mkdir(parents=True)

    rows = [(r[0], r[1], r[2].strip() == "1" if len(r) > 2 else True) for r in rows]
    for fid, text, _ in rows:
        say = text
        for pat, rep in SAY:
            say = re.sub(pat, rep, say)
        (audio / f"{fid}.txt").write_text(say, encoding="utf-8")
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(HERE / "tts.ps1"),
                    str(audio), "-Voice", a.voice], check=True)

    # one continuous voice track (exact sample counts) + one image list with
    # exact durations -> a single encode, so picture, voice and subtitles
    # cannot drift apart
    srt, t0, lst = [], 0.0, ["ffconcat version 1.0"]
    pcm, rate = bytearray(), None
    prev_last = True
    for fid, text, last in rows:
        pad_b = PAD_FIRST if prev_last else PAD_INNER_BEFORE
        pad_a = PAD_LAST if last else PAD_INNER_AFTER
        prev_last = last
        with wave.open(str(audio / f"{fid}.wav")) as w:
            if rate is None:
                rate, width, chans = w.getframerate(), w.getsampwidth(), w.getnchannels()
            data = w.readframes(w.getnframes())
        nb, na = int(round(pad_b * rate)), int(round(pad_a * rate))
        pcm += bytes(nb * width * chans) + data + bytes(na * width * chans)
        dur = len(data) / (rate * width * chans)
        total = (nb + na) / rate + dur
        lst += [f"file '{(BUILD / 'frames' / f'{fid}.png').as_posix()}'", f"duration {total:.6f}"]
        # subtitles: each line gets a share of the narration time by its length
        shown = text
        for pat, rep in SUBS:
            shown = re.sub(pat, rep, shown)
        parts = chunks(shown)
        tot_chars = sum(len(p) for p in parts)
        t = t0 + nb / rate
        for p in parts:
            d = dur * len(p) / tot_chars
            srt.append(f"{len(srt) + 1}\n{srt_time(t)} --> {srt_time(t + d)}\n{p}\n")
            t += d
        t0 += total
        print(f"  {fid}: {total:5.1f} s")
    lst.append(lst[-2])                     # the concat demuxer needs the last file twice

    with wave.open(str(BUILD / "voice.wav"), "wb") as w:
        w.setnchannels(chans); w.setsampwidth(width); w.setframerate(rate)
        w.writeframes(bytes(pcm))
    (BUILD / "images.txt").write_text("\n".join(lst), encoding="utf-8")
    (BUILD / "subtitles.srt").write_text("\n".join(srt), encoding="utf-8")
    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    run([ff, "-y", "-f", "concat", "-safe", "0", "-i", str(BUILD / "images.txt"),
         "-i", str(BUILD / "voice.wav"), "-i", str(BUILD / "subtitles.srt"),
         "-map", "0:v", "-map", "1:a", "-map", "2",
         "-vf", "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:white,fps=10,format=yuv420p",
         "-c:v", "libx264", "-preset", "medium", "-tune", "stillimage", "-crf", "24",
         "-c:a", "aac", "-b:a", "96k", "-ar", "44100", "-ac", "1",
         "-c:s", "mov_text", "-metadata:s:s:0", "language=eng", "-t", f"{t0:.3f}",
         "-movflags", "+faststart", str(out)])
    shutil.copyfile(BUILD / "subtitles.srt", out.with_suffix(".srt"))
    print(f"\n{out}  ({t0 / 60:.1f} min, {out.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
