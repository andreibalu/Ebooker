#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${JAVA_HOME:?Set JAVA_HOME to your JDK21}"
: "${ANDROID_HOME:?Set ANDROID_HOME to your Android SDK}"
: "${ANDROID_SERIAL:?Select the dedicated Unpaged_E2E emulator explicitly}"
adb="$ANDROID_HOME/platform-tools/adb"
case "$ANDROID_SERIAL" in emulator-*) ;; *) echo 'Use a dedicated emulator, not a physical/user device.' >&2; exit 1;; esac
name="$("$adb" -s "$ANDROID_SERIAL" emu avd name | tr -d '\r' | head -1)"
case "$name" in Unpaged_E2E_*) ;; *) echo "Refusing unrelated AVD: $name" >&2; exit 1;; esac
# Other attached devices are allowed only when they are dedicated Unpaged_E2E emulators,
# so parallel worktrees can each drive their own instance. Gradle targets ANDROID_SERIAL.
for other in $("$adb" devices | awk 'NR>1 && $2=="device" { print $1 }'); do
  [[ "$other" == "$ANDROID_SERIAL" ]] && continue
  case "$other" in emulator-*) ;; *) echo "Refusing a run with non-emulator device $other attached." >&2; exit 1;; esac
  other_name="$("$adb" -s "$other" emu avd name | tr -d '\r' | head -1)"
  case "$other_name" in Unpaged_E2E_*) ;; *) echo "Refusing a run with unrelated AVD $other_name attached." >&2; exit 1;; esac
done
boot="$("$adb" -s "$ANDROID_SERIAL" shell getprop sys.boot_completed | tr -d '\r')"
[[ "$boot" == 1 ]] || { echo 'Wait for the emulator to finish booting.' >&2; exit 1; }
evidence="${E2E_EVIDENCE_DIR:-$(mktemp -d /private/tmp/unpaged-android-e2e.XXXXXX)}"
mkdir -p "$evidence/fixtures"
python3 tools/make-e2e-fixtures.py "$evidence/fixtures"
"$adb" -s "$ANDROID_SERIAL" push "$evidence/fixtures/." /sdcard/Download/Unpaged_E2E/ > "$evidence/fixture-push.log"
# Remove only this test driver's previous capture directory; preserve the provider originals.
"$adb" -s "$ANDROID_SERIAL" shell rm -rf /sdcard/Download/Unpaged_E2E_Captures
collect() {
  result=$?
  if [[ -n "${abs_server_pid:-}" ]]; then kill "$abs_server_pid" 2>/dev/null || true; wait "$abs_server_pid" 2>/dev/null || true; fi
  [[ "$result" == 0 ]] || tail -80 "$evidence/gradle.log" >&2
  "$adb" -s "$ANDROID_SERIAL" pull /sdcard/Download/Unpaged_E2E_Captures "$evidence/screenshots" > "$evidence/capture-pull.log" 2>&1 || true
  "$adb" -s "$ANDROID_SERIAL" logcat -d -v threadtime > "$evidence/logcat.txt" 2>&1 || true
  [[ ! -d app/build/test-results/testDebugUnitTest ]] || cp -R app/build/test-results/testDebugUnitTest "$evidence/host-test-results"
  [[ ! -d app/build/reports/tests/testDebugUnitTest ]] || cp -R app/build/reports/tests/testDebugUnitTest "$evidence/host-test-report"
  [[ ! -f app/build/reports/lint-results-debug.xml ]] || cp app/build/reports/lint-results-debug.xml "$evidence/"
  [[ ! -d e2e/build/outputs/androidTest-results ]] || cp -R e2e/build/outputs/androidTest-results "$evidence/"
  [[ ! -d e2e/build/reports/androidTests ]] || cp -R e2e/build/reports/androidTests "$evidence/"
  echo "Android E2E evidence: $evidence"
  exit "$result"
}
trap collect EXIT
# Each run gets its own host port; the device always reaches it as 127.0.0.1:13378.
abs_port="${E2E_ABS_PORT:-$((13400 + ${ANDROID_SERIAL#emulator-} % 1000))}"
"$adb" -s "$ANDROID_SERIAL" reverse tcp:13378 "tcp:$abs_port" > /dev/null
python3 tools/fake-abs-server.py --port "$abs_port" --fixtures "$evidence/fixtures" --evidence "$evidence" > "$evidence/abs-server.log" 2>&1 &
abs_server_pid=$!
python3 - "$abs_port" <<'READY'
import sys
import time
port = sys.argv[1]
import urllib.request
for attempt in range(50):
    try:
        urllib.request.urlopen(f'http://127.0.0.1:{port}/_test/health', timeout=1).close()
        break
    except OSError:
        time.sleep(.1)
else:
    raise SystemExit('Fake ABS server did not become ready')
READY
kill -0 "$abs_server_pid" # Refuse accidentally using a server left by another run.
./gradlew --no-daemon :app:assembleDebug :app:lintDebug :app:testDebugUnitTest :e2e:connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.e2eApproved=true "$@" > "$evidence/gradle.log" 2>&1
cat "$evidence/gradle.log"
# AGP's connected-device provider honors ANDROID_SERIAL. Fail loudly if a future
# plugin version ever fans the suite out to another attached emulator.
targets="$(grep -oE 'Starting [0-9]+ tests on [A-Za-z0-9_.-]+' "$evidence/gradle.log" | awk '{print $5}' | sort -u)"
[[ -z "$targets" || "$targets" == "$name" ]] || {
  echo "E2E ran on unexpected devices: $targets (expected only $name)" >&2; exit 1;
}
