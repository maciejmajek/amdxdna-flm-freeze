// Memory-bandwidth load on the GPU (HIP): copies between two 1 GiB buffers for argv[1] seconds.
#include <hip/hip_runtime.h>
#include <chrono>
#include <cstdio>
#include <cstdlib>

__global__ void k(float* a, const float* b, size_t n) {
  size_t s = (size_t)gridDim.x * blockDim.x;
  for (size_t i = blockIdx.x * (size_t)blockDim.x + threadIdx.x; i < n; i += s) a[i] = b[i] * 1.0001f + 1.0f;
}

int main(int argc, char** argv) {
  double secs = argc > 1 ? atof(argv[1]) : 60;
  size_t n = (1ull << 30) / sizeof(float);
  float *a, *b;
  if (hipMalloc(&a, n * sizeof(float)) || hipMalloc(&b, n * sizeof(float))) { puts("hipMalloc failed"); return 1; }
  auto t0 = std::chrono::steady_clock::now();
  long launches = 0;
  while (std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count() < secs) {
    for (int i = 0; i < 20; i++) k<<<4096, 256>>>(a, b, n);
    hipDeviceSynchronize();
    launches += 20;
  }
  printf("%ld launches\n", launches);
  return 0;
}
