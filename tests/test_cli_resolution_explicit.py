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
    assert args.tile_quality == "high"
    assert args.tile_safe_mode == "auto"
    assert args.auto_ram_cap is True
    assert args.tile_hwaccel == "auto"


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
            "off",
        ]
    )
    assert args.tile_quality == "fast"
    assert args.tile_safe_mode == "off"
    assert args.auto_ram_cap is False
    assert args.tile_hwaccel == "off"


def test_tile_motion_flags_have_expected_defaults() -> None:
    parser = cli.build_parser()
    args = parser.parse_args(["live", "fixtures/images", "--effect", "tile"])
    assert args.tile_motion == "off"
    assert args.animate is None


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
        ]
    )
    assert args.tile_motion == "ken-burns"


def test_tile_motion_parallax_parse() -> None:
    parser = cli.build_parser()
    args = parser.parse_args(
        ["live", "fixtures/images", "--effect", "tile", "--tile-motion", "parallax"]
    )
    assert args.tile_motion == "parallax"


def test_media_validate_flag_parse() -> None:
    parser = cli.build_parser()
    args = parser.parse_args(["live", "fixtures/images", "--effect", "tile", "--media-validate"])
    assert args.media_validate is True


def test_animate_preset_sets_tile_video_and_parallax() -> None:
    parser = cli.build_parser()
    argv = ["live", "fixtures/images", "--grid", "3x1", "--animate"]
    args = parser.parse_args(argv)
    cli.apply_animate_preset(args, argv)
    assert args.animate == "full"
    assert args.effect == "tile"
    assert args.animate_videos is True
    assert args.tile_motion == "parallax"


def test_animate_videos_mode_skips_still_pan() -> None:
    parser = cli.build_parser()
    argv = ["live", "fixtures/images", "--grid", "3x1", "--animate", "videos"]
    args = parser.parse_args(argv)
    cli.apply_animate_preset(args, argv)
    assert args.animate == "videos"
    assert args.animate_videos is True
    assert args.tile_motion == "off"


def test_animate_preset_respects_explicit_tile_motion() -> None:
    parser = cli.build_parser()
    argv = ["live", "fixtures/images", "--grid", "3x1", "--animate", "--tile-motion", "ken-burns"]
    args = parser.parse_args(argv)
    cli.apply_animate_preset(args, argv)
    assert args.tile_motion == "ken-burns"


def test_main_tracks_explicit_tile_quality_flag() -> None:
    parser = cli.build_parser()
    argv = [
        "live",
        "fixtures/images",
        "--effect",
        "tile",
        "--tile-quality",
        "high",
    ]
    args = parser.parse_args(argv)
    args.tile_quality_explicit = cli._argv_has_option(argv, "--tile-quality")
    assert args.tile_quality_explicit is True
    argv2 = ["live", "fixtures/images", "--effect", "tile"]
    assert cli._argv_has_option(argv2, "--tile-quality") is False
