#!/bin/bash
# Prints the system facts for a bug report. No hostname, user name, serial number or address.
s() { echo; echo "## $1"; }
s system;   uname -srvm; cat /sys/class/dmi/id/{sys_vendor,product_name,bios_version,bios_date} 2>/dev/null
s cpu;      grep -m1 "model name" /proc/cpuinfo
s memory;   free -g | head -2
s cmdline;  tr ' ' '\n' < /proc/cmdline | grep -E "amd|iommu|gtt|ttm" || echo "(no amd/iommu/ttm options)"
s amdxdna;  modinfo amdxdna 2>/dev/null | grep -E "^(filename|version):"; lsmod | grep -E "^amdxdna" || echo "(amdxdna not loaded)"
s npu;      xrt-smi examine 2>/dev/null | grep -iE "version|firmware|npu|xrt|amdxdna" | grep -viE "host|serial|bdf" || echo "(xrt-smi not found)"
s vulkan;   vulkaninfo --summary 2>/dev/null | grep -E "apiVersion|driverInfo|deviceName" || echo "(vulkaninfo not found)"
s packages; dpkg-query -W 'libxrt*' 'amdxdna*' mesa-vulkan-drivers linux-firmware 2>/dev/null
s submodules; git -C "$(dirname "$0")" submodule status
