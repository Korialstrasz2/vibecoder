"""
GPU picker helper for llama.cpp launcher.

Purpose:
- Prefer the NVIDIA RTX 4070 / RTX 4070 Laptop GPU when requested.
- Avoid relying on PyTorch for GPU detection. PyTorch can be CPU-only even when
  llama.cpp can use CUDA, which gives false "No CUDA GPUs detected" failures.
- Writes the selected CUDA/nvidia-smi device index to gpu_choice.tmp by default.

Recommended launcher behavior:
- CPU mode: set CUDA_VISIBLE_DEVICES=-1 and --n-gpu-layers 0.
- RTX 4070 mode: set CUDA_DEVICE_ORDER=PCI_BUS_ID and CUDA_VISIBLE_DEVICES=<index>.
- All GPUs mode: unset CUDA_VISIBLE_DEVICES and use GPU layers.
"""
from __future__ import annotations

import argparse
import csv
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class GpuInfo:
    index: int
    name: str
    uuid: str | None = None
    memory_mib: int | None = None
    pci_bus_id: str | None = None
    source: str = "unknown"


def parse_memory_mib(raw: str) -> int | None:
    match = re.search(r"(\d+)", raw.strip())
    return int(match.group(1)) if match else None


def query_with_nvidia_smi() -> list[GpuInfo]:
    if shutil.which("nvidia-smi") is None:
        return []

    cmd = [
        "nvidia-smi",
        "--query-gpu=index,uuid,name,memory.total,pci.bus_id",
        "--format=csv,noheader,nounits",
    ]
    try:
        proc = subprocess.run(
            cmd,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except Exception as exc:
        print(f"[WARN] nvidia-smi query failed: {exc}")
        return []

    gpus: list[GpuInfo] = []
    for row in csv.reader(proc.stdout.splitlines()):
        if len(row) < 2:
            continue
        try:
            index = int(row[0].strip())
        except ValueError:
            continue
        uuid = row[1].strip()
        name = row[2].strip() if len(row) >= 3 else "Unknown NVIDIA GPU"
        memory_mib = parse_memory_mib(row[3]) if len(row) >= 4 else None
        pci_bus_id = row[4].strip() if len(row) >= 5 else None
        gpus.append(GpuInfo(index=index, name=name, uuid=uuid, memory_mib=memory_mib, pci_bus_id=pci_bus_id, source="nvidia-smi"))
    return gpus


def query_with_torch() -> list[GpuInfo]:
    """Fallback only. PyTorch may not match llama.cpp CUDA visibility."""
    try:
        import torch  # type: ignore
    except Exception as exc:
        print(f"[WARN] PyTorch fallback unavailable: {exc}")
        return []

    try:
        count = torch.cuda.device_count()
    except Exception as exc:
        print(f"[WARN] PyTorch CUDA query failed: {exc}")
        return []

    gpus: list[GpuInfo] = []
    for i in range(count):
        try:
            props = torch.cuda.get_device_properties(i)
            memory_mib = round(props.total_memory / 1024**2)
            gpus.append(GpuInfo(index=i, name=props.name, memory_mib=memory_mib, source="torch"))
        except Exception as exc:
            print(f"[WARN] Could not read PyTorch CUDA device {i}: {exc}")
    return gpus


def is_rtx_4070(name: str) -> bool:
    return re.search(r"\bRTX\s+4070\b", name, flags=re.IGNORECASE) is not None


def choose_4070(gpus: list[GpuInfo]) -> GpuInfo | None:
    candidates = [gpu for gpu in gpus if is_rtx_4070(gpu.name)]
    if not candidates:
        return None
    candidates.sort(key=lambda gpu: ("laptop" not in gpu.name.lower(), gpu.index))
    return candidates[0]


def format_memory(memory_mib: int | None) -> str:
    if memory_mib is None:
        return "unknown VRAM"
    return f"{memory_mib / 1024:.1f} GB VRAM"


def print_gpus(gpus: list[GpuInfo]) -> None:
    print()
    print("  Available NVIDIA/CUDA GPUs:")
    print()
    for gpu in gpus:
        pci = f", PCI {gpu.pci_bus_id}" if gpu.pci_bus_id else ""
        uuid = f", UUID {gpu.uuid}" if gpu.uuid else ""
        print(f"  [{gpu.index}]  {gpu.name}  ({format_memory(gpu.memory_mib)}{pci}{uuid}; via {gpu.source})")
    print()


def cuda_visible_selector(gpu: GpuInfo) -> str:
    # CUDA_VISIBLE_DEVICES accepts GPU UUIDs. Prefer UUIDs because ordinals can change.
    return gpu.uuid or str(gpu.index)


def write_choice(path: Path, gpu: GpuInfo) -> None:
    path.write_text(cuda_visible_selector(gpu), encoding="ascii")


def main() -> int:
    parser = argparse.ArgumentParser(description="Pick the RTX 4070 CUDA device for llama.cpp.")
    parser.add_argument("--prefer", default="4070", choices=["4070"], help="GPU preference to select.")
    parser.add_argument(
        "--choice-file",
        default=str(Path(__file__).with_name("gpu_choice.tmp")),
        help="File where the selected device index will be written.",
    )
    args = parser.parse_args()

    choice_file = Path(args.choice_file)
    try:
        if choice_file.exists():
            choice_file.unlink()
    except OSError:
        pass

    gpus = query_with_nvidia_smi()
    if not gpus:
        print("[WARN] nvidia-smi did not return GPUs. Trying PyTorch fallback.")
        gpus = query_with_torch()

    if not gpus:
        print("[ERROR] No NVIDIA/CUDA GPUs detected by picker.")
        return 1

    print_gpus(gpus)

    selected = choose_4070(gpus)
    if selected is None:
        print("[ERROR] No RTX 4070 GPU found. Refusing to fall back to another GPU.")
        print("[ERROR] This avoids accidentally using the RTX 3090/eGPU.")
        return 2

    selector = cuda_visible_selector(selected)
    write_choice(choice_file, selected)
    print(f"  RTX 4070 selected: CUDA_VISIBLE_DEVICES={selector} ({selected.name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
