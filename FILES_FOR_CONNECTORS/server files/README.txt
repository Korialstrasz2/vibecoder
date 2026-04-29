MAIN PC (SERVER) QUICK START
============================

1) Keep this folder inside the repo at FILES_FOR_CONNECTORS\server files\
2) (Optional) Copy local_settings_template.bat to MAIN_DATA\ as local_settings.bat.
3) Run: start_server_main_pc.bat
4) Keep the terminal open while using OpenCode from your work laptop.

Expected API endpoint format:
  http://<MAIN_PC_LAN_IP>:8076/v1

Health check from another machine:
  http://<MAIN_PC_LAN_IP>:8076/v1/models
