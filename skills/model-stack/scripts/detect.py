#!/usr/bin/env python3
"""Detect system hardware and installed model hosting stacks."""

from __future__ import annotations

import json
import os
import platform
import re
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass
from typing import Any


@dataclass
class HardwareInfo:
    os_name: str = ""
    os_version: str = ""
    cpu_name: str = ""
    cpu_cores_physical: int = 0
    cpu_cores_logical: int = 0
    cpu_arch: str = ""
    ram_gb: float = 0.0
    gpus: list[GPUInfo] | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class GPUInfo:
    name: str = ""
    vram_gb: float = 0.0
    driver: str = ""
    backend: str = ""  # cuda, rocm, mps, openvino, etc.


@dataclass
class StackInfo:
    name: str = ""
    version: str = ""
    path: str = ""


def run(cmd: list[str] | str, timeout: int = 10) -> str:
    """Run a shell command and return stdout."""
    try:
        if isinstance(cmd, str):
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        else:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.stdout.strip()
    except Exception:
        return ""


def detect_os() -> tuple[str, str]:
    """Detect OS name and version."""
    system = platform.system()
    if system == "Darwin":
        version = run(["sw_vers", "-productVersion"])
        return "macOS", version or ""
    if system == "Linux":
        # Try /etc/os-release first
        if os.path.exists("/etc/os-release"):
            with open("/etc/os-release") as f:
                data = f.read()
            name_match = re.search(r'PRETTY_NAME="([^"]*)"', data)
            name = name_match.group(1) if name_match else platform.linux_distribution()[0] if hasattr(platform, "linux_distribution") else "Linux"
            return name, ""
        return "Linux", ""
    if system == "Windows":
        return "Windows", platform.version()
    return system, ""


def detect_cpu() -> tuple[str, int, int, str]:
    """Detect CPU name, physical cores, logical cores, architecture."""
    cpu_name = ""
    physical = os.cpu_count() or 0
    logical = physical
    arch = platform.machine()

    system = platform.system()
    if system == "Darwin":
        cpu_name = run(["sysctl", "-n", "machdep.cpu.brand_string"])
        physical = int(run(["sysctl", "-n", "hw.physicalcpu"]) or logical)
        logical = int(run(["sysctl", "-n", "hw.logicalcpu"]) or physical)
    elif system == "Linux":
        lscpu = run(["lscpu"])
        if lscpu:
            model_match = re.search(r"Model name:\s*(.+)", lscpu)
            if model_match:
                cpu_name = model_match.group(1).strip()
            core_match = re.search(r"Core\(s\) per socket:\s*(\d+)", lscpu)
            socket_match = re.search(r"Socket\(s\):\s*(\d+)", lscpu)
            if core_match and socket_match:
                physical = int(core_match.group(1)) * int(socket_match.group(1))
        # Fallback to /proc/cpuinfo
        if not cpu_name and os.path.exists("/proc/cpuinfo"):
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if line.startswith("model name"):
                        cpu_name = line.split(":", 1)[1].strip()
                        break
    elif system == "Windows":
        cpu_name = run(["wmic", "cpu", "get", "Name", "/value"])
        cpu_name = cpu_name.replace("Name=", "").strip() if "Name=" in cpu_name else cpu_name

    if not cpu_name:
        cpu_name = platform.processor() or "Unknown"

    return cpu_name, physical, logical, arch


def detect_ram() -> float:
    """Detect total RAM in GB."""
    try:
        import psutil
        return psutil.virtual_memory().total / (1024 ** 3)
    except ImportError:
        pass

    system = platform.system()
    if system == "Darwin":
        mem = run(["sysctl", "-n", "hw.memsize"])
        if mem:
            return int(mem) / (1024 ** 3)
    elif system == "Linux":
        if os.path.exists("/proc/meminfo"):
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        kb = int(line.split()[1])
                        return kb / (1024 ** 2)
    elif system == "Windows":
        mem = run(["wmic", "computersystem", "get", "TotalPhysicalMemory", "/value"])
        match = re.search(r"TotalPhysicalMemory=(\d+)", mem)
        if match:
            return int(match.group(1)) / (1024 ** 3)

    return 0.0


def detect_nvidia_gpus() -> list[GPUInfo]:
    """Detect NVIDIA GPUs using nvidia-smi."""
    gpus = []
    smi = run(["nvidia-smi", "--query-gpu=name,memory.total,driver_version", "--format=csv,noheader"])
    if not smi:
        return gpus
    for line in smi.split("\n"):
        parts = [p.strip() for p in line.split(",")]
        if len(parts) >= 3:
            name = parts[0]
            mem_str = parts[1]
            driver = parts[2]
            # Parse memory (usually "8192 MiB" or "8.00 GiB")
            mem_mb = 0
            match = re.search(r"([\d.]+)\s*(MiB|GiB|MB|GB)", mem_str)
            if match:
                val = float(match.group(1))
                unit = match.group(2)
                if unit in ("GiB", "GB"):
                    mem_mb = val * 1024
                else:
                    mem_mb = val
            gpus.append(GPUInfo(name=name, vram_gb=mem_mb / 1024, driver=driver, backend="cuda"))
    return gpus


def detect_apple_gpus() -> list[GPUInfo]:
    """Detect Apple Silicon GPUs."""
    gpus = []
    if platform.system() != "Darwin":
        return gpus
    # Check if Apple Silicon
    arch = platform.machine()
    if arch not in ("arm64", "aarch64"):
        return gpus

    # Unified memory on Apple Silicon
    mem = run(["sysctl", "-n", "hw.memsize"])
    vram_gb = int(mem) / (1024 ** 3) if mem else 0.0

    # GPU name from system_profiler
    profiler = run(["system_profiler", "SPDisplaysDataType"])
    name = "Apple Silicon GPU"
    match = re.search(r"Chipset Model: (.+)", profiler)
    if match:
        name = match.group(1).strip()

    gpus.append(GPUInfo(name=name, vram_gb=vram_gb, driver="Metal", backend="mps"))
    return gpus


def detect_amd_gpus() -> list[GPUInfo]:
    """Detect AMD GPUs using rocm-smi."""
    gpus = []
    rocm = run(["rocm-smi", "--showproductname", "--showmeminfo", "vram"])
    if not rocm:
        return gpus
    # Simple parsing - rocm-smi output varies by version
    lines = rocm.split("\n")
    for line in lines:
        if "GPU" in line and ("MiB" in line or "GB" in line):
            parts = line.split()
            name = "AMD GPU"
            vram_gb = 0.0
            for i, part in enumerate(parts):
                if "MiB" in part:
                    try:
                        vram_gb = float(parts[i - 1]) / 1024
                    except (ValueError, IndexError):
                        pass
                elif "GB" in part:
                    try:
                        vram_gb = float(parts[i - 1])
                    except (ValueError, IndexError):
                        pass
            gpus.append(GPUInfo(name=name, vram_gb=vram_gb, driver="ROCm", backend="rocm"))
    return gpus


def detect_gpus() -> list[GPUInfo]:
    """Detect all GPUs."""
    all_gpus = []
    all_gpus.extend(detect_nvidia_gpus())
    all_gpus.extend(detect_apple_gpus())
    all_gpus.extend(detect_amd_gpus())
    return all_gpus


def detect_stacks() -> list[StackInfo]:
    """Detect installed model hosting stacks."""
    stacks = []

    checks = [
        ("ollama", ["ollama", "--version"]),
        ("vllm", ["python3", "-c", "import vllm; print(vllm.__version__)"]),
        ("llama.cpp", ["llama-server", "--version"]),
        ("llama.cpp", ["llama-cli", "--version"]),
        ("lm-studio", ["lm-studio", "--version"]),
        ("text-generation-inference", ["text-generation-launcher", "--version"]),
        ("ollama", ["docker", "ps", "--filter", "name=ollama", "--format", "{{.Names}}"]),
    ]

    for name, cmd in checks:
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                version = result.stdout.strip().split("\n")[0][:50]
                path = shutil.which(cmd[0]) or "docker"
                stacks.append(StackInfo(name=name, version=version, path=path))
        except Exception:
            pass

    # Deduplicate by name
    seen = set()
    unique = []
    for s in stacks:
        if s.name not in seen:
            seen.add(s.name)
            unique.append(s)
    return unique


def main() -> None:
    hw = HardwareInfo()
    hw.os_name, hw.os_version = detect_os()
    hw.cpu_name, hw.cpu_cores_physical, hw.cpu_cores_logical, hw.cpu_arch = detect_cpu()
    hw.ram_gb = detect_ram()
    hw.gpus = detect_gpus()

    stacks = detect_stacks()

    print("=" * 60)
    print("🖥️  System Hardware")
    print("=" * 60)
    print(f"OS:        {hw.os_name} {hw.os_version}".strip())
    print(f"CPU:       {hw.cpu_name}")
    print(f"Cores:     {hw.cpu_cores_physical} physical / {hw.cpu_cores_logical} logical")
    print(f"Arch:      {hw.cpu_arch}")
    print(f"RAM:       {hw.ram_gb:.1f} GB")

    if hw.gpus:
        print(f"\n🎮 GPUs ({len(hw.gpus)} detected):")
        for i, gpu in enumerate(hw.gpus, 1):
            print(f"  [{i}] {gpu.name}")
            print(f"      VRAM:   {gpu.vram_gb:.1f} GB")
            print(f"      Driver: {gpu.driver}")
            print(f"      Backend: {gpu.backend}")
    else:
        print("\n🎮 GPUs:    None detected (CPU-only inference)")

    print()
    print("=" * 60)
    print("📦 Installed Model Hosting Stacks")
    print("=" * 60)
    if stacks:
        for s in stacks:
            print(f"  • {s.name:20s} {s.version}")
    else:
        print("  None detected. Common stacks:")
        print("    • ollama        - https://ollama.com")
        print("    • llama.cpp     - https://github.com/ggml-org/llama.cpp")
        print("    • vLLM          - https://github.com/vllm-project/vllm")
        print("    • LM Studio     - https://lmstudio.ai")

    print()

    # Also output JSON for other scripts to consume
    output = {
        "hardware": hw.to_dict(),
        "stacks": [{"name": s.name, "version": s.version, "path": s.path} for s in stacks],
    }
    print("--- JSON ---")
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
