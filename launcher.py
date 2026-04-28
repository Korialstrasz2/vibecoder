import json
import re
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent
MAIN_DATA_DIR = ROOT / "MAIN_DATA"
MAIN_MODELS_DIR = MAIN_DATA_DIR / "models"
PROFILE_DIR = MAIN_DATA_DIR / "startup_bat_profiles"

TARGET_COMMANDS = {
    "assistant_small": [ROOT / "ASSISTANT_SMALL" / "start_server.bat"],
    "connectors_server": [ROOT / "FILES_FOR_CONNECTORS" / "server files" / "start_server_main_pc.bat"],
    "main_plus_opencode": [
        MAIN_DATA_DIR / "start_server.bat",
        MAIN_DATA_DIR / "start_opencode.bat",
    ],
}

DENSE_RE = re.compile(r"(?i)(?<!x)(\d{1,3}b)")
MOE_RE = re.compile(r"(?i)([ae])(\d{1,3})x(\d{1,3})b")
ARCH_PATTERNS = [
    "qwen", "llama", "mistral", "mixtral", "deepseek", "gemma", "phi", "yi", "command-r", "gpt-oss",
]


def run_bat_file(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Missing file: {path}")
    subprocess.Popen(
        ["cmd", "/c", "start", "", str(path)],
        shell=False,
        cwd=str(path.parent),
    )


def _format_gb(size_bytes: int) -> float:
    return round(size_bytes / (1024 ** 3), 2)


def detect_gpus() -> list[dict]:
    try:
        command = [
            "nvidia-smi",
            "--query-gpu=index,name,memory.total",
            "--format=csv,noheader,nounits",
        ]
        res = subprocess.run(command, capture_output=True, text=True, check=True)
        gpus = []
        for line in res.stdout.splitlines():
            parts = [p.strip() for p in line.split(",")]
            if len(parts) != 3:
                continue
            idx, name, mem_mb = parts
            mem_gb = round(float(mem_mb) / 1024.0, 2)
            gpus.append({"index": idx, "name": name, "vram_gb": mem_gb})
        return gpus
    except Exception:
        return []


def infer_architecture(filename_lower: str) -> str:
    for pattern in ARCH_PATTERNS:
        if pattern in filename_lower:
            return pattern
    return "unknown"


def parse_param_tag(filename: str) -> dict:
    lower = filename.lower()
    moe_match = MOE_RE.search(lower)
    if moe_match:
        family, experts_raw, active_raw = moe_match.groups()
        experts = int(experts_raw)
        active = int(active_raw)
        return {
            "param_tag": f"{family.upper()}{experts}x{active}B",
            "model_type": "moe",
            "active_params_b": active,
            "total_params_b": experts * active,
        }

    dense_match = DENSE_RE.search(lower)
    if dense_match:
        tag = dense_match.group(1).upper()
        count = int(re.sub(r"(?i)b", "", tag))
        return {
            "param_tag": tag,
            "model_type": "dense",
            "active_params_b": count,
            "total_params_b": count,
        }

    return {
        "param_tag": "unknown",
        "model_type": "unknown",
        "active_params_b": None,
        "total_params_b": None,
    }


def scan_models() -> list[dict]:
    if not MAIN_MODELS_DIR.exists():
        return []

    models = []
    for model_path in sorted(MAIN_MODELS_DIR.rglob("*.gguf")):
        if "mmproj" in model_path.name.lower():
            continue
        stats = model_path.stat()
        rel = model_path.relative_to(ROOT).as_posix()
        param_info = parse_param_tag(model_path.name)
        models.append(
            {
                "name": model_path.name,
                "path": rel,
                "size_gb": _format_gb(stats.st_size),
                "architecture": infer_architecture(model_path.name.lower()),
                **param_info,
            }
        )
    return models


def choose_default_gpu(gpus: list[dict]) -> tuple[str, str | None]:
    if not gpus:
        return "all", None
    for gpu in gpus:
        if "4070" in gpu["name"].lower():
            return "single", gpu["index"]
    return "single", gpus[0]["index"]


def choose_default_model(models: list[dict]) -> str | None:
    if not models:
        return None
    for model in models:
        if model["param_tag"].lower() == "a3x3b" or "a3b" in model["name"].lower():
            return model["path"]
    return models[0]["path"]


def build_main_options() -> dict:
    gpus = detect_gpus()
    models = scan_models()
    gpu_mode, gpu_index = choose_default_gpu(gpus)
    return {
        "gpus": gpus,
        "models": models,
        "contexts": [16384, 32768, 65536, 131072],
        "defaults": {
            "context": 65536,
            "gpu_mode": gpu_mode,
            "gpu_index": gpu_index,
            "model_path": choose_default_model(models),
        },
    }


def build_profile_script(profile: dict) -> Path:
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)

    model_path = Path(profile["model_path"])
    model_abs = (ROOT / model_path).resolve()
    if not model_abs.exists():
        raise FileNotFoundError(f"Selected model does not exist: {model_abs}")

    context = int(profile.get("context", 65536))
    gpu_mode = profile.get("gpu_mode", "all")
    gpu_index = profile.get("gpu_index")

    slug_base = re.sub(r"[^a-zA-Z0-9_-]", "_", model_abs.stem)[:40]
    slug = f"{slug_base}_{context}_{gpu_mode}_{gpu_index or 'all'}"
    script_path = PROFILE_DIR / f"start_profile_{slug}.bat"

    lines = [
        "@echo off",
        "setlocal",
        "cd /d \"%~dp0..\"",
        f"set \"MODEL_FILE={model_abs}\"",
        f"set \"LLAMA_CTX={context}\"",
        "set \"CONTEXT_PROFILE=ui-profile\"",
    ]

    if gpu_mode == "cpu":
        lines.extend([
            "set \"LLAMA_GPU_LAYERS=0\"",
            "set \"CUDA_VISIBLE_DEVICES=\"",
            "set \"GGML_CUDA_DEVICE=\"",
        ])
    elif gpu_mode == "single" and gpu_index is not None:
        lines.extend([
            "set \"LLAMA_GPU_LAYERS=999\"",
            f"set \"CUDA_VISIBLE_DEVICES={gpu_index}\"",
            f"set \"GGML_CUDA_DEVICE={gpu_index}\"",
        ])
    else:
        lines.extend([
            "set \"LLAMA_GPU_LAYERS=999\"",
            "set \"CUDA_VISIBLE_DEVICES=\"",
            "set \"GGML_CUDA_DEVICE=\"",
        ])

    lines.append('call "..\\start_server.bat"')

    script_path.write_text("\r\n".join(lines) + "\r\n", encoding="utf-8")
    return script_path


def build_target_status() -> dict:
    status = {}
    for target, commands in TARGET_COMMANDS.items():
        missing = [str(command) for command in commands if not command.exists()]
        status[target] = {
            "ready": len(missing) == 0,
            "missing": missing,
            "commands": [str(command) for command in commands],
        }
    return status


class LauncherHandler(BaseHTTPRequestHandler):
    def _write_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _write_text(self, status: int, body: str, content_type: str) -> None:
        body_bytes = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body_bytes)))
        self.end_headers()
        self.wfile.write(body_bytes)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        clean_path = parsed.path

        if clean_path == "/health":
            self._write_json(200, {"status": "ok"})
            return

        if clean_path == "/targets":
            self._write_json(200, {"targets": build_target_status()})
            return

        if clean_path == "/main/options":
            self._write_json(200, build_main_options())
            return

        if clean_path in {"/", "/entrance.html"}:
            html = (ROOT / "entrance.html").read_text(encoding="utf-8")
            self._write_text(200, html, "text/html; charset=utf-8")
            return

        if clean_path == "/entrance.js":
            js = (ROOT / "entrance.js").read_text(encoding="utf-8")
            self._write_text(200, js, "application/javascript; charset=utf-8")
            return

        self._write_json(404, {"message": "Not found"})

    def do_POST(self):
        parsed = urlparse(self.path)
        clean_path = parsed.path

        if clean_path != "/start":
            self._write_json(404, {"message": "Not found"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            target = payload.get("target")

            if target not in TARGET_COMMANDS:
                self._write_json(400, {"message": f"Unknown target: {target}"})
                return

            target_status = build_target_status()[target]
            if not target_status["ready"]:
                self._write_json(
                    400,
                    {
                        "message": f"Cannot start {target}. Missing files found.",
                        "missing": target_status["missing"],
                    },
                )
                return

            if target == "main_plus_opencode" and payload.get("profile"):
                script = build_profile_script(payload["profile"])
                run_bat_file(script)
                run_bat_file(MAIN_DATA_DIR / "start_opencode.bat")
                self._write_json(200, {"message": f"Started main profile: {script.name}"})
                return

            for command in TARGET_COMMANDS[target]:
                run_bat_file(command)

            self._write_json(200, {"message": f"Started: {target}"})
        except Exception as exc:  # noqa: BLE001
            self._write_json(500, {"message": str(exc)})


def main() -> None:
    server = HTTPServer(("127.0.0.1", 8765), LauncherHandler)
    print("Launcher running at http://127.0.0.1:8765")
    server.serve_forever()


if __name__ == "__main__":
    main()
