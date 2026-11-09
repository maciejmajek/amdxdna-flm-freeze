LLAMA := llama.cpp/build/bin/llama-server
FLM   := FastFlowLM/src/build/flm
GGUF  := models/gpt-oss-20b-Q4_K_M.gguf
ROCM  ?= /opt/rocm
MODE  ?= cycles

.PHONY: deps build freeze
freeze: run-vkcube

deps:
	sudo add-apt-repository -y ppa:lemonade-team/stable
	sudo apt-get install -y build-essential cmake ninja-build git curl cargo \
	  libvulkan-dev glslc vulkan-tools \
	  libxrt-dev libxrt-npu2 libedit-dev uuid-dev libdrm-dev

build: $(LLAMA) $(FLM) $(GGUF)
	$(FLM) pull gemma3:4b

$(LLAMA):
	git submodule update --init --depth 1 llama.cpp
	cmake -S llama.cpp -B llama.cpp/build -DGGML_VULKAN=ON -DLLAMA_CURL=OFF -DLLAMA_BUILD_UI=OFF \
	  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF
	cmake --build llama.cpp/build --config Release -j --target llama-server

$(FLM):
	git submodule update --init --recursive --depth 1 FastFlowLM
	cd FastFlowLM/src && cmake --preset linux-default -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ && cmake --build build -j
	cd FastFlowLM/src && cp model_list.json model_info.json build/ && ln -sfn ../xclbins build/xclbins

$(GGUF):
	mkdir -p models
	curl -L --fail -o $@.part https://huggingface.co/unsloth/gpt-oss-20b-GGUF/resolve/main/gpt-oss-20b-Q4_K_M.gguf
	mv $@.part $@

gpu_load: gpu_load.hip
	$(ROCM)/bin/hipcc --offload-arch=gfx1151 -O2 -I$(ROCM)/include -L$(ROCM)/lib -Wl,-rpath,$(ROCM)/lib -o $@ $<

# make run-<load> [MODE=cycles|loop|text]; see README.md.
run-hip run-all: gpu_load
run-%: build
	./repro.sh $* $(MODE)
