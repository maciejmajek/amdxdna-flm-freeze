# amdxdna-flm-freeze

Repro for a hard machine freeze on AMD Strix Halo (Ryzen AI MAX+ 395) when the XDNA2 NPU and the Radeon 8060S iGPU work at the same time. See [amd/xdna-driver#1605](https://github.com/amd/xdna-driver/issues/1605).

**Warning:** `make freeze` freezes the whole machine. A power cycle is needed.

## Setup

```sh
git clone --recurse-submodules --shallow-submodules https://github.com/maciejmajek/amdxdna-flm-freeze.git
cd amdxdna-flm-freeze
make deps          # apt packages (sudo)
make build         # llama.cpp (Vulkan), FastFlowLM, gpt-oss-20b GGUF (12 GB), gemma3:4b
sudo modprobe amdxdna
```

Run from a desktop session: `vkcube` needs a display.

## Run

```sh
make freeze        # same as: make run-vkcube
```

`make run-<load> MODE=<mode>` runs one workflow:

| load | what keeps the iGPU busy |
|---|---|
| `none` | nothing |
| `hip` | HIP memory-bandwidth kernel, about 180 GB/s (needs ROCm, `ROCM=/opt/rocm`) |
| `cube` | 4 `vkcube` windows |
| `vk` | llama.cpp (Vulkan) generates text in a loop |
| `vkcube` | `vk` + `cube` |
| `all` | `hip` + `vk` + `cube` |

| mode | what the NPU does (FastFlowLM, gemma3:4b) |
|---|---|
| `cycles` (default) | start flm, send 4 parallel 1-token image requests, stop flm; 20 times |
| `loop` | start flm once, 4 parallel loops of 1-token image requests for 30 s |
| `text` | as `loop`, with text requests |

Env: `CYCLES`, `DUR` (seconds), `LOOPS` (parallel requests).

Logs go to `runs/<time>-<load>-<mode>/`. Each line of `progress.log` is synced to disk, so after a freeze the last line shows the last step.

## Results

Kernel 7.0.0-31, in-tree amdxdna 0.7.0, NPU firmware 1.1.2.65, XRT 2.21.75, Mesa RADV 25.2.8, BIOS 1.05, GMKtec EVO-X2.

| command | result |
|---|---|
| `make run-none MODE=loop` | no freeze |
| `make run-hip MODE=loop` | no freeze (2 runs) |
| `make run-cube MODE=loop` | no freeze |
| `make run-vk MODE=loop` | no freeze (2 runs) |
| `make run-vkcube MODE=loop` | **freeze** in 2 of 3 runs, within 10 s |
| `make run-vkcube` | **freeze** in cycle 1, within 15 s |
| `make run-all MODE=loop` | no freeze (2 runs, one with `DUR=180 LOOPS=8`) |
| `make run-<any> MODE=text` | no freeze |

These results come from the scripts this repo was made from. Load and requests are the same; paths and log layout differ.

## Kernel log over the network

Netconsole sends the kernel log to a second machine, so the last lines before the freeze are kept:

```sh
# on the second machine
socat -u UDP-RECV:6666,reuseaddr OPEN:netconsole.log,creat,append
# on this machine
sudo modprobe netconsole netconsole=6665@<this ip>/<iface>,6666@<other ip>/<other mac>
sudo dmesg -n 8
echo 'module amdxdna +p' | sudo tee /sys/kernel/debug/dynamic_debug/control
```

In our runs the last line is an `amdxdna` mailbox send of `MSG_OP_CHAIN_EXEC_NPU` (opcode 0x18) with no response, then nothing.
