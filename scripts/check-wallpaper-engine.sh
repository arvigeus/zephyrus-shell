#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
engine_test_root=$(mktemp -d)
trap 'rm -rf -- "$engine_test_root"' EXIT
export ENGINE_FIXTURE_ROOT="$engine_test_root"
export XDG_CONFIG_HOME="$engine_test_root/config" XDG_DATA_HOME="$engine_test_root/data" XDG_CACHE_HOME="$engine_test_root/cache" XDG_RUNTIME_DIR="$engine_test_root/runtime"
export WALLPIPER_STEAM_ROOT="$engine_test_root/Steam" HYPRLAND_INSTANCE_SIGNATURE=fixture
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9
unset ALL_PROXY all_proxy NO_PROXY no_proxy WAYLAND_DISPLAY
mkdir -p "$engine_test_root/bin" "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME/zephyrus-shell" "$XDG_DATA_HOME/zephyrus-shell/wallpapers" "$WALLPIPER_STEAM_ROOT/steamapps/workshop/content/431960/123456"
cp tests/fixtures/wallpaper-engine.py "$engine_test_root/bin/fixture"
chmod +x "$engine_test_root/bin/fixture"
for engine_test_tool in wallpiperd wallpiperctl hyprctl steam engine-fixture-control; do
    ln -s fixture "$engine_test_root/bin/$engine_test_tool"
done
export PATH="$engine_test_root/bin:$PATH"
python3 - <<'PY'
import json,os,struct,zlib
from pathlib import Path
def chunk(kind,data):
    return struct.pack('!I',len(data))+kind+data+struct.pack('!I',zlib.crc32(kind+data))
image=(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',1,1,8,2,0,0,0))
       +chunk(b'IDAT',zlib.compress(b'\x00\x45\x67\x89'))+chunk(b'IEND',b''))
folder=Path(os.environ['WALLPIPER_STEAM_ROOT'])/'steamapps/workshop/content/431960/123456'
(folder/'project.json').write_text(json.dumps({'title':'Clouds','type':'scene','file':'scene.json','preview':'preview.png'}))
(folder/'preview.png').write_bytes(image)
engine=Path(os.environ['WALLPIPER_STEAM_ROOT'])/'steamapps/common/wallpaper_engine/wallpaper64.exe'
engine.parent.mkdir(parents=True)
engine.write_bytes(b'fixture')
engine.with_name('config.json').write_text(json.dumps({'steamuser':{'general':{'user':{'playbacksleep':'stop','fps':15}}}}))
proton=Path(os.environ['WALLPIPER_STEAM_ROOT'])/'steamapps/common/Proton Fixture/proton'
proton.parent.mkdir(parents=True)
proton.write_bytes(b'fixture')
proton.chmod(0o755)
(Path(os.environ['ENGINE_FIXTURE_ROOT'])/'full-preview.png').write_bytes(
    b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',1024,512,8,2,0,0,0))
    +chunk(b'IDAT',zlib.compress((b'\x00'+b'\x45\x67\x89'*1024)*512))+chunk(b'IEND',b''))
(Path(os.environ['XDG_DATA_HOME'])/'zephyrus-shell/wallpapers/wallhaven-fixture.png').write_bytes(image)
PY
for engine_test_phase in apply restore static-recovery; do
export ENGINE_TEST_PHASE="$engine_test_phase"
if [[ "$engine_test_phase" == restore ]]; then
    python3 - <<'PY'
import json,os
from pathlib import Path
setting=Path(os.environ['XDG_CONFIG_HOME'])/'zephyrus-shell/wallpaper.json'
setting.write_text(json.dumps({'mode':'wallpaper_engine','workshop_id':'123456','selection':'restore'}))
(Path(os.environ['ENGINE_FIXTURE_ROOT'])/'commands.jsonl').unlink()
PY
fi
if [[ "$engine_test_phase" == static-recovery ]]; then
    python3 - <<'PY'
import json,os,select,subprocess,sys,time
from pathlib import Path
from pictures import wallpaper_engine as engine
setting=engine.config_dir()/'wallpaper.json'
setting.write_text(json.dumps({'mode':'wallpaper_engine','workshop_id':'123456','selection':'crash'}))
(Path(os.environ['ENGINE_FIXTURE_ROOT'])/'commands.jsonl').unlink()
worker=subprocess.Popen([sys.executable,'-u','pictures/wallpaper_engine.py'],
                        stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
try:
    deadline=time.monotonic()+10
    while time.monotonic()<deadline:
        worker.stdin.write(json.dumps({'id':1,'op':'sync','monitors':[{'name':'TEST','id':0}],'clients':[]})+'\n')
        worker.stdin.flush()
        assert select.select([worker.stdout],[],[],5)[0], 'seed worker did not answer'
        response=json.loads(worker.stdout.readline())
        if response.get('result',{}).get('screens')==['TEST']: break
        time.sleep(.05)
    assert response.get('result',{}).get('screens')==['TEST'], response
finally:
    worker.kill();worker.wait(timeout=3)
    for stream in (worker.stdin,worker.stdout,worker.stderr): stream.close()
setting.write_text(json.dumps({'provider':'wallhaven','image':(
    Path(os.environ['XDG_DATA_HOME'])/'zephyrus-shell/wallpapers/wallhaven-fixture.png').as_uri()}))
PY
fi
timeout 35s dbus-run-session quickshell -p "$PWD/wallpaper-engine-smoke.qml" --no-color > "$engine_test_root/log" 2>&1 || { cat "$engine_test_root/log"; exit 1; }
cat "$engine_test_root/log"
rg -q 'ENGINE PASS' "$engine_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ENGINE FAIL|Error decoding' "$engine_test_root/log"; then exit 1; fi
python3 - <<'PY'
import json,os,time
from pathlib import Path
from pictures.wallpaper_engine import process_identity,read_state,runtime_alive
root=Path(os.environ['ENGINE_FIXTURE_ROOT'])
deadline=time.monotonic()+5
while runtime_alive(read_state()) and time.monotonic()<deadline: time.sleep(.05)
assert not runtime_alive(read_state()), 'Wallpaper controller survived worker unload'
pids=[pid for line in (root/'all-pids.jsonl').read_text().splitlines() for pid in json.loads(line)]
assert not any(process_identity(pid) for pid in pids), 'Wallpaper processes survived static selection'
assert read_state()['status']=='idle'
assert not (Path(os.environ['XDG_CONFIG_HOME'])/'zephyrus-shell/.engine-ownership.json').exists()
assert not (Path(os.environ['XDG_CONFIG_HOME'])/'zephyrus-shell/.engine-native-playback.json').exists()
native_config=Path(os.environ['WALLPIPER_STEAM_ROOT'])/'steamapps/common/wallpaper_engine/config.json'
assert json.loads(native_config.read_text())['steamuser']['general']['user']=={'playbacksleep':'stop','fps':15}
for line in (root/'native-starts.jsonl').read_text().splitlines():
    assert json.loads(line)=={'playbacksleep':'run','playbackfullscreen':'run','playbackmaximized':'run','fps':15}, line
commands=[json.loads(line)['command'] for line in (root/'commands.jsonl').read_text().splitlines()]
expected=['mute','play','mute']
if os.environ['ENGINE_TEST_PHASE']=='apply': expected=['mute','set','play','mute']+expected+['pause','play']
assert commands==expected, commands
steam_args=json.loads((root/'steam.json').read_text())
assert steam_args==['steam://openurl/https://steamcommunity.com/sharedfiles/filedetails/?id=123456'], steam_args
print('ENGINE PROCESS PASS: daemon and detached helper stopped; commands only on transitions')
PY
done
