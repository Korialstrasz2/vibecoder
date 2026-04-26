# OpenCode LAN Setup (Main PC server + Work PC client)

This folder contains helper scripts to run OpenCode server on one machine and attach from another machine on the same local network.

## Why files must be accessible from the server machine

When you run `opencode serve` on the **main PC**, that machine becomes the backend execution environment.

That means:
- File reads/writes happen on the main PC's filesystem.
- Commands and tools run from the main PC working directory.
- If your repo exists only on the work laptop, the main PC cannot directly edit it unless you make it visible there.

So for "work files on laptop, compute on main PC", you need one of these:
1. **Shared folder** (SMB) from work laptop to main PC.
2. **Synced copy** of the repo on both machines (Git, Syncthing, etc.).
3. **Mounted network drive** on main PC that points to work-laptop files.

## Files in this folder

- `start_server_api_external.bat` → run on the main PC.
- `install_work_pc_prereqs.bat` → optional installer for work PC prerequisites.
- `connect_work_pc_to_api_server.bat` → run on work PC to attach to the main PC server.

## Step-by-step setup

## 1) Main PC (powerful PC)

1. Open `start_server_api_external.bat` and edit:
   - `OPENCODE_PASSWORD`
   - `OPENCODE_PROJECT_DIR`
   - (optional) port
2. Ensure firewall allows inbound TCP on chosen port (default `4096`).
3. Run the bat file.

Expected server bind:
- Host: `0.0.0.0`
- Port: `4096` (or your custom value)

## 2) Work PC

1. Run `install_work_pc_prereqs.bat` once (if needed).
2. Open `connect_work_pc_to_api_server.bat` and set:
   - `SERVER_IP` to main PC LAN IP (for example `192.168.1.50`)
   - `SERVER_PORT`
   - `OPENCODE_PASSWORD` (same as main PC)
3. Run `connect_work_pc_to_api_server.bat`.

## 3) Verify connectivity

From work PC terminal:

```bat
opencode attach http://MAIN_PC_IP:4096
```

If it fails:
- Check main PC firewall.
- Confirm both devices are on same subnet/VPN.
- Confirm server is running and password matches.

## Security notes

- Keep this on trusted LAN only.
- Use a strong `OPENCODE_SERVER_PASSWORD`.
- Do not expose this port publicly on the internet without proper hardening.

