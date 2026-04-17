"""Unified CLI for mpv-img-tricks.

Argument parsing lives here; ``live`` (basic/tile) uses Python pipelines (mpv/ffmpeg),
and plain ``--render`` uses Python + ffmpeg.
"""

from __future__ import annotations

import argparse
import shlex
import shutil
import sys
from argparse import Namespace
from pathlib import Path

from mpv_img_tricks.config import live_subparser_defaults, load_config
from mpv_img_tricks.pipelines import dispatch_live, dispatch_plain_render
from mpv_img_tricks.pipelines.live import format_live_dry_run

LIVE_EFFECTS = frozenset({"basic", "tile"})
LIVE_EFFECT_CHOICES = sorted(LIVE_EFFECTS)

# ``main`` prepends DEFAULT_SUBCOMMAND when the first argv token is not a known subcommand
# (e.g. ``slideshow ~/pics`` → ``slideshow live ~/pics``). Register every subparser name in
# SUBCOMMAND_NAMES so flags, paths, and globs still route to the default slideshow flow.
DEFAULT_SUBCOMMAND = "live"
SUBCOMMAND_NAMES: frozenset[str] = frozenset({DEFAULT_SUBCOMMAND})


def add_display_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--duration", "-d", default="2.0", help="Duration per image")
    scale = parser.add_mutually_exclusive_group()
    scale.add_argument(
        "--scale-mode",
        choices=["fit", "fill", "stretch"],
        help="Image scaling mode (default: fit, or from config)",
    )
    scale.add_argument(
        "--fit",
        dest="scale_mode",
        action="store_const",
        const="fit",
        help="Shorthand for --scale-mode fit",
    )
    scale.add_argument(
        "--fill",
        dest="scale_mode",
        action="store_const",
        const="fill",
        help="Shorthand for --scale-mode fill",
    )
    parser.add_argument("--instances", "-n", default="1", help="Number of mpv instances")
    parser.add_argument("--display", help="Display index for the single instance or master")
    parser.add_argument("--display-map", help="Per-instance display map CSV")
    parser.add_argument("--master-control", action="store_true", help="Force master control sync")
    parser.add_argument(
        "--no-master-control",
        action="store_true",
        help="Disable master control sync",
    )


def add_live_only_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--watch", action="store_true", help="Watch for new files")
    parser.add_argument(
        "--no-recursive",
        action="store_true",
        help="Disable recursive watch mode",
    )
    parser.add_argument("--shuffle", action="store_true", help="Shuffle playlist order")
    parser.add_argument(
        "--no-recursive-images",
        action="store_true",
        help="When collecting images for basic live, only scan the top directory (no subfolders)",
    )
    parser.add_argument(
        "--order",
        choices=["natural", "om", "nm"],
        default="natural",
        help="Deterministic playlist order (ignored when --shuffle is set): natural, om (oldest mtime), nm (newest mtime)",
    )


def add_render_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--render", action="store_true", help="Render to a video instead of live playback")
    parser.add_argument("--output", help="Output file path for render mode")
    parser.add_argument("--resolution", default="1920x1080", help="Output resolution")
    parser.add_argument(
        "--img-per-sec",
        default="60",
        help="Images per second for plain render mode",
    )


def add_effect_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--effect", choices=LIVE_EFFECT_CHOICES, help="Effect modifier (live only)")
    parser.add_argument("--grid", help="Tile grid size")
    parser.add_argument("--spacing", help="Tile spacing in pixels")
    parser.add_argument("--group-size", type=int, help="Randomized tile group size")
    parser.add_argument("--randomize", action="store_true", help="Randomize tile layouts")
    parser.add_argument(
        "--animate-videos",
        action="store_true",
        help="Animate tile videos instead of stills",
    )
    parser.add_argument(
        "--encoder",
        choices=["auto", "hevc_videotoolbox", "libx265", "libx264"],
        help="Animated tile encoder override",
    )
    parser.add_argument("--sound", help="Sound file for slideshow playback")
    parser.add_argument(
        "--sound-trim-db",
        help="Leading silence trim threshold in dB",
    )
    parser.add_argument("--max-files", type=int, help="Limit discovered files")
    parser.add_argument("--recursive", action="store_true", help="Recurse into subdirectories when discovering images")
    parser.add_argument(
        "--no-subdirs",
        dest="effect_no_recursive",
        action="store_true",
        help="For tile, only scan the top-level directory (default: recurse into subfolders)",
    )
    parser.add_argument(
        "--random-scale",
        action="store_true",
        help="Randomly alternate between fit and fill",
    )


def add_diagnostic_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--debug", action="store_true", help="Print backend debug info")
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress progress/chatter on stderr from backends (errors still print)",
    )
    parser.add_argument(
        "--verbose-ffmpeg",
        action="store_true",
        help="Louder ffmpeg logging for compositing and tile",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the backend argv or command and exit without running mpv/ffmpeg",
    )
    parser.add_argument(
        "--clear-cache",
        action="store_true",
        help="Remove mpv-img-tricks caches under ~/.cache/mpv-img-tricks/ (ffprobe validate + tile composites), then run",
    )


_TOOL_CACHE_SUBDIRS = (
    "ffprobe-tile-v1",
    "ffprobe-tile-v2",
    "ffprobe-tile-v3",
    "ffprobe-tile-v4",
    "ffprobe-tile-v5",
    "tile-randomized",
    "tile-fixed",
)


def clear_mpv_img_tricks_tool_caches(*, quiet: bool) -> None:
    """Remove mpv-img-tricks cache dirs under ~/.cache/mpv-img-tricks."""
    base = Path.home() / ".cache" / "mpv-img-tricks"
    removed = False
    failures: list[tuple[Path, OSError]] = []
    for name in _TOOL_CACHE_SUBDIRS:
        path = base / name
        if not path.exists():
            continue
        try:
            shutil.rmtree(path)
            removed = True
        except OSError as exc:
            failures.append((path, exc))
    if quiet:
        return
    for path, exc in failures:
        print(f"mpv-img-tricks: phase=cache msg=warn could_not_remove path={path} err={exc}", file=sys.stderr)
    if removed:
        print(
            "mpv-img-tricks: phase=cache msg=cleared ffprobe-tile-v1 ffprobe-tile-v2 ffprobe-tile-v3 ffprobe-tile-v4 ffprobe-tile-v5 tile-randomized tile-fixed",
            file=sys.stderr,
        )
    elif not failures:
        print(f"mpv-img-tricks: phase=cache msg=cleared noop dir={base}", file=sys.stderr)


def build_plain_render_dry_run_line(args: Namespace) -> str:
    """Human-readable line for dry-run (plain render is Python, not a script argv)."""
    out = args.output or "flipbook.mp4"
    return shlex.join(
        [
            "ffmpeg",
            "(plain-render)",
            *args.sources,
            "--img-per-sec",
            str(args.img_per_sec),
            "--resolution",
            args.resolution,
            "--output",
            out,
        ]
    )


def validate_live_args(args: Namespace, parser: argparse.ArgumentParser) -> None:
    if args.master_control and args.no_master_control:
        parser.error("choose either --master-control or --no-master-control")

    if args.render and args.effect:
        parser.error("--effect cannot be combined with --render (use plain --render only)")

    if args.watch and args.render:
        parser.error("--watch cannot be combined with --render")

    if args.shuffle and args.render:
        parser.error("--shuffle cannot be combined with --render")

    if args.no_recursive and args.render:
        parser.error("--no-recursive cannot be combined with --render")

    if args.recursive and getattr(args, "effect_no_recursive", False):
        parser.error("choose either --recursive or --no-subdirs for effect discovery, not both")

    if args.watch and len(args.sources) != 1:
        parser.error("--watch requires exactly one source path (a directory)")


def handle_live(args: Namespace, parser: argparse.ArgumentParser) -> int:
    validate_live_args(args, parser)

    if getattr(args, "clear_cache", False) and not args.dry_run:
        clear_mpv_img_tricks_tool_caches(quiet=args.quiet)

    if args.dry_run:
        if args.render:
            print(build_plain_render_dry_run_line(args))
            return 0
        line = format_live_dry_run(args)
        if line is None:
            print("Error: no images found for dry-run sources", file=sys.stderr)
            return 1
        print(line)
        return 0

    if args.render:
        return dispatch_plain_render(args)

    return dispatch_live(args)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="slideshow",
        description="Unified CLI for live slideshows (basic or tile) and plain image→video render.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    live_parser = subparsers.add_parser(
        "live",
        help="Run a slideshow from an image directory or glob",
        description=(
            "Run a live slideshow by default. Use --effect tile for tiling, "
            "or add --render to export a flipbook video (no --effect)."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    live_parser.add_argument(
        "sources",
        nargs="+",
        metavar="SOURCE",
        help="One or more image directories, files, or glob patterns",
    )

    playback = live_parser.add_argument_group("playback/display")
    add_display_args(playback)
    add_live_only_args(playback)

    render = live_parser.add_argument_group("render/video")
    add_render_args(render)

    effects = live_parser.add_argument_group("effect-specific")
    add_effect_args(effects)

    diagnostics = live_parser.add_argument_group("diagnostics")
    add_diagnostic_args(diagnostics)

    cfg = load_config()
    live_parser.set_defaults(**live_subparser_defaults(cfg))

    live_parser.epilog = "\n".join(
        [
            "Examples:",
            "  slideshow ~/pics",
            "  slideshow live ~/pics",
            "  slideshow ~/pics --fill",
            "  slideshow live ~/pics --effect tile --grid 2x2 --randomize",
            "  slideshow ~/pics --render --output out.mp4",
            "",
            f'If the first argument is not a subcommand name, "{DEFAULT_SUBCOMMAND}" '
            "is used as the default slideshow command.",
            "Optional defaults: ~/.config/mpv-img-tricks/config.json or MPV_IMG_TRICKS_CONFIG (JSON).",
        ]
    )
    live_parser.set_defaults(handler=handle_live, parser=live_parser)

    assert DEFAULT_SUBCOMMAND in SUBCOMMAND_NAMES, "default subcommand must be a registered name"
    return parser


def main() -> int:
    parser = build_parser()
    argv = sys.argv[1:]
    if argv and argv[0] not in SUBCOMMAND_NAMES:
        argv = [DEFAULT_SUBCOMMAND, *argv]
    args = parser.parse_args(argv)
    return args.handler(args, args.parser)


if __name__ == "__main__":
    sys.exit(main())
