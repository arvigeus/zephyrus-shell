#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
offline
export PICTURE_FIXTURE_ROOT="$SMOKE_ROOT" XDG_RUNTIME_DIR="$SMOKE_ROOT/runtime" HYPRLAND_INSTANCE_SIGNATURE=fixture
mkdir -p "$SMOKE_ROOT/bin" "$XDG_RUNTIME_DIR" "$XDG_DATA_HOME/zephyrus-shell/wallpapers"
cp tests/fixtures/picture-provider.py "$SMOKE_ROOT/bin/fixture"
chmod +x "$SMOKE_ROOT/bin/fixture"
for picture_tool in mpvpaper hyprctl picture-fixture-server; do ln -s fixture "$SMOKE_ROOT/bin/$picture_tool"; done
export PATH="$SMOKE_ROOT/bin:$PATH"
ffmpeg -nostdin -v error -f lavfi -i color=c=blue:s=64x64:d=2 -c:v libx264 -pix_fmt yuv420p "$SMOKE_ROOT/video.mp4"
start_fixture server picture-fixture-server
python3 - <<'PY'
import json,os,struct,time,zlib
from pathlib import Path
root=Path(os.environ['PICTURE_FIXTURE_ROOT'])
def chunk(kind,data): return struct.pack('!I',len(data))+kind+data+struct.pack('!I',zlib.crc32(kind+data))
image=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',1,1,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b'\x00\x45\x67\x89'))+chunk(b'IEND',b'')
(root/'poster.png').write_bytes(image)
(Path(os.environ['XDG_DATA_HOME'])/'zephyrus-shell/wallpapers/wallhaven-fixture.png').write_bytes(image)
package=root/'plugin with spaces'; package.mkdir()
(package/'manifest.json').write_text(json.dumps({'api_version':1,'command':['python3',str(Path('tests/fixtures/picture-provider.py').resolve())]}))
(Path(os.environ['XDG_CONFIG_HOME'])/'zephyrus-shell/pictures.json').write_text(json.dumps({'providers':[{'id':'fixture','name':'Fixture provider','plugin':str(package)}]}))
deadline=time.monotonic()+5
while not (root/'server.port').exists():
    assert time.monotonic()<deadline, 'Server did not start'
    time.sleep(.05)
PY
for picture_phase in apply restore; do
    export PICTURE_TEST_PHASE="$picture_phase"
    run_smoke picture-providers "PROVIDER" 30s "Error decoding"
    python3 - <<'PY'
import json,os,time
from pathlib import Path
from modules.pictures import wallpaper_engine as engine
root=Path(os.environ['PICTURE_FIXTURE_ROOT'])
deadline=time.monotonic()+5
while engine.runtime_alive(engine.read_state()) and time.monotonic()<deadline: time.sleep(.05)
assert not engine.runtime_alive(engine.read_state()), 'Runtime survived shell shutdown'
players=[json.loads(line) for line in (root/'players.jsonl').read_text().splitlines()]
assert not any(engine.process_identity(p['pid']) for p in players), 'Video player survived shutdown'
assert all(p['argv'][-2]=='ALL' and 'audio=no' in p['argv'][p['argv'].index('-o')+1] for p in players)
requests=[json.loads(line) for line in (root/'provider-requests.jsonl').read_text().splitlines()]
assert len([r for r in requests if r['op']=='resolve'])==1, 'Resolution must happen only on Apply, and use cache after restore'
if os.environ['PICTURE_TEST_PHASE']=='apply':
    assert (root/'pause.jsonl').read_text().splitlines()==['true','false']
    assert engine.read_setting()['mode']=='video'
else:
    assert 'mode' not in engine.read_setting()
assert (engine.config_dir()/'lock-wallpaper').is_file()
print('PROVIDER PROCESS PASS owned player cleanup, silent loop, resolve-on-Apply, lock still')
PY
done
