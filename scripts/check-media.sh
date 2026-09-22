#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
media_test_root=$(mktemp -d)
trap 'rm -rf -- "$media_test_root"' EXIT
export XDG_CONFIG_HOME="$media_test_root/config" XDG_DATA_HOME="$media_test_root/data" XDG_CACHE_HOME="$media_test_root/cache"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
mkdir -p "$XDG_CONFIG_HOME/zephyrus-shell" tests/artifacts
python3 - <<'PY'
import sys,json
sys.path.insert(0,'media')
from backend import Backend
b=Backend()
b.config_path.write_text(json.dumps({"providers":[{"name":"First service","movie_url":"https://example.org/movie/{imdbId}","series_url":"https://example.org/tv/{imdbId}/{season}/{episode}"},{"name":"Second service","url":"https://example.net/{imdbId}"}]}))
# Local art exercises asynchronous images without network or credentials.
art=b.cache/'fixture.svg'
art.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900"><defs><linearGradient id="g"><stop stop-color="#18343f"/><stop offset="1" stop-color="#7d5165"/></linearGradient></defs><path fill="url(#g)" d="M0 0h1600v900H0z"/><circle cx="1250" cy="340" r="180" fill="#cfaf88"/><path d="M0 850L600 400l350 300 350-200 300 350z" fill="#1a242e"/></svg>')
logo=b.cache/'logo.svg'
logo.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="900" height="150"><text x="4" y="100" fill="#f1f2f6" font-size="90" font-family="sans-serif" font-weight="bold">THE LAST HORIZON</text></svg>')
for kind in ['movie','tv']:
    items=[]
    for i in range(20):
        t=dict(id=f'tt{1000+i}' if kind=='movie' else f'tt{2000+i}',kind=kind,title=['The Last Horizon','A Quiet Morning','Across the Blue','Northern Lights'][i%4],year=2025,plot='A journey through unfamiliar places brings old friends together. As the landscape changes, they discover how much they have left unsaid.',runtime=112,genres=['Adventure','Drama'],ratings=[dict(source='IMDb',value=8.1)],cast=[dict(name='Alex Morgan',role='Director'),dict(name='Sam Rivers',role='Cast')])
        t.update(imdbId=t['id'],poster=art.as_uri(),backdrop=art.as_uri(),logo=logo.as_uri(),trailers=[dict(title='Official trailer',url='https://example.org/trailer'),dict(title='Trailer 2',url='https://example.org/trailer2')]);b.save_title(t);items.append(t)
        b.put('detail:'+t['id'],t);b.put('art:'+t['id'],dict(title=t,warnings=[],version=2))
        b.put('episodes:'+json.dumps([t['id'],None,'']),dict(seasons=['1','2']))
        b.put('episodes:'+json.dumps([t['id'],'1','']),dict(items=[dict(season='1',number=1,title='The beginning',plot='The journey starts here. Old friends set out to explore the northern coast.',image=art.as_uri())],next=''))
    b.put('browse:'+json.dumps([kind,'',{},''],sort_keys=True),dict(items=items,next='fixture:2'))
    for page in (2,3):
        more=[]
        for i in range(20):
            title=items[i]|{'id':f'tt{3000 + (1000 if kind == "tv" else 0) + page*20+i}','title':f'Page {page}: '+items[i]['title']}
            title['imdbId']=title['id']; more.append(title)
        b.put('browse:'+json.dumps([kind,'',{},f'fixture:{page}'],sort_keys=True),dict(items=more,next='fixture:3' if page==2 else ''))
PY
timeout 20s dbus-run-session quickshell -p "$PWD/media-smoke.qml" --no-color > "$media_test_root/log" 2>&1 || { cat "$media_test_root/log"; exit 1; }
cat "$media_test_root/log"
rg -q 'MEDIA PASS' "$media_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|MEDIA FAIL' "$media_test_root/log"; then exit 1; fi
