@echo off

REM Extract the tarball. Tar doesn't support wildcards on windows, DIR only supports one wildcard, so we have to do this mess:
cd distributables\v*\
set GET_TAR="dir /b httptoolkit-server-*-win32-x64.tar.gz"
FOR /F "tokens=*" %%i IN (' %GET_TAR% ') DO SET TAR_PATH=%%i

tar -xvzf %TAR_PATH%

echo:
echo:
echo Starting server...

START "server" /b .\httptoolkit-server\bin\httptoolkit-server start

REM The closest we can get to a 10 second delay on Windows in CI, ick:
ping -n 10 127.0.0.1 >NUL

echo:
echo:
echo Testing server...

REM --silent (no progress), --fail on errors, --include headers in logs
set CURL_OPTIONS="-sfi"
REM CSRF protection fully blocks unrecognized/missing origin requests:
set WITH_ORIGIN="-HOrigin: https://techtanic-htk.github.io"
set AS_JSON="-HContent-Type: application/json"

echo:
echo:
echo Can start a Mockttp server?
REM Uses the default config from the UI:
curl %CURL_OPTIONS% %WITH_ORIGIN% %AS_JSON% -X POST "http://127.0.0.1:45456/start" ^
  --data "{\"plugins\":{\"http\":{\"options\":{\"cors\":false,\"suggestChanges\":false,\"http2\":\"fallback\",\"https\":{\"tlsPassthrough\":[]}}},\"webrtc\":{}}}" ^
  || goto :error`

echo:
echo:
echo Can query the API server version?
curl %CURL_OPTIONS% %WITH_ORIGIN% %AS_JSON% http://127.0.0.1:45457/ -d "{\"query\": \"query getVersion { version }\"}" || goto :error

echo:
echo:
echo Can get config?
curl %CURL_OPTIONS% %WITH_ORIGIN% %AS_JSON% http://127.0.0.1:45457/ -d "{\"query\": \"query getConfig { config { certificateContent certificatePath certificateFingerprint } }\"}" || goto :error

echo:
echo:
echo Can query interceptors?
curl %CURL_OPTIONS% %WITH_ORIGIN% %AS_JSON% http://127.0.0.1:45457/ -d "{\"query\": \"query getInterceptors { interceptors { id version, metadata isActivable isActive(proxyPort: 8000) } }\"}" || goto :error

echo:
echo:
echo Can trigger update?
REM (can't test that it actually updates, unfortunately)
curl %CURL_OPTIONS% %WITH_ORIGIN% %AS_JSON% http://127.0.0.1:45457/ -d "{\"query\": \"mutation TriggerUpdate { triggerUpdate }\"}" || goto :error

REM ^ This will fail if they receive anything but a 200 result.
REM This ensures that the server is startable, and has minimal functionality for launch.

goto :success

:error
set err=%errorlevel%

taskkill /FI "WindowTitle eq server*" /T /F
echo Test failed with error #%err%.
exit /b %err%

:success
echo All good.

REM Shut down by matching title passed to START to run in the background
taskkill /FI "WindowTitle eq server*" /T /F || goto :success