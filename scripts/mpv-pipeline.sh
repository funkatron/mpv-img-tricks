#!/usr/bin/env bash
set -euo pipefail

# Canonical mpv launch pipeline for slideshow-like entrypoints.
# Handles:
# - normalized mpv flag construction
# - optional split-playlist multi-instance launching

DURATION="0.001"
PLAYLIST_FILE=""
FULLSCREEN="true"
SHUFFLE="false"
LOOP_MODE="playlist" # none|file|playlist
SCALE_MODE="fit"     # fit|fill
DOWNSCALE_LARGER="true"
USE_BLAST_SCRIPT="true"
NO_AUDIO="true"
WATCH_IPC_SOCKET=""
INSTANCES="1"
DISPLAY=""
DISPLAY_MAP=""
MASTER_CONTROL="auto"
DEBUG="false"

declare -a MPV_ARG_PASSTHROUGH=()
declare -a EXTRA_SCRIPTS=()
declare -a CHILD_PIDS=()
declare -a SOCKET_FILES=()
declare -a FOLLOWER_SOCKETS=()
declare -a INSTANCE_PLAYLISTS=()
BRIDGE_PID=""

usage() {
  cat <<'EOF'
Usage: mpv-pipeline.sh --playlist FILE [options]

Options:
  --playlist FILE                 Playlist file path (required)
  --duration SECONDS              image-display-duration value
  --fullscreen yes|no             Fullscreen toggle (default: yes)
  --shuffle yes|no                Shuffle toggle
  --loop-mode MODE                none|file|playlist (default: playlist)
  --scale-mode MODE               fit|fill (default: fit)
  --downscale-larger yes|no       Keep/downscale larger images (default: yes)
  --use-blast-script yes|no       Load mpv-scripts/blast.lua if present
  --no-audio yes|no               Pass --no-audio (default: yes)
  --watch-ipc-socket PATH         mpv IPC socket path
  --instances N                   Number of mpv instances (default: 1)
  --display INDEX                 Preferred display index for single instance
  --display-map CSV               Per-instance display mapping (e.g. 0,1,2)
  --master-control yes|no|auto    Sync followers from master (default: auto)
  --extra-script PATH             Additional --script path (repeatable)
  --mpv-arg ARG                   Raw mpv argument passthrough (repeatable)
  --debug yes|no                  Print resolved launch details
  --help                          Show this help
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

is_yes() {
  [[ "${1:-}" == "yes" || "${1:-}" == "true" ]]
}

is_no() {
  [[ "${1:-}" == "no" || "${1:-}" == "false" ]]
}

resolve_repo_root() {
  local source="${BASH_SOURCE[0]}"
  while [[ -L "$source" ]]; do
    local dir
    dir="$(cd "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    [[ "$source" != /* ]] && source="${dir}/${source}"
  done
  cd "$(dirname "$source")/.." >/dev/null 2>&1 && pwd
}

collect_loop_flags() {
  case "$LOOP_MODE" in
    none)
      printf '%s\n' "--loop-file=no" "--loop-playlist=no"
      ;;
    file)
      printf '%s\n' "--loop-file=inf"
      ;;
    playlist)
      printf '%s\n' "--loop-playlist=inf"
      ;;
    *)
      die "Invalid --loop-mode '$LOOP_MODE' (expected none|file|playlist)"
      ;;
  esac
}

collect_scale_flags() {
  case "$SCALE_MODE" in
    fit)
      printf '%s\n' "--keepaspect"
      ;;
    fill)
      printf '%s\n' "--no-keepaspect"
      ;;
    *)
      die "Invalid --scale-mode '$SCALE_MODE' (expected fit|fill)"
      ;;
  esac

  if is_no "$DOWNSCALE_LARGER"; then
    printf '%s\n' "--no-keepaspect-window"
  fi
}

collect_display_flags() {
  local display_index="$1"
  if [[ -z "$display_index" ]]; then
    return
  fi
  if is_yes "$FULLSCREEN"; then
    printf '%s\n' "--fs-screen=${display_index}"
  else
    printf '%s\n' "--screen=${display_index}"
  fi
}

build_base_args() {
  local repo_root="$1"

  BASE_ARGS=()

  BASE_ARGS+=("--image-display-duration=${DURATION}")

  if is_yes "$FULLSCREEN"; then
    BASE_ARGS+=("--fullscreen")
  fi
  if is_yes "$SHUFFLE"; then
    BASE_ARGS+=("--shuffle")
  fi
  if is_yes "$NO_AUDIO"; then
    BASE_ARGS+=("--no-audio")
  fi

  local loop_flag
  while IFS= read -r loop_flag; do
    [[ -n "$loop_flag" ]] && BASE_ARGS+=("$loop_flag")
  done < <(collect_loop_flags)

  local scale_flag
  while IFS= read -r scale_flag; do
    [[ -n "$scale_flag" ]] && BASE_ARGS+=("$scale_flag")
  done < <(collect_scale_flags)

  if [[ -n "$WATCH_IPC_SOCKET" ]]; then
    BASE_ARGS+=("--input-ipc-server=${WATCH_IPC_SOCKET}")
  fi

  if is_yes "$USE_BLAST_SCRIPT"; then
    local blast_script="${repo_root}/mpv-scripts/blast.lua"
    if [[ -f "$blast_script" ]]; then
      BASE_ARGS+=("--script=${blast_script}")
    elif is_yes "$DEBUG"; then
      echo "Debug: blast.lua not found at ${blast_script}" >&2
    fi
  fi

  local script_path
  for script_path in "${EXTRA_SCRIPTS[@]:-}"; do
    [[ -n "$script_path" ]] && BASE_ARGS+=("--script=${script_path}")
  done

  if ((${#MPV_ARG_PASSTHROUGH[@]} > 0)); then
    BASE_ARGS+=("${MPV_ARG_PASSTHROUGH[@]}")
  fi
}

split_playlist_round_robin() {
  local source_list="$1"
  local instance_count="$2"
  local target_dir="$3"

  local i
  INSTANCE_PLAYLISTS=()
  for ((i=0; i<instance_count; i++)); do
    local file_path="${target_dir}/instance-$((i+1)).m3u"
    : > "$file_path"
    INSTANCE_PLAYLISTS+=("$file_path")
  done

  local line index=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local bucket=$((index % instance_count))
    echo "$line" >> "${INSTANCE_PLAYLISTS[$bucket]}"
    index=$((index + 1))
  done < "$source_list"
}

cleanup_children() {
  local pid
  for pid in "${CHILD_PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  if [[ -n "$BRIDGE_PID" ]]; then
    kill "$BRIDGE_PID" 2>/dev/null || true
  fi
  local socket_path
  for socket_path in "${SOCKET_FILES[@]:-}"; do
    rm -f "$socket_path"
  done
}

ipc_send_json() {
  local socket_path="$1"
  local json_payload="$2"
  python3 - "$socket_path" "$json_payload" <<'PY' >/dev/null 2>&1 || true
import socket
import sys

sock_path = sys.argv[1]
payload = sys.argv[2]
try:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.6)
    client.connect(sock_path)
    client.send((payload + "\n").encode("utf-8"))
    try:
        client.recv(65535)
    except Exception:
        pass
    client.close()
except Exception:
    pass
PY
}

ipc_get_property() {
  local socket_path="$1"
  local prop_name="$2"
  python3 - "$socket_path" "$prop_name" <<'PY' 2>/dev/null || true
import json
import socket
import sys

sock_path = sys.argv[1]
prop_name = sys.argv[2]
payload = json.dumps({"command": ["get_property", prop_name]})

try:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.6)
    client.connect(sock_path)
    client.send((payload + "\n").encode("utf-8"))
    response = client.recv(65535).decode("utf-8", errors="ignore")
    client.close()

    data = json.loads(response)
    value = data.get("data")
    if isinstance(value, bool):
        print("true" if value else "false")
    elif value is None:
        print("")
    else:
        print(value)
except Exception:
    print("")
PY
}

sync_followers() {
  local json_payload="$1"
  local socket_path
  for socket_path in "${FOLLOWER_SOCKETS[@]:-}"; do
    ipc_send_json "$socket_path" "$json_payload"
  done
}

start_master_control_bridge() {
  local master_socket="$1"
  local master_pid="$2"

  (
    local prev_pos=""
    local prev_pause=""
    local curr_pos=""
    local curr_pause=""
    local step

    while kill -0 "$master_pid" 2>/dev/null; do
      curr_pos="$(ipc_get_property "$master_socket" "playlist-pos")"
      curr_pause="$(ipc_get_property "$master_socket" "pause")"

      if [[ "$curr_pos" =~ ^-?[0-9]+$ ]] && [[ "$prev_pos" =~ ^-?[0-9]+$ ]] && [[ "$curr_pos" != "$prev_pos" ]]; then
        step=$((curr_pos - prev_pos))
        if [[ "$step" -eq 1 ]]; then
          sync_followers '{"command":["playlist-next","weak"]}'
        elif [[ "$step" -eq -1 ]]; then
          sync_followers '{"command":["playlist-prev","weak"]}'
        else
          sync_followers "{\"command\":[\"set_property\",\"playlist-pos\",${curr_pos}]}"
        fi
      fi

      if [[ -n "$curr_pause" && "$curr_pause" != "$prev_pause" ]]; then
        if [[ "$curr_pause" == "true" ]]; then
          sync_followers '{"command":["set_property","pause",true]}'
        elif [[ "$curr_pause" == "false" ]]; then
          sync_followers '{"command":["set_property","pause",false]}'
        fi
      fi

      prev_pos="$curr_pos"
      prev_pause="$curr_pause"
      sleep 0.12
    done
  ) &

  BRIDGE_PID="$!"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --playlist)
      PLAYLIST_FILE="${2:-}"
      shift 2
      ;;
    --duration)
      DURATION="${2:-}"
      shift 2
      ;;
    --fullscreen)
      FULLSCREEN="${2:-}"
      shift 2
      ;;
    --shuffle)
      SHUFFLE="${2:-}"
      shift 2
      ;;
    --loop-mode)
      LOOP_MODE="${2:-}"
      shift 2
      ;;
    --scale-mode)
      SCALE_MODE="${2:-}"
      shift 2
      ;;
    --downscale-larger)
      DOWNSCALE_LARGER="${2:-}"
      shift 2
      ;;
    --use-blast-script)
      USE_BLAST_SCRIPT="${2:-}"
      shift 2
      ;;
    --no-audio)
      NO_AUDIO="${2:-}"
      shift 2
      ;;
    --watch-ipc-socket)
      WATCH_IPC_SOCKET="${2:-}"
      shift 2
      ;;
    --instances)
      INSTANCES="${2:-}"
      shift 2
      ;;
    --display)
      DISPLAY="${2:-}"
      shift 2
      ;;
    --display-map)
      DISPLAY_MAP="${2:-}"
      shift 2
      ;;
    --master-control)
      MASTER_CONTROL="${2:-}"
      shift 2
      ;;
    --extra-script)
      EXTRA_SCRIPTS+=("${2:-}")
      shift 2
      ;;
    --mpv-arg)
      MPV_ARG_PASSTHROUGH+=("${2:-}")
      shift 2
      ;;
    --debug)
      DEBUG="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[[ -n "$PLAYLIST_FILE" ]] || die "--playlist is required"
[[ -f "$PLAYLIST_FILE" ]] || die "Playlist file does not exist: $PLAYLIST_FILE"
[[ "$INSTANCES" =~ ^[0-9]+$ ]] || die "--instances must be a positive integer"
((INSTANCES >= 1)) || die "--instances must be at least 1"
case "$MASTER_CONTROL" in
  yes|true)
    MASTER_CONTROL="true"
    ;;
  no|false)
    MASTER_CONTROL="false"
    ;;
  auto)
    ;;
  *)
    die "Invalid --master-control value '$MASTER_CONTROL' (expected yes|no|auto)"
    ;;
esac

if ((INSTANCES > 1)) && [[ -n "$WATCH_IPC_SOCKET" ]]; then
  die "watch mode is currently supported only for --instances 1"
fi

if ((INSTANCES > 1)) && [[ "$MASTER_CONTROL" == "auto" ]]; then
  MASTER_CONTROL="true"
elif ((INSTANCES == 1)); then
  MASTER_CONTROL="false"
fi

REPO_ROOT="$(resolve_repo_root)"
declare -a BASE_ARGS=()
build_base_args "$REPO_ROOT"

if ((INSTANCES == 1)); then
  declare -a SINGLE_ARGS=("${BASE_ARGS[@]}")
  while IFS= read -r display_flag; do
    [[ -n "$display_flag" ]] && SINGLE_ARGS+=("$display_flag")
  done < <(collect_display_flags "$DISPLAY")
  SINGLE_ARGS+=("--playlist=${PLAYLIST_FILE}")
  if is_yes "$DEBUG"; then
    printf 'Debug: launching single instance: mpv'
    printf ' %q' "${SINGLE_ARGS[@]}"
    printf '\n'
  fi
  exec mpv "${SINGLE_ARGS[@]}"
fi

TMP_DIR="$(mktemp -d)"
trap 'cleanup_children; rm -rf "$TMP_DIR"' EXIT INT TERM

split_playlist_round_robin "$PLAYLIST_FILE" "$INSTANCES" "$TMP_DIR"

IFS=',' read -r -a DISPLAY_MAP_LIST <<< "$DISPLAY_MAP"
MASTER_SOCKET=""
MASTER_PID=""

for ((i=0; i<INSTANCES; i++)); do
  if [[ ! -s "${INSTANCE_PLAYLISTS[$i]}" ]]; then
    continue
  fi

  declare -a INSTANCE_ARGS=("${BASE_ARGS[@]}")

  if ((${#DISPLAY_MAP_LIST[@]} > i)) && [[ -n "${DISPLAY_MAP_LIST[$i]}" ]]; then
    while IFS= read -r display_flag; do
      [[ -n "$display_flag" ]] && INSTANCE_ARGS+=("$display_flag")
    done < <(collect_display_flags "${DISPLAY_MAP_LIST[$i]}")
  elif [[ -n "$DISPLAY" && $i -eq 0 ]]; then
    while IFS= read -r display_flag; do
      [[ -n "$display_flag" ]] && INSTANCE_ARGS+=("$display_flag")
    done < <(collect_display_flags "$DISPLAY")
  fi

  local_ipc="$(mktemp -u "/tmp/mpv-pipeline-$((i+1))-XXXXXX.socket")"
  SOCKET_FILES+=("$local_ipc")
  INSTANCE_ARGS+=("--input-ipc-server=${local_ipc}")
  INSTANCE_ARGS+=("--playlist=${INSTANCE_PLAYLISTS[$i]}")

  if is_yes "$DEBUG"; then
    printf 'Debug: launching instance %d: mpv' "$((i + 1))"
    printf ' %q' "${INSTANCE_ARGS[@]}"
    printf '\n'
  fi

  mpv "${INSTANCE_ARGS[@]}" >/dev/null 2>&1 &
  current_pid="$!"
  CHILD_PIDS+=("$current_pid")

  if [[ -z "$MASTER_PID" ]]; then
    MASTER_PID="$current_pid"
    MASTER_SOCKET="$local_ipc"
  else
    FOLLOWER_SOCKETS+=("$local_ipc")
  fi
done

if ((${#CHILD_PIDS[@]} == 0)); then
  die "No playable items were assigned to instances."
fi

if [[ "$MASTER_CONTROL" == "true" && -n "$MASTER_PID" && ${#FOLLOWER_SOCKETS[@]} -gt 0 ]]; then
  if is_yes "$DEBUG"; then
    echo "Debug: starting master-control bridge (followers=${#FOLLOWER_SOCKETS[@]})"
  fi
  start_master_control_bridge "$MASTER_SOCKET" "$MASTER_PID"
fi

wait "${CHILD_PIDS[@]}"
