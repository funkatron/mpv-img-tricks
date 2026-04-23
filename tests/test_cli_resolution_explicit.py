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


def test_tile_perf_flags_have_expected_defaults() -> None:
    parser = cli.build_parser()
    args = parser.parse_args(["live", "fixtures/images", "--effect", "tile"])
    assert args.tile_quality == "balanced"
    assert args.tile_safe_mode == "auto"
    assert args.auto_ram_cap is True
    assert args.tile_hwaccel == "off"


def test_tile_perf_flags_can_be_overridden() -> None:
    parser = cli.build_parser()
    args = parser.parse_args(
        [
            "live",
            "fixtures/images",
            "--effect",
            "tile",
            "--tile-quality",
            "fast",
            "--tile-safe-mode",
            "off",
            "--no-auto-ram-cap",
            "--tile-hwaccel",
            "auto",
        ]
    )
    assert args.tile_quality == "fast"
    assert args.tile_safe_mode == "off"
    assert args.auto_ram_cap is False
    assert args.tile_hwaccel == "auto"


def test_tile_motion_flags_have_expected_defaults() -> None:
    parser = cli.build_parser()
    args = parser.parse_args(["live", "fixtures/images", "--effect", "tile"])
    assert args.tile_motion == "off"
    assert args.tile_parallax == "off"
    assert args.tile_motion_strength == 1.0


def test_tile_motion_flags_can_be_overridden() -> None:
    parser = cli.build_parser()
    args = parser.parse_args(
        [
            "live",
            "fixtures/images",
            "--effect",
            "tile",
            "--tile-motion",
            "ken-burns",
            "--tile-parallax",
            "auto",
            "--tile-motion-strength",
            "0.75",
        ]
    )
    assert args.tile_motion == "ken-burns"
    assert args.tile_parallax == "auto"
    assert args.tile_motion_strength == 0.75
