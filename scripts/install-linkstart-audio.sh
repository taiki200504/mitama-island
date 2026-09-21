#!/bin/zsh
#
# Puts your own audio under the login sequence.
#
# The five cues the sequence plays (`ui-linkstart-rise`, `-warp`, `-flash`,
# `-tick`, `-resolve`) are looked up in your own sound folder before the
# bundled ones, so a file placed there wins without touching the app. This
# script slices one recording into those five files and drops them in.
#
# Nothing it produces is committed: the folder lives outside the repository,
# and the repository ships only its own synthesised cues.
#
# Usage:
#   zsh scripts/install-linkstart-audio.sh <audio-or-video-file> [offset]
#   zsh scripts/install-linkstart-audio.sh --restore     # back to the bundled cues
#
# `offset` (seconds, default 0) is where the sequence starts inside the file —
# use it when the recording has a lead-in.
#
# The slice points follow the structure of the sequence the app draws:
#   rise    offset + 0.00 … 1.40   the light arriving
#   warp    offset + 3.50 … 5.00   the dive into the tunnel
#   flash   offset + 5.00 … 5.80   the white-out at its end
#   tick    offset + 6.02 … 6.17   one sense confirming
#   resolve offset + 8.28 … 9.28   the five marks turning green
#   dive    offset + 16.60 … 18.40 leaving the interface
# Override any of them with e.g. RISE_RANGE="0.0 1.5" before the command.

set -euo pipefail

sounds_dir="$HOME/Library/Application Support/MitamaIsland/Sounds"
cues=(rise warp flash tick resolve dive)

if [[ "${1:-}" == "--restore" ]]; then
    for cue in $cues full; do
        rm -f "$sounds_dir/ui-linkstart-$cue."{caf,wav,aiff,aif,m4a,mp3}
    done
    echo "戻しました。バンドルされた音が鳴ります。"
    exit 0
fi

# --full <file> [offset] : install the recording as one take instead of five
# cues. The sequence then plays that file straight through, which is the only
# way to keep a piece of audio that was written as one take sounding like one.
if [[ "${1:-}" == "--full" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "使い方: zsh scripts/install-linkstart-audio.sh --full <ファイル> [開始位置(秒)]" >&2
        exit 1
    fi
    source_file="$2"
    offset="${3:-0}"
    [[ -f "$source_file" ]] || { echo "ファイルが見つかりません: $source_file" >&2; exit 1; }
    command -v ffmpeg >/dev/null || { echo "ffmpeg が要ります: brew install ffmpeg" >&2; exit 1; }
    mkdir -p "$sounds_dir"
    for cue in $cues; do
        rm -f "$sounds_dir/ui-linkstart-$cue."{caf,wav,aiff,aif,m4a,mp3}
    done
    target="$sounds_dir/ui-linkstart-full.caf"
    # A screen recording sits ~20 dB below where a cue needs to be, and its
    # quieter stretches then read as "the sound stopped". Bring the take up to
    # a broadcast-ish loudness while keeping its own dynamics.
    ffmpeg -nostdin -loglevel error -y -ss "$offset" -i "$source_file" \
        -af "afade=t=in:st=0:d=0.02,dynaudnorm=f=200:g=15:p=0.92:m=14,alimiter=limit=0.95" \
        -ac 2 -ar 48000 -c:a pcm_s16le -f caf "$target"
    echo "1本で入れました: $target"
    echo "⌃⌥L で最初から最後まで鳴ります。戻すときは --restore。"
    exit 0
fi

if [[ $# -lt 1 ]]; then
    echo "使い方: zsh scripts/install-linkstart-audio.sh <音声または動画ファイル> [開始位置(秒)]" >&2
    exit 1
fi

source_file="$1"
offset="${2:-0}"

if [[ ! -f "$source_file" ]]; then
    echo "ファイルが見つかりません: $source_file" >&2
    exit 1
fi

if ! command -v ffmpeg >/dev/null; then
    echo "ffmpeg が要ります: brew install ffmpeg" >&2
    exit 1
fi

# start length  (seconds, relative to `offset`)
typeset -A ranges
ranges[rise]="${RISE_RANGE:-0.00 1.40}"
ranges[warp]="${WARP_RANGE:-3.50 1.50}"
ranges[flash]="${FLASH_RANGE:-5.00 0.80}"
ranges[tick]="${TICK_RANGE:-6.02 0.15}"
ranges[resolve]="${RESOLVE_RANGE:-8.28 1.00}"
ranges[dive]="${DIVE_RANGE:-16.60 1.80}"

mkdir -p "$sounds_dir"

for cue in $cues; do
    set -- ${=ranges[$cue]}
    start="$1"
    length="$2"
    target="$sounds_dir/ui-linkstart-$cue.caf"
    # 48 kHz 16-bit, the format the bundled cues use; a short fade at each end
    # so a slice taken mid-waveform does not click.
    ffmpeg -nostdin -loglevel error -y \
        -ss "$(python3 -c "print($offset + $start)")" -t "$length" -i "$source_file" \
        -af "afade=t=in:st=0:d=0.01,afade=t=out:st=$(python3 -c "print(max(0, $length - 0.03))"):d=0.03" \
        -ac 2 -ar 48000 -c:a pcm_s16le -f caf "$target"
    printf "%-8s %s\n" "$cue" "$target"
done

echo
echo "入れました。⌃⌥L で鳴ります。元に戻すときは --restore。"
