# amdxdna-flm-freeze

Repro for a hard machine freeze on AMD Strix Halo (Ryzen AI MAX+ 395) when the XDNA2 NPU and the Radeon 8060S iGPU work at the same time. See [amd/xdna-driver#1605](https://github.com/amd/xdna-driver/issues/1605).

**Warning:** `make freeze` freezes the whole machine. A power cycle is needed.

## Setup

```sh
git clone --recurse-submodules --shallow-submodules https://github.com/maciejmajek/amdxdna-flm-freeze.git
cd amdxdna-flm-freeze
sudo add-apt-repository -y ppa:lemonade-team/stable
sudo apt-get install -y build-essential cmake ninja-build git curl cargo \
  libvulkan-dev glslc vulkan-tools libxrt-dev libxrt-npu2 libedit-dev uuid-dev libdrm-dev
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

## Latest driver and XRT

To test with the driver and XRT from [amd/xdna-driver](https://github.com/amd/xdna-driver) main instead of the distribution ones:

```sh
git clone https://github.com/amd/xdna-driver.git ~/xdna-driver   # needs git-lfs
cd ~/xdna-driver && git submodule update --init --recursive
sudo ./tools/amdxdna_deps.sh
cd xrt/build && ./build.sh -npu -opt
sudo apt install ./Release/xrt_*-base.deb ./Release/xrt_*-base-dev.deb ./Release/xrt_*-npu.deb   # installs to /opt/xilinx/xrt
cd ../../build && ./build.sh -release
sudo apt install ./Release/xrt_plugin.*-amdxdna.deb   # DKMS amdxdna, replaces the loaded module
```

Then, in this repo:

```sh
make freeze-opt-xrt   # builds flm against /opt/xilinx/xrt and runs make freeze with it
```

Undo: `sudo apt remove xrt-plugin-amdxdna xrt-npu xrt-base-dev xrt-base`.

## System info

```sh
make info          # writes info.txt: kernel, BIOS, amdxdna, NPU firmware, XRT, Mesa, packages; no hostname or serials
```

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

Runs of this repo, unchanged:

| driver | command | result |
|---|---|---|
| in-tree amdxdna 0.7.0 | `make freeze` | **freeze** in cycle 1, about 1 s after the first image request |
| amdxdna 2.27.0 ([amd/xdna-driver](https://github.com/amd/xdna-driver) `55990418`), same firmware and XRT | `make freeze` | **freeze** in cycle 2 |
| amdxdna 2.27.0 and XRT 2.27.0, flm rebuilt against XRT 2.27 | `make freeze-opt-xrt` | **freeze** in cycle 4 |

The results above the last table come from the scripts this repo was made from. Load and requests are the same; paths and log layout differ.

### Fabric clock (FCLK)

The freeze depends on the iGPU/SoC clock management. With FCLK pinned, `make freeze` does not freeze. Run as root, `card1` is the iGPU here:

```sh
c=/sys/class/drm/card1/device
echo profile_peak > $c/power_dpm_force_performance_level   # all clocks pinned, or:
echo manual > $c/power_dpm_force_performance_level
echo 7 > $c/pp_dpm_fclk                                     # FCLK only, 2000 MHz
echo "0 7" > $c/pp_dpm_fclk                                 # FCLK dynamic again
echo auto > $c/power_dpm_force_performance_level           # default
```

The setting is lost at reboot. On this APU, `manual` mode accepts `pp_dpm_fclk` and `pp_dpm_socclk`; `pp_dpm_sclk` and `pp_dpm_mclk` give an I/O error.

amdxdna 2.27.0, XRT 2.27.0, NPU firmware 1.1.2.65, `make freeze`:

| setting | result |
|---|---|
| `auto` (default) | **freeze** in cycle 1 to 4, every run |
| `auto`, amdxdna loaded with `force_iova=1` | **freeze** in cycle 1 |
| `auto`, NPU turbo (`sudo xrt-smi configure --pmode turbo`, clock gating off) | **freeze** in cycle 1 |
| `profile_peak` | no freeze, 20/20 cycles (2 runs) |
| `auto` again, same boot | **freeze** in cycle 2 |
| `manual`, only FCLK pinned at 2000 MHz (SCLK still dynamic up to 2900 MHz) | no freeze, 20/20 cycles |
| `manual`, FCLK released, same boot | **freeze** in cycle 5 |

`flm serve --pmode` has no effect on Linux: FastFlowLM sets the power mode only on Windows. Use `xrt-smi`.

## Logs

[`logs/`](logs) has the kernel log tails of our 9 freezes and the Data Fabric MCE. In all 9, the last line is a `MSG_OP_CHAIN_EXEC_NPU` send on mailbox channel 127 that never gets a response. The MCE appeared 3 times, each time between a channel 127 send and its response. IP and MAC addresses and user and host names are removed.

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
