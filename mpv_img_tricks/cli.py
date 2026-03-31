"""Unified CLI for mpv-img-tricks.

Argument parsing lives here; execution delegates to Bash backends under ``scripts/``.
"""

from __future__ import annotations

import argparse
import shlex
import shutil
import subprocess
import sys
from argparse import Namespace
from pathlib import Path

from mpv_img_tricks.config import live_subparser_defaults, load_config
from mpv_img_tricks.paths import get_scripts_dir

LIVE_EFFECTS = {"basic", "chaos", "tile"}
RENDER_EFFECTS = {
    "glitch",
    "acid",
    "reality",
    "kaleido",
    "matrix",
    "liquid",
    "ken-burns",
    "crossfade",
}
ALL_EFFECTS = sorted(LIVE_EFFECTS | RENDER_EFFECTS)

# ``main`` prepends DEFAULT_SUBCOMMAND when the first argv token is not a known subcommand
# (e.g. ``slideshow ~/pics`` → ``slideshow live ~/pics``). Register every subparser name in
# SUBCOMMAND_NAMES so flags, paths, and globs still route to the default slideshow flow.
DEFAULT_SUBCOMMAND = "live"
SUBCOMMAND_NAMES: frozenset[str] = frozenset({DEFAULT_SUBCOMMAND})


def run_command(cmd: list[str]) -> int:
    return subprocess.run(cmd, check=False).returncode


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


def add_render_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--render", action="store_true", help="Render to a video instead of live playback")
    parser.add_argument("--output", help="Output file path for render mode")
    parser.add_argument("--resolution", default="1920x1080", help="Output resolution")
    parser.add_argument("--fps", default="30", help="Frames per second for effect renders")
    parser.add_argument(
        "--img-per-sec",
        default="60",
        help="Images per second for plain render mode",
    )


def add_effect_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--effect", choices=ALL_EFFECTS, help="Effect modifier")
    parser.add_argument("--limit", "-l", default="5", help="Max images for video effects")
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
    parser.add_argument(
        "--order",
        choices=["natural", "om"],
        help="File ordering mode",
    )
    parser.add_argument("--recursive", action="store_true", help="Recurse into subdirectories when discovering images")
    parser.add_argument(
        "--no-subdirs",
        dest="effect_no_recursive",
        action="store_true",
        help="For tile/chaos/render effects, only scan the top-level directory (default: recurse into subfolders)",
    )
    parser.add_argument(
        "--random-scale",
        action="store_true",
        help="Randomly alternate between fit and fill",
    )


def add_diagnostic_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--debug", action="store_true", help="Print backend debug info (shell trace in img-effects)")
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress progress/chatter on stderr from backends (errors still print)",
    )
    parser.add_argument(
        "--verbose-ffmpeg",
        action="store_true",
        help="Louder ffmpeg logging for compositing and video effects",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the backend argv and exit without running mpv/ffmpeg",
    )
    parser.add_argument(
        "--clear-cache",
        action="store_true",
        help="Remove mpv-img-tricks caches under ~/.cache/mpv-img-tricks/ (ffprobe validate + tile composites), then run",
    )


def append_if_value(cmd: list[str], flag: str, value: object | None) -> None:
    if value is None:
        return
    cmd.extend([flag, str(value)])


def append_if_true(cmd: list[str], flag: str, enabled: bool) -> None:
    if enabled:
        cmd.append(flag)


def append_diagnostic(cmd: list[str], args: Namespace) -> None:
    append_if_true(cmd, "--debug", args.debug)
    append_if_true(cmd, "--quiet", args.quiet)
    append_if_true(cmd, "--verbose-ffmpeg", args.verbose_ffmpeg)


def validate_live_args(args: Namespace, parser: argparse.ArgumentParser) -> None:
    if args.master_control and args.no_master_control:
        parser.error("choose either --master-control or --no-master-control")

    if not args.render and args.effect in RENDER_EFFECTS:
        parser.error(f"--effect {args.effect} requires --render")

    if args.render and args.effect in LIVE_EFFECTS:
        parser.error(f"--effect {args.effect} is live-only and cannot be combined with --render")

    if args.watch and args.render:
        parser.error("--watch cannot be combined with --render")

    if args.shuffle and args.render:
        parser.error("--shuffle cannot be combined with --render")

    if args.no_recursive and args.render:
        parser.error("--no-recursive cannot be combined with --render")

    if args.recursive and getattr(args, "effect_no_recursive", False):
        parser.error("choose either --recursive or --no-subdirs for effect discovery, not both")


_TOOL_CACHE_SUBDIRS = (
    "ffprobe-tile-v1",
    "ffprobe-tile-v2",
    "ffprobe-tile-v3",
    "ffprobe-tile-v4",
    "ffprobe-tile-v5",
    "tile-randomized",
)


def clear_mpv_img_tricks_tool_caches(*, quiet: bool) -> None:
    """Remove img-effects cache dirs under ~/.cache/mpv-img-tricks (same set as img-effects.sh)."""
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
            "mpv-img-tricks: phase=cache msg=cleared ffprobe-tile-v1 ffprobe-tile-v2 ffprobe-tile-v3 ffprobe-tile-v4 ffprobe-tile-v5 tile-randomized",
            file=sys.stderr,
        )
    elif not failures:
        print(f"mpv-img-tricks: phase=cache msg=cleared noop dir={base}", file=sys.stderr)


def _clear_cache_handled_by_img_effects(args: Namespace) -> bool:
    effect = args.effect or "basic"
    if args.render:
        return bool(args.effect)
    return effect in ("tile", "chaos")


def build_live_backend_command(args: Namespace) -> list[str]:
    scripts = get_scripts_dir()
    effect = args.effect or "basic"
    if effect == "basic":
        cmd = [str(scripts / "slideshow.sh"), args.images_dir]
        cmd.extend(
            ["--duration", str(args.duration), "--scale-mode", args.scale_mode, "--instances", str(args.instances)]
        )
        append_if_value(cmd, "--display", args.display)
        append_if_value(cmd, "--display-map", args.display_map)
        append_if_true(cmd, "--master-control", args.master_control)
        append_if_true(cmd, "--no-master-control", args.no_master_control)
        append_if_true(cmd, "--shuffle", args.shuffle)
        append_if_true(cmd, "--watch", args.watch)
        append_if_true(cmd, "--no-recursive", args.no_recursive)
        append_if_true(cmd, "--no-recursive-images", args.no_recursive_images)
        append_diagnostic(cmd, args)
        return cmd

    cmd = [str(scripts / "img-effects.sh"), effect, args.images_dir]
    cmd.extend(["--duration", str(args.duration)])
    if args.scale_mode != "stretch":
        cmd.extend(["--scale-mode", args.scale_mode])
    cmd.extend(["--instances", str(args.instances)])
    append_if_value(cmd, "--display", args.display)
    append_if_value(cmd, "--display-map", args.display_map)
    append_if_true(cmd, "--master-control", args.master_control)
    append_if_true(cmd, "--no-master-control", args.no_master_control)
    append_diagnostic(cmd, args)

    if effect == "tile":
        append_if_value(cmd, "--grid", args.grid)
        append_if_value(cmd, "--spacing", args.spacing)
        append_if_value(cmd, "--group-size", args.group_size)
        append_if_true(cmd, "--randomize", args.randomize)
        append_if_true(cmd, "--animate-videos", args.animate_videos)
        append_if_value(cmd, "--encoder", args.encoder)
        append_if_value(cmd, "--sound", args.sound)
        append_if_value(cmd, "--sound-trim-db", args.sound_trim_db)
        append_if_value(cmd, "--max-files", args.max_files)
        append_if_value(cmd, "--order", args.order)
        if getattr(args, "effect_no_recursive", False):
            append_if_true(cmd, "--no-recursive", True)
        else:
            append_if_true(cmd, "--recursive", args.recursive)
        append_if_true(cmd, "--random-scale", args.random_scale)

    if effect == "chaos":
        if getattr(args, "effect_no_recursive", False):
            append_if_true(cmd, "--no-recursive", True)
        else:
            append_if_true(cmd, "--recursive", args.recursive)

    append_if_true(cmd, "--clear-cache", getattr(args, "clear_cache", False))
    return cmd


def build_plain_render_command(args: Namespace) -> list[str]:
    scripts = get_scripts_dir()
    cmd = [
        str(scripts / "images-to-video.sh"),
        args.images_dir,
        str(args.img_per_sec),
        args.resolution,
        args.output or "flipbook.mp4",
    ]
    append_diagnostic(cmd, args)
    return cmd


def build_effect_render_command(args: Namespace) -> list[str]:
    scripts = get_scripts_dir()
    cmd = [str(scripts / "img-effects.sh"), args.effect, args.images_dir]
    cmd.extend(["--duration", str(args.duration), "--resolution", args.resolution, "--fps", str(args.fps)])
    append_if_value(cmd, "--output", args.output)
    append_if_value(cmd, "--scale-mode", args.scale_mode if args.scale_mode != "stretch" else "fit")
    append_if_value(cmd, "--limit", args.limit)
    append_if_value(cmd, "--sound", args.sound)
    append_if_value(cmd, "--sound-trim-db", args.sound_trim_db)
    append_if_value(cmd, "--max-files", args.max_files)
    append_if_value(cmd, "--order", args.order)
    if getattr(args, "effect_no_recursive", False):
        append_if_true(cmd, "--no-recursive", True)
    else:
        append_if_true(cmd, "--recursive", args.recursive)
    append_if_true(cmd, "--random-scale", args.random_scale)
    append_diagnostic(cmd, args)
    append_if_true(cmd, "--clear-cache", getattr(args, "clear_cache", False))
    return cmd


def handle_live(args: Namespace, parser: argparse.ArgumentParser) -> int:
    validate_live_args(args, parser)

    if getattr(args, "clear_cache", False) and not args.dry_run:
        if not _clear_cache_handled_by_img_effects(args):
            clear_mpv_img_tricks_tool_caches(quiet=args.quiet)

    if args.dry_run:
        if args.render:
            if args.effect:
                cmd = build_effect_render_command(args)
            else:
                cmd = build_plain_render_command(args)
        else:
            cmd = build_live_backend_command(args)
        print(shlex.join(cmd))
        return 0

    if args.render:
        if args.effect:
            return run_command(build_effect_render_command(args))
        return run_command(build_plain_render_command(args))

    return run_command(build_live_backend_command(args))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="slideshow",
        description="Unified CLI for live slideshows, effects, and renders.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    live_parser = subparsers.add_parser(
        "live",
        help="Run a slideshow from an image directory or glob",
        description=(
            "Run a live slideshow by default. Add --effect to modify the live session, "
            "or add --render to export a video."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    live_parser.add_argument("images_dir", help="Source image directory or glob")

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
            "  slideshow ~/pics --effect chaos --duration 0.02",
            "  slideshow ~/pics --fill",
            "  slideshow live ~/pics --effect tile --grid 2x2 --randomize",
            "  slideshow ~/pics --render --output out.mp4",
            "  slideshow ~/pics --render --effect glitch --output glitch.mp4",
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
