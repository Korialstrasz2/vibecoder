WORK LAPTOP QUICK START
=======================

1) Copy this entire "remote files" folder to your work laptop.
2) Run install.bat once.
3) Run start_opencode.bat whenever you want to work.

Daily use flow
--------------
A) On MAIN PC: start_server_main_pc.bat
B) On WORK LAPTOP: start_opencode.bat

What install.bat does
---------------------
- asks for your MAIN PC LAN IP
- writes config/opencode/opencode.jsonc with that API base URL
- installs that config to:
  - %USERPROFILE%\.config\opencode\opencode.jsonc
  - %APPDATA%\opencode\opencode.jsonc
- installs opencode-ai globally via npm if missing
- checks API endpoint reachability
