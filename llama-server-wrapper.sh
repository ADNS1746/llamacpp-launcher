#!/bin/bash
# Wrapper script for llama.cpp server (reads /opt/llamacpp-launcher/config.conf)
# Usage:
#   llama-server-wrapper.sh start [--model <path>]
#   llama-server-wrapper.sh stop|status|restart
PID_FILE="/tmp/llama-server.pid"

# Load central configuration (bash-compatible format)
CONFIG_FILE_CONF="/opt/llamacpp-launcher/config.conf"
if [ -f "$CONFIG_FILE_CONF" ]; then
    set -a
    source "$CONFIG_FILE_CONF"
    set +a
fi

# Override model via CLI or env
get_model() {
    if [ -n "$MODEL_PATH" ]; then
        echo "$MODEL_PATH"
        return
    fi
    if [ -f "$CONFIG_FILE_CONF" ]; then
        local saved
        saved=$(head -1 "/opt/llamacpp-launcher/current_model.txt" 2>/dev/null)
        if [ -n "$saved" ] && [ -f "$saved" ]; then
            echo "$saved"
            return
        fi
    fi
    echo "${DEFAULT_MODEL:-/opt/textgen/user_data/models/Unsloth_Qwen3-14B-128K-Q4_K_M.gguf}"
}

build_cmd() {
    local m="$1"
    # Read other params from config (default if not set)
    local ctx_size=${CTX_SIZE:-16384}
    local n_gpu_layers=${NGPU_LAYERS:-all}
    local threads=${THREADS:-6}
    local threads_batch=${THREADS_BATCH:-12}
    local flash_attn=${FLASH_ATTN:-on}
    local batch_size=${BATCH_SIZE:-1024}
    local ubatch_size=${UBATCH_SIZE:-256}
    local parallel=${PARALLEL:-1}
    local host=${HOST:-192.168.2.54}
    local port=${PORT:-8081}
    echo "${BIN:-/opt/llamacpp/bin/llama-server} -m '$m' --ctx-size $ctx_size --n-gpu-layers $n_gpu_layers --threads $threads --threads-batch $threads_batch --flash-attn $flash_attn --batch-size $batch_size --ubatch-size $ubatch_size --parallel $parallel --host $host --port $port"
}

export LD_LIBRARY_PATH="${LD_LIB:-/opt/llamacpp/bin}"
LOG_FILE="${LOG_FILE:-/opt/llamacpp-launcher/llama-server.log}"
MODEL_CONFIG_FILE="${CONFIG_FILE:-/opt/llamacpp-launcher/current_model.txt}"
PID_FILE="${PID_FILE:-/tmp/llama-server.pid}"

if id llama.cpp &>/dev/null; then
    TARGET_USER="llama.cpp"
else
    TARGET_USER="$USER"
fi

notify() {
    local title="$1"
    local body="$2"
    command -v notify-send &>/dev/null && notify-send "$title" "$body" --icon=dialog-information --timeout=5000 2>/dev/null || true
}

is_running() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

launch_server() {
    if is_running; then
        notify "Llama.cpp" "Le serveur est déjà en cours d'exécution (PID $(cat "$PID_FILE"))"
        return 1
    fi

    : > "$LOG_FILE"

    local model cmd child_pid
    model=$(get_model)
    echo "$model" > "$MODEL_CONFIG_FILE"
    cmd=$(build_cmd "$model")

    # Detach from terminal/session so wrapper exit doesn't kill server
    trap - EXIT HUP INT TERM

    if [ "$TARGET_USER" = "$USER" ]; then
        nohup bash -c "echo \$\$ > '$PID_FILE'; exec $cmd" </dev/null >>"$LOG_FILE" 2>&1 &
    else
        nohup runuser -u "$TARGET_USER" -- bash -c "echo \$\$ > '$PID_FILE'; exec $cmd" </dev/null >>"$LOG_FILE" 2>&1 &
    fi
    child_pid=$!
    disown 2>/dev/null || true
    disown 2>/dev/null || true

    echo "$child_pid" > "$PID_FILE"
    notify "Llama.cpp" "Serveur démarré (PID $child_pid) sur http://${HOST:-192.168.2.54}:${PORT:-8081}"
    >&2 echo "Serveur démarré (PID $child_pid) avec modèle : $model"
    return 0
}

stop_server() {
    if ! is_running; then
        notify "Llama.cpp" "Le serveur n'est pas en cours d'exécution"
        return 1
    fi
    local pid; pid=$(cat "$PID_FILE")
    kill "$pid" 2>/dev/null || true
    local waited=0; local max_wait=10
    while kill -0 "$pid" 2>/dev/null && [ $waited -lt $max_wait ]; do
        sleep 0.5; waited=$((waited + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid" 2>/dev/null || true; fi
    rm -f "$PID_FILE"
    >&2 echo "Serveur arrêté"
    notify "Llama.cpp" "Serveur arrêté"
    return 0
}

cleanup() {
    stop_server 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

# Parse arguments
ARG_MODEL=""
case "${1:-}" in
    start)
        shift
        while [ $# -gt 0 ]; do
            case "$1" in
                --model) shift; ARG_MODEL="$1";;
            esac
            shift
        done
        if [ -n "$ARG_MODEL" ]; then export MODEL_PATH="$ARG_MODEL"; fi
        launch_server
        ;;
    stop) stop_server ;;
    status)
        if is_running; then echo "Serveur en cours d'exécution (PID $(cat "$PID_FILE"))"; echo "Modèle : $(cat "$MODEL_CONFIG_FILE" 2>/dev/null || echo 'inconnu')"; else echo "Serveur arrêté"; fi
        ;;
    restart)
        stop_server; sleep 1; launch_server ;;
    *)
        # Foreground mode (terminal session): server stops when terminal closes
        if is_running; then
            notify "Llama.cpp" "Le serveur est déjà en cours d'exécution (PID $(cat "$PID_FILE"))"
            >&2 echo "Serveur déjà en cours d'exécution (PID $(cat "$PID_FILE"))"
            exit 0
        fi
        : > "$LOG_FILE"
        local model_path; model_path=$(get_model)
        if [ "$TARGET_USER" = "$USER" ]; then
            bash -c "echo \$\$ > '$PID_FILE'; exec $(build_cmd "$model_path")" >>"$LOG_FILE" 2>&1 &
        else
            runuser -u "$TARGET_USER" -- bash -c "echo \$\$ > '$PID_FILE'; exec $(build_cmd "$model_path")" >>"$LOG_FILE" 2>&1 &
        fi
        child_pid=$!
        echo "$child_pid" > "$PID_FILE"
        notify "Llama.cpp" "Serveur démarré (PID $child_pid)"
        >&2 echo "Serveur démarré (PID $child_pid) sur http://${HOST:-192.168.2.54}:${PORT:-8081}"
        wait "$child_pid" 2>/dev/null
        exit_code=$?
        rm -f "$PID_FILE"
        if [ "$exit_code" -ne 0 ] 2>/dev/null; then notify "Erreur Llama.cpp" "Le serveur s'est arrêté avec le code $exit_code"; fi
        exit $exit_code
        ;;
esac
