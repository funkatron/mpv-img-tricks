#!/usr/bin/env python3
"""Experimental Python CLI spike for mpv-img-tricks.

This wrapper intentionally delegates execution to the existing shell scripts.
It is opt-in and non-default.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = REPO_ROOT / "scripts"


def run_command(cmd: list[str]) -> int:
  return subprocess.run(cmd, check=False).returncode


def add_common_live_args(parser: argparse.ArgumentParser) -> None:
  parser.add_argument("images_dir", help="Source image directory")
  parser.add_argument("--duration", "-d", default="0.001")
  parser.add_argument("--scale-mode", default="fit", choices=["fit", "fill", "stretch"])
  parser.add_argument("--instances", "-n", default="1")
  parser.add_argument("--display")
  parser.add_argument("--display-map")
  parser.add_argument("--master-control", action="store_true")
  parser.add_argument("--no-master-control", action="store_true")
  parser.add_argument("--shuffle", action="store_true")
  parser.add_argument("--watch", action="store_true")
  parser.add_argument("--no-recursive", action="store_true")
  parser.add_argument("--debug", action="store_true")


def handle_live(args: argparse.Namespace) -> int:
  cmd = [str(SCRIPTS_DIR / "slideshow.sh"), args.images_dir]
  cmd += ["--duration", str(args.duration), "--scale-mode", args.scale_mode, "--instances", str(args.instances)]
  if args.display:
    cmd += ["--display", args.display]
  if args.display_map:
    cmd += ["--display-map", args.display_map]
  if args.master_control:
    cmd.append("--master-control")
  if args.no_master_control:
    cmd.append("--no-master-control")
  if args.shuffle:
    cmd.append("--shuffle")
  if args.watch:
    cmd.append("--watch")
  if args.no_recursive:
    cmd.append("--no-recursive")
  if args.debug:
    cmd.append("--debug")
  return run_command(cmd)


def handle_tile(args: argparse.Namespace) -> int:
  cmd = [str(SCRIPTS_DIR / "img-effects.sh"), "tile", args.images_dir]
  cmd += ["--duration", str(args.duration), "--scale-mode", args.scale_mode]
  if args.grid:
    cmd += ["--grid", args.grid]
  if args.randomize:
    cmd.append("--randomize")
  if args.group_size:
    cmd += ["--group-size", str(args.group_size)]
  if args.spacing:
    cmd += ["--spacing", str(args.spacing)]
  if args.animate_videos:
    cmd.append("--animate-videos")
  if args.encoder:
    cmd += ["--encoder", args.encoder]
  if args.no_cache:
    cmd.append("--no-cache")
  if args.max_files:
    cmd += ["--max-files", str(args.max_files)]
  if args.debug:
    cmd.append("--debug")
  return run_command(cmd)


def handle_render(args: argparse.Namespace) -> int:
  cmd = [
      str(SCRIPTS_DIR / "images-to-video.sh"),
      args.images_dir,
      str(args.img_per_sec),
      args.resolution,
      args.output,
  ]
  if args.play:
    cmd.append("--play")
    cmd += ["--scale-mode", args.scale_mode, "--instances", str(args.instances)]
    if args.display:
      cmd += ["--display", args.display]
    if args.display_map:
      cmd += ["--display-map", args.display_map]
    if args.master_control:
      cmd.append("--master-control")
    if args.no_master_control:
      cmd.append("--no-master-control")
  if args.debug:
    cmd.append("--debug")
  return run_command(cmd)


def build_parser() -> argparse.ArgumentParser:
  parser = argparse.ArgumentParser(
      prog="slideshow-cli",
      description="Experimental Python wrapper for mpv-img-tricks shell entrypoints.",
  )
  subparsers = parser.add_subparsers(dest="command", required=True)

  live_parser = subparsers.add_parser("live", help="Run slideshow live mode")
  add_common_live_args(live_parser)
  live_parser.set_defaults(handler=handle_live)

  tile_parser = subparsers.add_parser("tile", help="Run tiled slideshow effect")
  tile_parser.add_argument("images_dir", help="Source image directory or glob")
  tile_parser.add_argument("--duration", "-d", default="0.05")
  tile_parser.add_argument("--scale-mode", default="fit", choices=["fit", "fill"])
  tile_parser.add_argument("--grid")
  tile_parser.add_argument("--randomize", action="store_true")
  tile_parser.add_argument("--group-size", type=int)
  tile_parser.add_argument("--spacing", type=int)
  tile_parser.add_argument("--animate-videos", action="store_true")
  tile_parser.add_argument("--encoder", choices=["auto", "hevc_videotoolbox", "libx265", "libx264"])
  tile_parser.add_argument("--no-cache", action="store_true")
  tile_parser.add_argument("--max-files", type=int)
  tile_parser.add_argument("--debug", action="store_true")
  tile_parser.set_defaults(handler=handle_tile)

  render_parser = subparsers.add_parser("render", help="Render images to video")
  render_parser.add_argument("images_dir", help="Source image directory")
  render_parser.add_argument("--img-per-sec", default="60")
  render_parser.add_argument("--resolution", default="1920x1080")
  render_parser.add_argument("--output", default="flipbook.mp4")
  render_parser.add_argument("--play", action="store_true")
  render_parser.add_argument("--scale-mode", default="fit", choices=["fit", "fill", "stretch"])
  render_parser.add_argument("--instances", "-n", default="1")
  render_parser.add_argument("--display")
  render_parser.add_argument("--display-map")
  render_parser.add_argument("--master-control", action="store_true")
  render_parser.add_argument("--no-master-control", action="store_true")
  render_parser.add_argument("--debug", action="store_true")
  render_parser.set_defaults(handler=handle_render)

  return parser


def main() -> int:
  parser = build_parser()
  args = parser.parse_args()
  return args.handler(args)


if __name__ == "__main__":
  sys.exit(main())
