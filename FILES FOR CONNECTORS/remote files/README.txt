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
- if opencode is missing, installs local portable dependencies with no admin:
  - downloads portable Node.js into remote files\tools\node
  - installs opencode-ai into remote files\tools\npm-global
- checks API endpoint reachability

What start_opencode.bat does
----------------------------
- if server is unreachable, prompts for MAIN PC IP again and retries
- updates config baseURL automatically with your new IP
- uses local portable opencode if global one is unavailable
