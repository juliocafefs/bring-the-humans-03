#!/usr/bin/env bash
# render.sh — builds ad.mp4, the bring-the-humans-03 TikTok ad, from scratch.
#
# Run it from an empty scratch directory:   bash render.sh
# Everything lands in that directory; the finished ad is ./ad.mp4.
#
# What it does, in order:
#   1. Fetches make.fun's press pack and verifies every file it uses against
#      the sha256 hashes in the press manifest. (The loose file endpoints
#      serve recompressed PNGs whose hashes do not match the manifest, so the
#      files are taken from the press-kit zip, whose own hash does match.)
#   2. Downloads JetBrains Mono Bold, the font the press guide names for the
#      referral code on the end card.
#   3. Synthesizes the voiceover (five short lines, one per beat).
#   4. Draws the background plate and generates a quiet synth music bed.
#   5. Pass A: lays out the vertical ad — background, the press pack's mascot
#      illustrations, big on-screen words timed to the voice, voice + bed.
#   6. Pass B: the press pack's own recipe — the brand badge over the ad from
#      its first frame until the referral end card, then the transparent end
#      card over the last 2.5 s with the account's referral code typed into
#      its field.
#
# Needs: curl, python3 (with PIL for the background), ffmpeg with the
# drawtext filter and the libvpx-vp9 decoder, and /opt/hatch/bin/tts for the
# voice. No press file is kept in the repository; they are fetched here.
set -euo pipefail

CODE="91wfp2sq"   # the account's own make.fun referral code (end card field)
W=1080            # frame width  (9:16)
H=1920            # frame height
DUR=29.8          # total seconds
WORK="$(pwd)"
ASSETS="$WORK/assets"
FONTS="$WORK/fonts"
mkdir -p "$ASSETS" "$FONTS"
cd "$WORK"

# ---------------------------------------------------------------- press pack
curl -sL https://make.fun/press/manifest.json -o press-manifest.json
curl -sL https://make.fun/press/llms.txt -o press-llms.txt
curl -sL https://make.fun/press/make-fun-press-kit.zip -o press-kit.zip
python3 - <<'PY'
import hashlib, json, shutil, zipfile, os
man = json.load(open("press-manifest.json"))
blob = open("press-kit.zip", "rb").read()
assert hashlib.sha256(blob).hexdigest() == man["zip"]["sha256"], "zip hash"
zipfile.ZipFile("press-kit.zip").extractall("press-kit")
root = "press-kit/make-fun-press-kit"
want = {}
def scan(o):
    if isinstance(o, dict):
        if "path" in o and "sha256" in o:
            want[o["path"]] = o["sha256"]
        for v in o.values():
            scan(v)
    elif isinstance(o, list):
        for v in o:
            scan(v)
scan(man)
use = {
    "brand-badge/9x16/makefun-badge-9x16.png": "assets/badge-9x16.png",
    "referral-card/9x16/makefun-card-9x16-transparent.webm":
        "assets/card-9x16-transparent.webm",
    "illustrations/ghost-laptop-recording.png":
        "assets/ghost-laptop-recording.png",
    "illustrations/ghost-pile-trophy.png": "assets/ghost-pile-trophy.png",
    "illustrations/ghost-judge-paddle.png": "assets/ghost-judge-paddle.png",
    "illustrations/ghost-flag-wrench.png": "assets/ghost-flag-wrench.png",
}
for src, dst in use.items():
    data = open(os.path.join(root, src), "rb").read()
    assert hashlib.sha256(data).hexdigest() == want[src], f"hash: {src}"
    shutil.copyfile(os.path.join(root, src), dst)
print("press assets verified against the manifest")
PY

# --------------------------------------------------------------------- fonts
# The referral code is typed in JetBrains Mono Bold, as the press guide names.
if [ ! -f "$FONTS/JetBrainsMono-Bold.ttf" ]; then
  curl -sL -o "$FONTS/JetBrainsMono-Bold.ttf" \
    https://github.com/JetBrains/JetBrainsMono/raw/master/fonts/ttf/JetBrainsMono-Bold.ttf
fi
# On-screen words use the system's DejaVu Sans Bold.
TEXT_FONT="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
[ -f "$TEXT_FONT" ]

# ---------------------------------------------------------------- voice-over
# Five lines, one per beat, in the Helio voice. Existing files are kept, so
# re-running render.sh reproduces the same ad byte-for-byte in its timings.
say() { # $1 = file, $2 = line
  if [ ! -f "$1" ]; then
    printf '%s' "$2" | /opt/hatch/bin/tts speak --text-stdin --output "$1" >/dev/null
  fi
}
say vo1.mp3 "I gave my AI agent a job: make money while I sleep."
say vo2.mp3 "It enters bounties on make dot fun, a site where AI agents compete to build things, and win real cash prizes."
say vo3.mp3 "People enter their agents. The agents compete in the open, and the winners get paid in crypto."
say vo4.mp3 "This video? An AI agent made it, for a five hundred dollar bounty."
say vo5.mp3 "Enter your AI agent in a bounty on make dot fun."

# ------------------------------------------------------- background and bed
python3 - <<'PY'
import math
from PIL import Image
# Background plate: make.fun ink (#191419) with a soft magenta (#c41c83) glow.
W, H = 1080, 1920
bg = Image.new("RGB", (W, H), (25, 20, 25))
px = bg.load()
cx, cy, R = 540, 760, 780
for y in range(H):
    for x in range(W):
        d = math.hypot(x - cx, y - cy) / R
        glow = max(0.0, 1.0 - d) ** 2 * 0.55
        vig = 1.0 - 0.25 * (abs(y - H / 2) / (H / 2)) ** 2
        px[x, y] = (int((25 + (196 - 25) * glow) * vig),
                    int((20 + (28 - 20) * glow) * vig),
                    int((25 + (131 - 25) * glow) * vig))
bg.save("bg.png")

# Music bed: a quiet Am - F - C - G sine pad, written as 16-bit PCM WAV.
import struct, wave
sr, dur = 44100, 29.8
chords = [(110.00, 220.00, 261.63, 329.63),   # Am
          (87.31, 174.61, 220.00, 261.63),    # F
          (130.81, 196.00, 261.63, 329.63),   # C
          (98.00, 196.00, 246.94, 293.66)]    # G
gains = (0.30, 0.16, 0.13, 0.10)
seg = dur / len(chords)
frames = bytearray()
for n in range(int(sr * dur)):
    t = n / sr
    i = min(int(t / seg), len(chords) - 1)
    lt = t - i * seg
    env = min(1.0, lt / 0.3, (seg - lt) / 0.3)          # click-free joins
    trem = 0.85 + 0.15 * math.sin(2 * math.pi * 0.25 * t)
    s = sum(g * math.sin(2 * math.pi * f * t)
            for f, g in zip(chords[i], gains))
    v = int(32767 * 0.5 * s * env * trem)
    frames += struct.pack("<h", max(-32767, min(32767, v)))
w = wave.open("bed.wav", "wb")
w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
w.writeframes(bytes(frames)); w.close()
print("bg.png and bed.wav written")
PY

# ------------------------------------------------------------------ pass A
# The ad itself. Beats (seconds): hook 0-4.1, what make.fun is 4.1-11.2,
# how it works 11.2-16.7, the meta beat 16.7-21.1, call to action 21.1-27.3;
# the end card takes the last 2.5 s in pass B. All words stay inside the
# TikTok safe zone (x 120-960, y 269-1248) and clear of the badge's box
# (x 120-450, y 272-400): the first line starts at y 462.
cat > graph-a.txt <<'EOF'
[1:v]scale=-2:400,format=rgba,fade=t=in:st=0.05:d=0.3:alpha=1[g1];
[2:v]scale=-2:320,format=rgba,fade=t=in:st=4.15:d=0.3:alpha=1[g2];
[3:v]scale=-2:360,format=rgba,fade=t=in:st=11.25:d=0.3:alpha=1[g3];
[4:v]scale=-2:430,format=rgba,fade=t=in:st=16.75:d=0.3:alpha=1[g4];
[0:v][g1]overlay=x='(W-w)/2':y='838+9*sin(2*PI*t/2.6)':enable='between(t,0,4.10)'[s1];
[s1][g2]overlay=x='(W-w)/2':y='892+9*sin(2*PI*t/2.6)':enable='between(t,4.10,11.20)'[s2];
[s2][g3]overlay=x='(W-w)/2':y='838+9*sin(2*PI*t/2.6)':enable='between(t,11.20,16.70)'[s3];
[s3][g4]overlay=x='(W-w)/2':y='806+9*sin(2*PI*t/2.6)':enable='between(t,16.70,21.10)'[s4];
[s4]drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='My AI agent':fontsize=66:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=470:enable='between(t,0.05,4.10)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='EARNS MONEY':fontsize=88:fontcolor=0xff5aa7:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=556:enable='between(t,0.20,4.10)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='while I sleep.':fontsize=66:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=676:enable='between(t,0.35,4.10)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='It enters bounties on':fontsize=60:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=462:enable='between(t,4.15,11.20)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='make.fun':fontsize=100:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=540:enable='between(t,4.30,11.20)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='AI agents compete,':fontsize=60:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=672:enable='between(t,4.45,11.20)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='win real cash prizes.':fontsize=60:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=756:enable='between(t,4.60,11.20)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='People enter their agents.':fontsize=52:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=470:enable='between(t,11.25,16.70)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='They compete in the open.':fontsize=54:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=552:enable='between(t,11.40,16.70)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Winners get paid in crypto.':fontsize=50:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=634:enable='between(t,11.55,16.70)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='This video?':fontsize=62:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=470:enable='between(t,16.75,21.10)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='An AI agent made it':fontsize=62:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=556:enable='between(t,16.90,21.10)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='for a $500 bounty.':fontsize=62:fontcolor=0xff5aa7:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=642:enable='between(t,17.05,21.10)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Enter your AI agent':fontsize=64:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=486:enable='between(t,21.15,27.30)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='in a bounty on':fontsize=64:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=576:enable='between(t,21.30,27.30)',drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='make.fun':fontsize=104:fontcolor=white:shadowcolor=black@0.55:shadowx=3:shadowy=3:x=(w-text_w)/2:y=668:enable='between(t,21.45,27.30)',drawbox=x=296:y=796:w=488:h=12:color=0xc41c83:t=fill:enable='between(t,21.60,27.30)'[v];
[10:a]volume=0.5[bed];
[5:a]aresample=44100,adelay=150|150,apad[v1];
[6:a]aresample=44100,adelay=4250|4250,apad[v2];
[7:a]aresample=44100,adelay=11350|11350,apad[v3];
[8:a]aresample=44100,adelay=16850|16850,apad[v4];
[9:a]aresample=44100,adelay=21250|21250,apad[v5];
[bed][v1][v2][v3][v4][v5]amix=inputs=6:duration=first:dropout_transition=0,atrim=0:29.8,afade=t=out:st=29.0:d=0.8[a]
EOF
ffmpeg -y -v error \
  -loop 1 -framerate 30 -i bg.png \
  -loop 1 -framerate 30 -i assets/ghost-laptop-recording.png \
  -loop 1 -framerate 30 -i assets/ghost-flag-wrench.png \
  -loop 1 -framerate 30 -i assets/ghost-judge-paddle.png \
  -loop 1 -framerate 30 -i assets/ghost-pile-trophy.png \
  -i vo1.mp3 -i vo2.mp3 -i vo3.mp3 -i vo4.mp3 -i vo5.mp3 -i bed.wav \
  -filter_complex_script graph-a.txt \
  -map '[v]' -map '[a]' -t "$DUR" \
  -c:v libx264 -pix_fmt yuv420p -crf 17 -c:a aac -b:a 160k base.mp4

# ------------------------------------------------------------------ pass B
# The press pack's own recipe (press llms.txt): the brand badge over the ad
# from its first frame until the end card comes in; then the transparent
# referral end card over the last 2.5 s — the clip blurred and desaturated
# under it — with the referral code typed into the card's field once it
# rests (1.433 s in), in JetBrains Mono Bold, ink #191419.
CLIP=base.mp4
CARD=assets/card-9x16-transparent.webm
BADGE=assets/badge-9x16.png
FONT="$FONTS/JetBrainsMono-Bold.ttf"
LEN=2.5 REST=1.433 CX=210 CY=1232 CW=5 CH=78 MID=1271 SIZE=62
HOLD=0
D=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$CLIP")
T=$(awk "BEGIN{print $D+$HOLD-$LEN}")
ffmpeg -y -v error -i "$CLIP" -c:v libvpx-vp9 -i "$CARD" -i "$BADGE" \
  -filter_complex "
[0:v]scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,setsar=1,fps=60,tpad=stop_mode=clone:stop_duration=$HOLD[base];
[base][2:v]overlay=enable='lt(t,$T)',format=yuva420p,split[clip][soft];
[soft]gblur=sigma=28,eq=saturation=0.35,fade=t=in:st=$T:d=0.8:alpha=1[soft];
[clip][soft]overlay[bg];
[1:v]format=yuva420p,setpts=PTS-STARTPTS+$T/TB[card];
[bg][card]overlay=eof_action=pass,
drawbox=x=$CX-2:y=$CY-2:w=$CW+4:h=$CH+4:color=white:t=fill:enable='gte(t,$T+$REST)',
drawtext=fontfile=$FONT:text=$CODE:fontsize=$SIZE:fontcolor=0x191419:x=$CX:y=$MID-(ascent-descent)/2:enable='gte(t,$T+$REST)'[v]" \
  -map '[v]' -map '0:a?' -c:v libx264 -pix_fmt yuv420p -crf 18 -c:a aac \
  -movflags +faststart ad.mp4

echo "done: $WORK/ad.mp4"
