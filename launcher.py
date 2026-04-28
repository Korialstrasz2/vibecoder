import json
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent

TARGET_COMMANDS = {
    "assistant_small": [ROOT / "ASSISTANT_SMALL" / "start_server.bat"],
    "connectors_server": [ROOT / "FILES_FOR_CONNECTORS" / "server files" / "start_server_main_pc.bat"],
    "main_plus_opencode": [
        ROOT / "MAIN_DATA" / "start_server.bat",
        ROOT / "MAIN_DATA" / "start_opencode.bat",
    ],
}


def run_bat_file(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Missing file: {path}")
    subprocess.Popen(["cmd", "/c", "start", "", str(path)], shell=False)


class LauncherHandler(BaseHTTPRequestHandler):
    def _write_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.end_headers()

    def do_GET(self):
        if self.path == "/health":
            self._write_json(200, {"status": "ok"})
            return
        self._write_json(404, {"message": "Not found"})

    def do_POST(self):
        if self.path != "/start":
            self._write_json(404, {"message": "Not found"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            target = payload.get("target")

            if target not in TARGET_COMMANDS:
                self._write_json(400, {"message": f"Unknown target: {target}"})
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
