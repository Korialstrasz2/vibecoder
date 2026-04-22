@echo off
setlocal
echo Checking llama-server health...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-RestMethod http://127.0.0.1:8080/v1/models | ConvertTo-Json -Depth 5 } catch { Write-Host '[ERROR] Could not reach http://127.0.0.1:8080/v1/models'; Write-Host $_; exit 1 }"
pause
endlocal
