#!/usr/bin/env python3
"""Use only the hosted image's existing VoiceOver authorization. Never alter TCC/SIP."""
import json
import os
from pathlib import Path
import signal
import subprocess
import time

assert os.environ.get("GITHUB_ACTIONS") == "true"
assert os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted"
root = Path(os.environ["RUNNER_TEMP"]) / "vook-release-smoke"
assert (root / "results/app-verified.flag").is_file()
result = {"status": "unverified", "phrases": []}

def osa(statement):
    return subprocess.check_output(["osascript", "-e", statement], text=True,
                                   stderr=subprocess.STDOUT, timeout=10).strip()

try:
    assert Path("/private/var/db/Accessibility/.VoiceOverAppleScriptEnabled").is_file(), "Hosted image has not authorized VoiceOver scripting"
    enabled = subprocess.check_output(["defaults", "read", "com.apple.VoiceOver4/default", "SCREnableAppleScript"], text=True).strip()
    assert enabled == "1", "VoiceOver scripting is not enabled in this hosted profile"
    binary = str(root / "Vook4Me.app/Contents/MacOS/vook4me")
    for line in subprocess.check_output(["ps", "-axo", "pid,comm"], text=True).splitlines()[1:]:
        row = line.strip().split(None, 1)
        if len(row) == 2 and row[1] == binary:
            os.kill(int(row[0]), signal.SIGTERM)
    subprocess.run(["open", "-a", str(root / "Vook4Me.app")], check=True)
    time.sleep(2)
    subprocess.run(["open", "-a", str(root / "Vook4Me.app")], check=True)
    subprocess.run(["open", "-a", "/System/Library/CoreServices/VoiceOver.app"], check=True)
    time.sleep(3)
    osa('tell application "VoiceOver" to set enabled of caption window to true')
    subprocess.run(["open", "-a", str(root / "Vook4Me.app")], check=True)
    time.sleep(1)
    osa('tell application "VoiceOver" to tell vo cursor to move to first item')
    for index in range(24):
        if index in (0, 8):
            osa('tell application "VoiceOver" to tell vo cursor to move into item')
        else:
            osa('tell application "VoiceOver" to tell vo cursor to move right')
        time.sleep(0.3)
        phrase = osa('tell application "VoiceOver" to get content of last phrase')
        if phrase and phrase not in result["phrases"]:
            result["phrases"].append(phrase)
    combined = "\n".join(result["phrases"])
    names = ["All Bookmarks", "Memos", "Add bookmark or memo", "Change view", "Sort bookmarks", "Search"]
    result["recognizedControls"] = [name for name in names if name.lower() in combined.lower()]
    assert len(result["recognizedControls"]) >= 2, "Did not establish reading of two actual app controls"
    osa('tell application "VoiceOver" to open item chooser')
    time.sleep(1)
    result["itemChooserPhrase"] = osa('tell application "VoiceOver" to get content of last phrase')
    result["status"] = "passed"
except Exception as error:
    result["error"] = str(error)
finally:
    subprocess.run(["screencapture", "-x", str(root / "results/voiceover.png")], capture_output=True)
    try:
        osa('tell application "VoiceOver" to quit')
    except Exception:
        pass
    (root / "results/voiceover.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False))
raise SystemExit(0 if result["status"] == "passed" else 1)
