#!/bin/bash
# Usage: ./repro.sh <load> [mode]
#   load: none | hip | cube | vk | vkcube | all   (what keeps the iGPU busy)
#   mode: cycles | loop | text                     (what the NPU does)
# Env: CYCLES (cycles mode, default 20), DUR (loop/text seconds, default 30), LOOPS (parallel requests, default 4).
# WARNING: load vkcube can freeze the machine; a power cycle is then needed.
set -u
LOAD=${1:?load: none|hip|cube|vk|vkcube|all} MODE=${2:-cycles}
DIR=$(cd "$(dirname "$0")" && pwd)
FLM=$DIR/FastFlowLM/src/build/flm
LLAMA=$DIR/llama.cpp/build/bin/llama-server
GGUF=$DIR/models/gpt-oss-20b-Q4_K_M.gguf
LOOPS=${LOOPS:-4}
OUT=$DIR/runs/$(date +%Y%m%d-%H%M%S)-$LOAD-$MODE
mkdir -p "$OUT"; cd "$OUT"
PIDS=""
trap 'kill $PIDS ${FLMP:-} 2>/dev/null' EXIT
# Each line is synced to disk, so after a power cycle the last line shows where it froze.
log() { echo "$(date +%T.%N | cut -c1-12) gpu_busy=$(cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1) $*" | tee -a progress.log; sync progress.log; }

printf '{"model":"gemma3:4b","max_tokens":1,"messages":[{"role":"user","content":[{"type":"text","text":"Describe this image."},{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,%s"}}]}]}' "$(base64 -w0 "$DIR/image.jpg")" > img_req.json
printf '{"model":"gemma3:4b","max_tokens":64,"messages":[{"role":"user","content":"Write a long essay about warehouses."}]}' > text_req.json

cube() { for i in 1 2 3 4; do vkcube > /dev/null 2>&1 < /dev/null & PIDS="$PIDS $!"; done; }
hip() { "$DIR/gpu_load" 3600 > gpu_load.log 2>&1 & PIDS="$PIDS $!"; }
vk() {
  "$LLAMA" -m "$GGUF" -ngl 99 -c 8192 --host 127.0.0.1 --port 8098 > llama.log 2>&1 < /dev/null & PIDS="$PIDS $!"
  for i in $(seq 180); do curl -sf localhost:8098/health > /dev/null && break; sleep 1; done
  ( while :; do curl -s -m 300 localhost:8098/completion -d '{"prompt":"Write a long essay about warehouses.","n_predict":512}' > /dev/null; done ) & PIDS="$PIDS $!"
}
start_flm() {
  "$FLM" serve gemma3:4b --host 127.0.0.1 --port 8099 > "flm_$1.log" 2>&1 < /dev/null & FLMP=$!
  for i in $(seq 240); do curl -sf localhost:8099/v1/models > /dev/null && return; sleep 0.5; done
  log "flm did not start, see $OUT/flm_$1.log"; exit 1
}
req() { curl -s -m 60 localhost:8099/v1/chat/completions -H 'Content-Type: application/json' -d @"$1" > /dev/null; }

case $LOAD in
  none) ;; hip) hip ;; cube) cube ;; vk) vk ;; vkcube) vk; cube ;; all) hip; vk; cube ;;
  *) echo "unknown load: $LOAD"; exit 2 ;;
esac
log "load=$LOAD mode=$MODE: GPU load started"
sleep 5

case $MODE in
  cycles)
    for c in $(seq "${CYCLES:-20}"); do
      log "cycle $c: start flm"; start_flm "$c"
      log "cycle $c: $LOOPS parallel image requests"
      CP=""; for j in $(seq "$LOOPS"); do req img_req.json & CP="$CP $!"; done; wait $CP
      kill $FLMP; wait $FLMP 2>/dev/null; FLMP=
    done ;;
  loop|text)
    f=img_req.json; [ "$MODE" = text ] && f=text_req.json
    start_flm 1
    log "$LOOPS parallel $f loops for ${DUR:-30} s"
    end=$((SECONDS + ${DUR:-30})); CP=""
    for j in $(seq "$LOOPS"); do ( while [ $SECONDS -lt $end ]; do req $f; log "loop $j: request done"; done ) & CP="$CP $!"; done
    wait $CP ;;
  *) echo "unknown mode: $MODE"; exit 2 ;;
esac
log "no hang"
