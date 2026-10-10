#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
export XDG_VIDEOS_DIR="$SMOKE_ROOT/videos"
python3 - <<'PY'
import sys,json,os
from pathlib import Path
sys.path.insert(0,'modules/media')
from backend import Backend
b=Backend()
launcher=b.cache/'external-fixture.py'
launcher.write_text('#!/usr/bin/env python3\nimport json, os, sys, time\nfrom pathlib import Path\ntime.sleep(0.1)\nwith (Path(os.environ["XDG_CACHE_HOME"])/"external-launches.jsonl").open("a") as output: output.write(json.dumps(sys.argv[1:])+"\\n")\n')
launcher.chmod(0o700)
(b.config_path.parent/'browser.json').write_text(json.dumps({'command':[str(launcher)]}))
b.config_path.write_text(json.dumps({"player":[str(launcher)],"providers":[{"name":"First service","movie_url":"https://example.org/movie/{imdbId}","series_url":"https://example.org/tv/{imdbId}/{season}/{episode}"},{"name":"Second service","movie_url":"https://example.net/{imdbId}.mp4","series_url":"https://example.net/{imdbId}"}],"anime_sources":[{"name":"Fixture source","strategy":"mal_embed","embed_url":"https://example.org/{malId}/{episode}/{mode}","blob_pattern":"blob=([^ ]+)","xor_key":"fixture"}]}))
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
    if kind=='movie':
        b.put('collections:tmdb:v1:movie:tt1000',dict(sections=[
            dict(label='Fixture film collection',items=[items[0],items[1]]),
            dict(label='Recommended',items=[items[2]])]))
    for page in (2,3):
        more=[]
        for i in range(20):
            title=items[i]|{'id':f'tt{3000 + (1000 if kind == "tv" else 0) + page*20+i}','title':f'Page {page}: '+items[i]['title']}
            title['imdbId']=title['id']; more.append(title)
        b.put('browse:'+json.dumps([kind,'',{},f'fixture:{page}'],sort_keys=True),dict(items=more,next='fixture:3' if page==2 else ''))
anime=dict(id='mal:1',malId=1,kind='tv',title='Example anime',year=2025,plot='An anime catalogue entry.',
           poster=art.as_uri(),genres=['Adventure'],format='TV',episodesCount=1,
           premiere='Spring 2025',sourceMaterial='Manga',ageRating='PG-13',
           relatedAnime=[dict(malId=2,title='A related anime film',relation='Sequel')],
           recommendations=[dict(malId=3,title='A recommended series')],
           cast=[dict(id='',name='Example voice actor',role='Hero (voice)',department='Acting',
                      job='Actor',url='https://anilist.co/staff/1')],
           ratings=[dict(source='MyAnimeList',value=8.7,url='https://myanimelist.net/anime/1')])
b.save_title(anime)
b.put('detail:mal:v3:1',anime)
anime_film=dict(id='mal:2',malId=2,kind='movie',title='A related anime film',
                year=2025,poster=art.as_uri(),plot='A related film.',format='MOVIE',
                recommendations=[dict(malId=3,title='A recommended series')],
                ratings=[dict(source='MyAnimeList',value=7.5)])
anime_series=dict(id='mal:3',malId=3,kind='tv',title='A recommended series',
                  year=2025,poster=art.as_uri(),plot='A recommended series.',format='TV',
                  episodesCount=1,ratings=[dict(source='MyAnimeList',value=7.8)])
for related in (anime_film,anime_series):
    b.save_title(related)
    b.put('detail:mal:v3:'+str(related['malId']),related)
b.put('collections:mal:v1:1:public',dict(sections=[
    dict(label='Related anime',items=[anime_film|{'relation':'Sequel'}]),
    dict(label='Recommended',items=[anime_series])]))
b.put('collections:mal:v1:2:public',dict(sections=[
    dict(label='Recommended',items=[anime_series])]))
b.put('anime:genres:anilist',[dict(id='Action',name='Action')])
b.put('anime:episode_metadata:v1:1',dict(available=True,episodes={'1':dict(title='First episode',plot='The story begins.',image='',date='2025-04-01')}))
anime_filters=dict(genre='Anime',animeGenre='',sort='',country='',minYear='',maxYear='',rating='',votes='')
for query in ('','example'):
    b.put(b.browse_key('tv',query,anime_filters,''),dict(items=[anime],next=''))
b.put(b.browse_key('tv','',{'genre':'Anime'},''),dict(items=[anime],next=''))
b.put(b.browse_key('movie','',{'genre':'Anime'},''),dict(items=[anime_film],next=''))
show=dict(id='tt2001',imdbId='tt2001',kind='tv',title='A Quiet Morning',year=2025)
source=b.cache/'A.Quiet.Morning.S01E01.mkv'
source.write_bytes(b'local video fixture')
video=Path(b.local.add(show,source,move=True,release_name='A Quiet Morning S01 WEB-DL'))
video.with_name(video.stem+'.en.srt').write_text('1\n00:00:01,000 --> 00:00:02,000\nHello\n')
PY
run_smoke media "MEDIA" 20s

# Launch harmless detached fixtures through the real module controls and workers.
python3 - <<'PYPLAYER'
import json, os
from pathlib import Path
config = Path(os.environ['XDG_CONFIG_HOME'])/'zephyrus-shell/media.json'
value = json.loads(config.read_text())
player = Path(value['player'][0]).with_name('mpv')
player.symlink_to(value['player'][0])
value['player'] = [str(player)]
config.write_text(json.dumps(value))
PYPLAYER
offline
run_smoke external-launch "EXTERNAL" 20s
python3 - <<'PYVERIFY'
import json, os, time
from pathlib import Path
path = Path(os.environ['XDG_CACHE_HOME'])/'external-launches.jsonl'
for attempt in range(30):
    launches = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
    if len(launches) >= 7: break
    time.sleep(0.1)
assert len(launches) == 7, launches
assert ['https://example.org/movie/tt1000'] in launches, launches
assert ['--', 'https://example.net/tt1000.mp4'] in launches, launches
assert ['https://example.org/trailer'] in launches, launches
assert any('imdb.com/title/tt1000' in args[-1] for args in launches), launches
assert ['https://example.org/tv/tt2001/1/1'] in launches, launches
assert any(any(arg.startswith('--sub-file=') for arg in args) for args in launches), launches
assert ['https://example.org/hidden-owner'] in launches, launches
print('EXTERNAL DETACHED PASS: all seven applications survive module destruction')
PYVERIFY

# The real owned torrent worker talks to an isolated Web UI fixture; lifecycle
# actions use the real Movies/Series entry points and ShellState retention.
start_fixture qbittorrent python3 tests/fixtures/media-qbittorrent.py
wait_for "$XDG_CONFIG_HOME/zephyrus-shell/torrents.json"
run_smoke media-download "DOWNLOAD" 25s
