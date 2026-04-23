"""CLI parsing checks for explicit resolution override semantics."""

from __future__ import annotations

from mpv_img_tricks import cli


def test_resolution_defaults_when_not_provided() -> None:
    parser = cli.build_parser()
    args = parser.parse_args(["live", "fixtures/images"])
    resolution_explicit = args.resolution is not None
    if args.resolution is None:
        args.resolution = cli.DEFAULT_RESOLUTION
    assert resolution_explicit is False
    assert args.resolution == cli.DEFAULT_RESOLUTION


def test_resolution_marked_explicit_even_when_default_value_passed() -> None:
    parser = cli.build_parser()
    args = parser.parse_args(["live", "fixtures/images", "--resolution", "1920x1080"])
    resolution_explicit = args.resolution is not None
    if args.resolution is None:
        args.resolution = cli.DEFAULT_RESOLUTION
    assert resolution_explicit is True
    assert args.resolution == "1920x1080"
