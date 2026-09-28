#!/usr/bin/env python3
"""Owned JSON-lines media worker. Metadata API keys stay in this process."""
import concurrent.futures
from contextlib import contextmanager
import hashlib
import html
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import shutil
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from media.local import LocalLibrary
from media import anime_sources

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'zephyrus-shell/media.json'
DATA = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'zephyrus-shell/media'
CACHE = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'zephyrus-shell/media'
TMDB = 'https://api.themoviedb.org/3'
OMDB = 'https://www.omdbapi.com/'
MAL = 'https://api.myanimelist.net/v2'
ANILIST = 'https://graphql.anilist.co'
ANIMAP = 'https://animap.id'
MAL_FIELDS = ('id,title,main_picture,alternative_titles,start_date,synopsis,mean,'
              'num_scoring_users,nsfw,media_type,status,genres,num_episodes,average_episode_duration,studios')
MAL_DETAIL_FIELDS = MAL_FIELDS+',start_season,source,rating,background'
ANILIST_FIELDS = '''idMal title { romaji english native } synonyms format status
    description(asHtml:false) startDate { year } coverImage { extraLarge large }
    bannerImage genres episodes duration nextAiringEpisode { episode }
    studios(isMain:true) { nodes { name } } trailer { id site }'''
ANILIST_BROWSE = '''query ($page:Int!, $format:MediaFormat!, $search:String, $genre:String,
    $after:FuzzyDateInt, $before:FuzzyDateInt, $minScore:Int, $sort:[MediaSort]) {
    Page(page:$page, perPage:24) { pageInfo { hasNextPage }
      media(type:ANIME, format:$format, isAdult:false, search:$search, genre:$genre,
        startDate_greater:$after, startDate_lesser:$before,
        averageScore_greater:$minScore, sort:$sort) { '''+ANILIST_FIELDS+''' }
    }
}'''
ANILIST_DETAILS = '''query ($malId:Int!) {
    Media(idMal:$malId, type:ANIME) { '''+ANILIST_FIELDS+'''
      season seasonYear source
      characters(sort:ROLE, perPage:12) { edges {
        role node { id name { full } }
        voiceActors(language:JAPANESE) { id name { full } image { medium } }
      } }
      staff(sort:RELEVANCE, perPage:25) { edges {
        role node { id name { full } image { medium } }
      } }
    }
}'''
ANILIST_COLLECTIONS = '''query ($malId:Int!) {
    Media(idMal:$malId, type:ANIME) {
      relations { edges { relationType node {
        idMal format title { english romaji native } coverImage { large } startDate { year }
      } } }
      recommendations(sort:RATING_DESC, perPage:10) { nodes {
        mediaRecommendation {
          idMal format title { english romaji native } coverImage { large } startDate { year }
        }
      } }
    }
}'''
ANILIST_ENTRY = '''query ($malId:Int!) {
    Media(idMal:$malId, type:ANIME) { '''+ANILIST_FIELDS+''' }
}'''
TMDB_GENRES = {
    'movie': {'Action':28,'Adventure':12,'Animation':16,'Comedy':35,'Crime':80,
              'Documentary':99,'Drama':18,'Family':10751,'Fantasy':14,'History':36,
              'Horror':27,'Music':10402,'Mystery':9648,'Romance':10749,
              'Science Fiction':878,'TV Movie':10770,'Thriller':53,'War':10752,'Western':37},
    'tv': {'Action & Adventure':10759,'Animation':16,'Comedy':35,'Crime':80,
           'Documentary':99,'Drama':18,'Family':10751,'Kids':10762,'Mystery':9648,
           'News':10763,'Reality':10764,'Sci-Fi & Fantasy':10765,'Soap':10766,
           'Talk':10767,'War & Politics':10768,'Western':37}}
SORTS = {'popular':'popularity.desc', 'rating':'vote_average.desc', 'votes':'vote_count.desc', 'newest':'primary_release_date.desc', 'oldest':'primary_release_date.asc'}

class MediaError(Exception):
    pass

def http(url, params=None, *, timeout=15):
    if params:
        url += '?' + urllib.parse.urlencode({k:v for k,v in params.items() if v is not None and v != ''}, doseq=True)
    try:
        req = urllib.request.Request(url, headers={'User-Agent':'ZephyrusMedia/1.0', 'Accept':'application/json'})
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as e:
        e.close()
        raise MediaError(f'{urllib.parse.urlparse(url).hostname} returned HTTP {e.code}. Try again later.') from None
    except (OSError, ValueError):
        raise MediaError(f'Cannot reach {urllib.parse.urlparse(url).hostname}. Check your connection and configuration.') from None

def image_url(path, size='original'):
    return 'https://image.tmdb.org/t/p/' + size + path if path else ''

def tmdb_title(d, kind):
    imdb = d.get('imdb_id') or d.get('external_ids',{}).get('imdb_id')
    return dict(id=imdb or f'tmdb:{kind}:{d["id"]}',imdbId=imdb or '',tmdbId=d['id'],kind=kind,title=d.get('title') or d.get('name',''),year=(d.get('release_date') or d.get('first_air_date',''))[:4],poster=image_url(d.get('poster_path'),'w500'),backdrop=image_url(d.get('backdrop_path')),plot=d.get('overview',''),runtime=d.get('runtime') or next(iter(d.get('episode_run_time',[])),0),genres=[g['name'] for g in d.get('genres',[])] or [name for name,id in TMDB_GENRES[kind].items() if id in d.get('genre_ids',[])],countries=d.get('production_countries',[]),rating=d.get('vote_average'),votes=d.get('vote_count',0),ratings=[{'source':'TMDB','value':round(d.get('vote_average',0),1)}])

def omdb_title(d):
    def value(key):
        v=d.get(key)
        return v if v and v != 'N/A' else ''
    def number(key):
        match=re.search(r'\d+(?:\.\d+)?', str(value(key)).replace(',',''))
        return float(match[0]) if match else None
    def names(key): return [n.strip() for n in value(key).split(',') if n.strip()]
    return dict(id=d['imdbID'],imdbId=d['imdbID'],kind='tv' if d.get('Type')=='series' else 'movie',
                title=value('Title'),year=int(number('Year')) if number('Year') else None,
                poster=value('Poster'),plot=value('Plot'),runtime=int(number('Runtime')) if number('Runtime') else None,
                genres=names('Genre'),countries=names('Country'),rating=number('imdbRating'),
                votes=int(number('imdbVotes')) if number('imdbVotes') else None,
                ratings=[dict(source=r['Source'],value=r['Value']) for r in d.get('Ratings',[]) if r.get('Value') not in (None,'N/A','')],
                cast=[dict(id='',name=name,role=role) for field,role in [('Director','Director'),('Writer','Writer'),('Actors','Cast')] for name in names(field)])

def anilist_title(d, kind):
    mal_id=d.get('idMal')
    if not isinstance(mal_id,int) or mal_id<=0: raise MediaError('Anime catalogue returned no MAL ID.')
    names=d.get('title') or {}
    picture=d.get('coverImage') or {}
    studios=(d.get('studios') or {}).get('nodes') or []
    next_episode=(d.get('nextAiringEpisode') or {}).get('episode') or 0
    count=d.get('episodes') or max(0,next_episode-1)
    plot=html.unescape(re.sub(r'<[^>]+>', ' ', d.get('description') or ''))
    plot=re.sub(r'\s+', ' ', plot).strip()
    trailer=d.get('trailer') or {}
    trailer_url=('https://www.youtube.com/watch?v='+trailer['id']
                 if trailer.get('site')=='youtube' and re.fullmatch(r'[\w-]{11}',trailer.get('id') or '') else '')
    url=f'https://myanimelist.net/anime/{mal_id}'
    return dict(id=f'mal:{mal_id}',malId=mal_id,kind=kind,
                title=names.get('english') or names.get('romaji') or names.get('native') or '',
                originalTitle=names.get('native') or names.get('romaji') or '',
                aliases=list(dict.fromkeys(name for name in [*names.values(),*(d.get('synonyms') or [])] if name)),
                format=d.get('format') or '',year=(d.get('startDate') or {}).get('year') or '',
                poster=picture.get('extraLarge') or picture.get('large') or '',
                backdrop=d.get('bannerImage') or '',plot=plot,runtime=d.get('duration'),
                genres=d.get('genres') or [],studios=[item['name'] for item in studios if item.get('name')],
                episodesCount=count,status=d.get('status') or '',rating=None,votes=0,malUrl=url,
                ratings=[],trailers=[dict(title='Trailer',url=trailer_url)] if trailer_url else [])

def anime_related(rows, *, anilist_edges=False):
    result=[]; seen=set()
    for row in rows or []:
        if not isinstance(row,dict):continue
        node=row.get('node') or {}
        mal_id=node.get('idMal' if anilist_edges else 'id')
        if not isinstance(mal_id,int) or mal_id<=0 or mal_id in seen:continue
        seen.add(mal_id)
        names=node.get('title') if anilist_edges else None
        name=(names.get('english') or names.get('romaji') or names.get('native')
              if isinstance(names,dict) else node.get('title'))
        relation=(row.get('relationType') if anilist_edges else row.get('relation_type_formatted')) or ''
        picture=node.get('coverImage' if anilist_edges else 'main_picture') or {}
        start=node.get('startDate') if anilist_edges else node.get('start_date')
        format_name=node.get('format' if anilist_edges else 'media_type') or ''
        result.append(dict(id=f'mal:{mal_id}',malId=mal_id,title=name or f'Anime {mal_id}',
                           kind=anime_kind(format_name) if format_name else '',
                           poster=picture.get('large') or picture.get('medium') or '',
                           year=(start or {}).get('year') if isinstance(start,dict) else str(start or '')[:4],
                           relation=str(relation).replace('_',' ').title()))
    return result

def anime_cast(data):
    result=[]; seen=set()
    for edge in (data.get('characters') or {}).get('edges') or []:
        if not isinstance(edge,dict):continue
        character=(edge.get('node') or {}).get('name') or {}
        name=character.get('full') or ''
        for actor in edge.get('voiceActors') or []:
            actor_id=actor.get('id')
            if not isinstance(actor_id,int) or actor_id<=0 or not name:continue
            key=(actor_id,name)
            if key in seen:continue
            seen.add(key)
            result.append(dict(id='',name=(actor.get('name') or {}).get('full') or '',
                               role=f'{name} (voice)',job='Actor',department='Acting',
                               image=(actor.get('image') or {}).get('medium') or '',
                               url=f'https://anilist.co/staff/{actor_id}'))
    for edge in (data.get('staff') or {}).get('edges') or []:
        if not isinstance(edge,dict):continue
        person=edge.get('node') or {}; person_id=person.get('id'); role=edge.get('role') or ''
        if not isinstance(person_id,int) or person_id<=0:continue
        key=(person_id,role)
        if key in seen:continue
        seen.add(key)
        result.append(dict(id='',name=(person.get('name') or {}).get('full') or '',
                           role=role,job=('Writer' if role in ('Series Composition','Script') else role),
                           department='Crew',image=(person.get('image') or {}).get('medium') or '',
                           url=f'https://anilist.co/staff/{person_id}'))
    return [person for person in result if person['name']]

def official_anime_title(d, kind):
    mal_id=d.get('id')
    if not isinstance(mal_id,int): raise MediaError('MAL returned an invalid title ID.')
    alternative=d.get('alternative_titles') or {}
    names=[d.get('title'),alternative.get('en'),alternative.get('ja'),*(alternative.get('synonyms') or [])]
    url=f'https://myanimelist.net/anime/{mal_id}'
    score=d.get('mean')
    poster=d.get('main_picture') or {}
    duration=d.get('average_episode_duration')
    season=d.get('start_season') or {}
    premiere=(str(season.get('season') or '').title()+' '+str(season.get('year') or '')).strip()
    source=str(d.get('source') or '').replace('_',' ').title()
    age_rating={'g':'G','pg':'PG','pg_13':'PG-13','r':'R-17+','r+':'R+','rx':'Rx'}.get(d.get('rating'), '')
    return dict(id=f'mal:{mal_id}',malId=mal_id,kind=kind,
                title=alternative.get('en') or d.get('title') or '',
                originalTitle=alternative.get('ja') or d.get('title') or '',
                aliases=list(dict.fromkeys(name for name in names if name)),
                format=d.get('media_type') or '',year=str(d.get('start_date') or '')[:4],
                poster=poster.get('large') or poster.get('medium') or '',plot=d.get('synopsis') or '',
                runtime=round(duration/60) if isinstance(duration,(int,float)) and duration else None,
                genres=[item['name'] for item in d.get('genres') or [] if item.get('name')],
                studios=[item['name'] for item in d.get('studios') or [] if item.get('name')],
                episodesCount=d.get('num_episodes') or 0,status=d.get('status') or '',
                premiere=premiere,sourceMaterial=source,ageRating=age_rating,
                background=d.get('background') or '',
                rating=score,votes=d.get('num_scoring_users') or 0,malUrl=url,
                ratings=[dict(source='MyAnimeList',value=score,url=url)] if score is not None else [])

def anime_kind(format_name):
    return 'movie' if str(format_name).lower()=='movie' else 'tv'

def official_anime(url,client_id,params=None):
    if params:url+='?'+urllib.parse.urlencode(params)
    request=urllib.request.Request(url,headers={'User-Agent':'ZephyrusMedia/1.0',
        'Accept':'application/json','X-MAL-CLIENT-ID':client_id})
    try:
        with urllib.request.urlopen(request,timeout=15) as response:return json.load(response)
    except urllib.error.HTTPError as error:
        status=error.code
        error.close()
        raise MediaError(f'MAL returned HTTP {status}. Check mal_client_id or try again later.') from None
    except (OSError,ValueError):
        raise MediaError('Cannot reach the official MAL catalogue. Try again later.') from None

def anilist(query, variables=None):
    payload=json.dumps(dict(query=query,variables={key:value for key,value in (variables or {}).items()
                                                   if value is not None})).encode()
    request=urllib.request.Request(ANILIST,data=payload,headers={
        'User-Agent':'ZephyrusMedia/1.0','Accept':'application/json','Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(request,timeout=15) as response: result=json.load(response)
    except urllib.error.HTTPError as error:
        status=error.code
        error.close()
        raise MediaError(f'AniList returned HTTP {status}. Try again later.') from None
    except (OSError,ValueError):
        raise MediaError('Cannot reach the anime catalogue. Check your connection.') from None
    if not isinstance(result,dict) or result.get('errors') or not isinstance(result.get('data'),dict):
        raise MediaError('AniList returned an unreadable catalogue response.')
    return result['data']

def merge_ratings(*groups):
    aliases={'internet movie database':'IMDb','imdb':'IMDb','rotten tomatoes':'Rotten Tomatoes',
             'tomatoes':'Rotten Tomatoes','metacritic':'Metacritic','tmdb':'TMDB'}
    ratings={}
    for group in groups:
        for item in group:
            if item.get('value') in (None,'','N/A'): continue
            source=aliases.get(item['source'].lower(),item['source'])
            ratings[source.lower()]=item|{'source':source}
    return list(ratings.values())

def clean_spoiler(text):
    text=re.sub(r'\[(?:edit|edit source)\]', '', text, flags=re.I)
    text=re.sub(r'^\s*(?:plot(?: synopsis)?|synopsis|story)\s*\n+', '', text, flags=re.I)
    return text.strip()

def tmdb_credits(data):
    credits=data.get('credits',{})
    return [dict(id='tmdb:'+str(p['id']),name=p['name'],role=p.get('character') or 'Actor',department='Acting',job='Actor',image=image_url(p.get('profile_path'),'w185')) for p in credits.get('cast',[])]+[dict(id='tmdb:'+str(p['id']),name=p['name'],role=p.get('job',''),job=p.get('job',''),department=p.get('department','Crew'),image=image_url(p.get('profile_path'),'w185')) for p in credits.get('crew',[])]

def credit_role(value):
    role=str(value or '').replace('_',' ').strip().lower()
    if role in ('actor','actress','acting','cast','self'): return 'Actor'
    if role in ('director','co-director','co director','series director','directing'): return 'Director'
    if role in ('writer','writing','screenplay','story','teleplay','novel','characters'): return 'Writer'
    if 'producer' in role or role=='production': return 'Producer'
    return role.title() if role else ''

def tmdb_trailers(data):
    videos=[v for v in data.get('videos',{}).get('results',[]) if v.get('site')=='YouTube' and v.get('type')=='Trailer' and v.get('key')]
    videos.sort(key=lambda v:(not v.get('official',False),v.get('iso_639_1')!='en'))
    return list({v['key']:dict(title=v.get('name','Trailer'),url='https://www.youtube.com/watch?v='+v['key']) for v in videos}.values())

def template_url(template, title, season=None, episode=None):
    if not template.strip(): raise MediaError('Add a playback provider to media.json or save a custom URL for this title.')
    url=template.strip()
    if '{' not in url: url=url.rstrip('/')+'/title/{imdbId}/'
    url=re.sub(r'\{kind:([^|{}]*)\|([^{}]*)\}',lambda m:m[2] if title['kind']=='tv' else m[1],url)
    for key,value in dict(imdbId=title.get('imdbId'),tmdbId=title.get('tmdbId'),season=season,episode=episode).items():
        if '{'+key+'}' in url:
            if value is None or value=='': raise MediaError(f'{key} is unavailable for this selection.')
            url=url.replace('{'+key+'}',urllib.parse.quote(str(value),safe=''))
    if re.search(r'\{.*?\}',url): raise MediaError('Unknown playback template placeholder.')
    if urllib.parse.urlparse(url).scheme not in ('http','https'): raise MediaError('Playback URLs must use http or https.')
    return url

class Backend:
    def __init__(self, config=CONFIG, data=DATA, cache=CACHE):
        self.config_path,self.data,self.cache=config,data,cache
        self.write_lock = threading.RLock()
        config.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        for p in (data,cache): p.mkdir(parents=True,exist_ok=True,mode=0o700)
        with self.db() as db:
            db.executescript('CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, value TEXT, updated REAL); CREATE TABLE IF NOT EXISTS personal (id TEXT PRIMARY KEY, value TEXT); CREATE TABLE IF NOT EXISTS aliases (alias TEXT PRIMARY KEY, id TEXT);')
        self.local = LocalLibrary(data)
    @contextmanager
    def db(self):
        db=sqlite3.connect(self.data/'library.sqlite',timeout=20)
        try:
            with db:
                yield db
        finally:
            db.close()
    def config(self):
        try:
            config=json.loads(self.config_path.read_text()) if self.config_path.exists() else {}
        except (OSError,ValueError):
            raise MediaError(f'Cannot read {self.config_path}. Check the JSON syntax.') from None
        if not isinstance(config,dict): raise MediaError('media.json must contain a JSON object.')
        if not isinstance(config.get('mal_client_id',''),str):
            raise MediaError('mal_client_id must be a string.')
        providers=config.get('providers',[])
        if not isinstance(providers,list): raise MediaError('providers must be a JSON array.')
        for provider in providers:
            if (not isinstance(provider,dict) or not isinstance(provider.get('name'),str)
                    or not provider['name'].strip()
                    or not any(isinstance(provider.get(key),str) and provider[key].strip() for key in ('movie_url','series_url'))
                    or any(key in provider and not isinstance(provider[key],str) for key in ('movie_url','series_url'))):
                raise MediaError('Each playback provider needs a name and movie_url and/or series_url strings.')
        anime=config.get('anime_sources',[])
        if not isinstance(anime,list): raise MediaError('anime_sources must be a JSON array.')
        for source in anime:
            if (not isinstance(source,dict) or not isinstance(source.get('name'),str) or not source['name'].strip()
                    or source.get('strategy') not in ('mal_embed','search_embed')):
                raise MediaError('Each anime source needs a name and supported strategy.')
        return config
    def playback_providers(self,kind):
        key='series_url' if kind=='tv' else 'movie_url'
        return [(p['name'],p.get(key,'')) for p in self.config().get('providers',[]) if p.get(key,'').strip()]
    def omdb(self,**params):
        key=self.config().get('omdb_key')
        if not key: raise MediaError('OMDb key is not configured.')
        result=http(OMDB,dict(apikey=key,**params))
        if result.get('Response')=='False':
            # Never echo an upstream message that may include the request/key.
            message=str(result.get('Error','')).lower()
            if 'not found' in message: return {}
            if 'limit' in message: raise MediaError('OMDb request limit reached. Try again later.')
            if 'key' in message: raise MediaError('OMDb rejected the API key. Check omdb_key in media.json.')
            raise MediaError('OMDb could not complete this request.')
        return result
    def get(self,key,ttl=None):
        with self.db() as db: row=db.execute('SELECT value,updated FROM cache WHERE key=?',(key,)).fetchone()
        return json.loads(row[0]) if row and (ttl is None or time.time()-row[1]<ttl) else None
    def put(self,key,value):
        with self.db() as db: db.execute('INSERT OR REPLACE INTO cache VALUES (?,?,?)',(key,json.dumps(value),time.time()))
        return value
    def canonical(self,id):
        with self.db() as db: row=db.execute('SELECT id FROM aliases WHERE alias=?',(id,)).fetchone()
        return row[0] if row else id
    def personal(self,id):
        with self.db() as db: row=db.execute('SELECT value FROM personal WHERE id=?',(self.canonical(id),)).fetchone()
        return json.loads(row[0]) if row else dict(favorite=False,note='',url='')
    def save_title(self,t):
        with self.write_lock:
            return self._save_title(t)
    def _save_title(self,t):
        old=self.get('title:'+self.canonical(t['id'])) or {}
        updates={k:v for k,v in t.items() if v is not None and v!='' and v!=[]}
        if str(t['id']).startswith('mal:'):
            updates.update({key:t[key] for key in ('rating','votes','ratings') if key in t})
        merged=old|updates
        if merged.get('imdbId'):
            canonical=merged['imdbId']; merged['id']=canonical
            aliases=[t['id']]
            if merged.get('tmdbId'): aliases.append(f'tmdb:{merged["kind"]}:{merged["tmdbId"]}')
            with self.db() as db:
                for alias in aliases:
                    db.execute('INSERT OR REPLACE INTO aliases VALUES (?,?)',(alias,canonical))
                    db.execute('INSERT OR IGNORE INTO personal SELECT ?,value FROM personal WHERE id=?',(canonical,alias))
                    if alias!=canonical: db.execute('DELETE FROM personal WHERE id=?',(alias,))
        self.put('title:'+merged['id'],merged)
        return merged
    def tmdb(self,path,**params):
        key=self.config().get('tmdb_key','')
        if not key: raise MediaError('TMDB key is not configured.')
        return http(TMDB+'/'+path,dict(api_key=key,**params))
    def identity(self,t):
        if t.get('tmdbId'): return t
        data=self.tmdb('find/'+t['imdbId'],external_source='imdb_id')
        rows=data.get('tv_results' if t['kind']=='tv' else 'movie_results',[])
        if not rows: raise MediaError('No matching TMDB title found.')
        return t|{'tmdbId':rows[0]['id']}
    def browse_key(self,kind,query,filters,page):
        fields=[kind,query,filters,page]
        if filters.get('genre')=='Anime':
            client_id=self.config().get('mal_client_id','').strip()
            fields.append('anime:v2:'+hashlib.sha256(client_id.encode()).hexdigest()[:16]
                          if client_id else 'anime:v2:anilist')
        return 'browse:'+json.dumps(fields,sort_keys=True)
    def browse(self,r):
        kind=r.get('kind','movie'); q=r.get('query','').strip(); f=r.get('filters',{}); token=r.get('page','')
        anime=f.get('genre')=='Anime'
        if r.get('favorites'):
            with self.db() as db: rows=db.execute('SELECT id,value FROM personal').fetchall()
            titles=[self.get('title:'+id) for id,p in rows if json.loads(p).get('favorite')]
            return dict(items=[t for t in titles if t and t['kind']==kind and t['id'].startswith('mal:')==anime
                               and q.lower() in t['title'].lower()],next='')
        key=self.browse_key(kind,q,f,token)
        cached=self.get(key,900)
        if cached and not r.get('refresh'): return cached
        errors=[]
        candidates=[('anilist',self.browse_anime)] if anime else [('tmdb',self.browse_tmdb)]
        if anime and self.config().get('mal_client_id','').strip() and self.official_anime_supported(kind,q,f):
            candidates.insert(0,('malapi',self.browse_anime_official))
        if q and not anime: candidates.append(('omdb',self.browse_omdb))
        current=str(token).split(':')[0] if str(token).startswith(('tmdb:','omdb:','anilist:','malapi:')) else ''
        if current: candidates=[candidate for candidate in candidates if candidate[0]==current]
        for name,provider in candidates:
            if name not in ('anilist','malapi') and not self.config().get(name+'_key'): continue
            try:
                items,next_token=provider(kind,q,f,token)
                break
            except MediaError as error: errors.append(str(error))
        else:
            stale=self.get(key)
            if stale: return stale | {'warning':'Offline: showing the saved catalogue; configured providers are unavailable.'}
            if anime and errors:
                raise MediaError('Anime catalogue unavailable. '+' '.join(errors))
            if not q and self.config().get('omdb_key') and not self.config().get('tmdb_key'):
                raise MediaError('OMDb supports title search, but discovery requires a TMDB key. Search for a title or add tmdb_key to media.json.')
            raise MediaError('No catalogue provider is available. '+' '.join(errors))
        items=[t for t in items if t['kind']==kind]
        if not anime and not q and not f.get('maxYear'):
            items=[t for t in items if int(t.get('year') or 0)<=time.localtime().tm_year]
        if q and f.get('country') and not anime:
            items=[t for t in items if f['country'].upper() in [c.upper() if isinstance(c,str) else (c.get('code') or c.get('iso_3166_1') or '').upper() for c in t.get('countries',[])]]
        if q and not anime:
            items=[t for t in items if (not f.get('genre') or f['genre'] in t.get('genres',[])) and (not f.get('minYear') or int(t.get('year') or 0)>=int(f['minYear'])) and (not f.get('maxYear') or int(t.get('year') or 9999)<=int(f['maxYear'])) and (not f.get('rating') or float(t.get('rating') or 0)>=float(f['rating'])) and (not f.get('votes') or int(t.get('votes') or 0)>=int(f['votes']))]
            sort=f.get('sort'); field={'rating':'rating','votes':'votes','newest':'year','oldest':'year'}.get(sort)
            if field: items.sort(key=lambda t:float(t.get(field) or 0),reverse=sort!='oldest')
        return self.put(key,dict(items=[self.save_title(t) for t in items],next=next_token))
    def official_anime_supported(self,kind,query,filters):
        if any(filters.get(name) for name in ('animeGenre','minYear','maxYear','rating')):
            return False
        sort=filters.get('sort') or ''
        if query:return sort==''
        if kind=='movie':return sort=='rating'
        return sort in ('','popular','rating')
    def browse_anime_official(self,kind,query,filters,token):
        offset=int(str(token).split(':')[-1]) if str(token).startswith('malapi:') else 0
        client_id=self.config()['mal_client_id'].strip()
        path='/anime' if query else '/anime/ranking'
        params=dict(limit=100,offset=offset,fields=MAL_FIELDS)
        if query:params['q']=query
        else:params['ranking_type']='movie' if kind=='movie' and filters.get('sort')=='rating' else (
            'tv' if filters.get('sort')=='rating' else 'bypopularity')
        data=official_anime(MAL+path,client_id,params)
        if not isinstance(data,dict) or not isinstance(data.get('data'),list):
            raise MediaError('MAL returned an unreadable catalogue page.')
        rows=[row.get('node') for row in data['data'] if isinstance(row,dict)]
        media_type='movie' if kind=='movie' else 'tv'
        items=[official_anime_title(row,kind) for row in rows
               if isinstance(row,dict) and row.get('media_type')==media_type
               and row.get('nsfw')!='black']
        next_url=(data.get('paging') or {}).get('next')
        next_offset=urllib.parse.parse_qs(urllib.parse.urlparse(next_url or '').query).get('offset',[])
        next_page=f'malapi:{int(next_offset[0])}' if next_offset and str(next_offset[0]).isdigit() else ''
        return items,next_page
    def anime_genres(self):
        cached=self.get('anime:genres:anilist',86400*7)
        if cached:return cached
        try:
            rows=anilist('{ GenreCollection }').get('GenreCollection') or []
            result=[dict(id=name,name=name) for name in rows if isinstance(name,str) and name!='Hentai']
            return self.put('anime:genres:anilist',sorted(result,key=lambda row:row['name']))
        except MediaError:
            return self.get('anime:genres:anilist') or []
    def browse_anime(self,kind,q,f,token):
        page=int(str(token).split(':')[-1]) if str(token).startswith('anilist:') else 1
        sort={'popular':'POPULARITY_DESC','rating':'SCORE_DESC','votes':'POPULARITY_DESC',
              'newest':'START_DATE_DESC','oldest':'START_DATE'}.get(f.get('sort'))
        if not sort: sort='SEARCH_MATCH' if q else 'POPULARITY_DESC'
        try:
            minimum=float(f.get('rating') or 0)
        except (ValueError,TypeError): minimum=0
        variables=dict(page=page,format='MOVIE' if kind=='movie' else 'TV',search=q or None,
                       genre=f.get('animeGenre') or None,
                       after=(int(f['minYear'])-1)*10000+1231 if f.get('minYear') else None,
                       before=(int(f['maxYear'])+1)*10000+101 if f.get('maxYear') else None,
                       minScore=max(0,min(99,math.ceil(minimum*10)-1)) if minimum>0 else None,
                       sort=[sort])
        data=anilist(ANILIST_BROWSE,variables).get('Page') or {}
        items=[]
        for row in data.get('media') or []:
            if isinstance(row,dict) and isinstance(row.get('idMal'),int) and row['idMal']>0:
                items.append(anilist_title(row,kind))
        return items,f'anilist:{page+1}' if (data.get('pageInfo') or {}).get('hasNextPage') else ''
    def anime_entry(self,r):
        try:mal_id=int(r.get('malId'))
        except (TypeError,ValueError):raise MediaError('Choose a valid related anime.') from None
        if mal_id<=0:raise MediaError('Choose a valid related anime.')
        cached=self.get('title:mal:'+str(mal_id))
        if cached and cached.get('kind') in ('movie','tv'):return cached
        client_id=self.config().get('mal_client_id','').strip()
        if client_id:
            try:
                data=official_anime(f'{MAL}/anime/{mal_id}',client_id,dict(fields=MAL_FIELDS))
                if isinstance(data,dict) and data.get('id')==mal_id:
                    return self.save_title(official_anime_title(data,anime_kind(data.get('media_type'))))
            except MediaError:
                pass
        data=anilist(ANILIST_ENTRY,{'malId':mal_id}).get('Media') or {}
        if data.get('idMal')!=mal_id:raise MediaError('This related anime is unavailable in the catalogue.')
        return self.save_title(anilist_title(data,anime_kind(data.get('format'))))
    def anime_details(self,r):
        title=r['title']; mal_id=title.get('malId') or title['id'].split(':')[-1]
        client_id=self.config().get('mal_client_id','').strip()
        key='detail:mal:v3:'+str(mal_id)+((':official:'+hashlib.sha256(client_id.encode()).hexdigest()[:16])
                                        if client_id else '')
        cached=self.get(key,86400)
        if cached and not r.get('refresh'):return cached
        result=title.copy(); official_ok=False
        if client_id:
            try:
                data=official_anime(f'{MAL}/anime/{int(mal_id)}',client_id,dict(fields=MAL_DETAIL_FIELDS))
                if not isinstance(data,dict):raise MediaError('MAL returned unreadable title details.')
                result.update(official_anime_title(data,title['kind']))
                official_ok=True
            except MediaError:
                pass
        try:
            data=anilist(ANILIST_DETAILS,{'malId':int(mal_id)}).get('Media') or {}
            enriched=anilist_title(data,title['kind'])
            if not official_ok:result.update(enriched)
            else:
                for field in ('backdrop','trailers','episodesCount','poster','plot','studios','year','status'):
                    if not result.get(field) and enriched.get(field):result[field]=enriched[field]
            cast=anime_cast(data)
            if cast:result['cast']=cast
            if not result.get('premiere') and data.get('season') and data.get('seasonYear'):
                result['premiere']=str(data['season']).title()+' '+str(data['seasonYear'])
            if not result.get('sourceMaterial') and data.get('source'):
                result['sourceMaterial']=str(data['source']).replace('_',' ').title()
        except MediaError:
            pass
        return self.put(key,self.save_title(result))

    def collections(self,r):
        title=r['title']
        anime=str(title['id']).startswith('mal:')
        client_id=self.config().get('mal_client_id','').strip() if anime else ''
        suffix=hashlib.sha256(client_id.encode()).hexdigest()[:16] if client_id else 'public'
        key=('collections:mal:v1:'+str(title.get('malId') or title['id'].split(':')[-1])+':'+suffix
             if anime else 'collections:tmdb:v1:'+title['kind']+':'+str(self.canonical(title['id'])))
        cached=self.get(key,86400)
        if cached and not r.get('refresh'):return cached
        try:
            result=self.anime_collections(title,client_id) if anime else self.tmdb_collections(title)
            return self.put(key,result)
        except MediaError:
            stale=self.get(key)
            if stale:return stale
            raise

    def anime_collections(self,title,client_id):
        mal_id=int(title.get('malId') or title['id'].split(':')[-1])
        official={}; anilist_data={}; errors=[]
        if client_id:
            try:
                official=official_anime(f'{MAL}/anime/{mal_id}',client_id,
                                        dict(fields='related_anime,recommendations'))
            except MediaError as error:errors.append(str(error))
        try:
            anilist_data=anilist(ANILIST_COLLECTIONS,{'malId':mal_id}).get('Media') or {}
        except MediaError as error:errors.append(str(error))
        if errors and not official and not anilist_data:raise MediaError('Anime collections are unavailable. '+' '.join(errors))
        related=anime_related(official.get('related_anime'))
        recommended=anime_related(official.get('recommendations'))
        related_anilist=anime_related((anilist_data.get('relations') or {}).get('edges'),anilist_edges=True)
        recommendations=(anilist_data.get('recommendations') or {}).get('nodes') or []
        recommended_anilist=anime_related(
            [{'node':row.get('mediaRecommendation')} for row in recommendations if isinstance(row,dict)],
            anilist_edges=True)
        def combine(primary,secondary):
            by_id={item['malId']:item for item in secondary}
            merged=[{**by_id.get(item['malId'],{}),**{key:value for key,value in item.items()
                     if value or key in ('id','malId','title','relation')}} for item in primary]
            seen={item['malId'] for item in merged}
            return merged+[item for item in secondary if item['malId'] not in seen]
        sections=[]
        for label,items in (('Related anime',combine(related,related_anilist)),
                            ('Recommended',combine(recommended,recommended_anilist))):
            if items:sections.append(dict(label=label,items=items))
        return dict(sections=sections)

    def tmdb_collections(self,title):
        if not self.config().get('tmdb_key'):
            raise MediaError('Add tmdb_key to media.json to load collections and recommendations.')
        title=self.identity(title)
        kind=title['kind']; tmdb_id=title['tmdbId']; sections=[]; errors=[]
        if kind=='movie':
            try:
                details=self.tmdb(f'movie/{tmdb_id}')
                collection=details.get('belongs_to_collection') or {}
                if isinstance(collection.get('id'),int) and collection['id']>0:
                    data=self.tmdb(f'collection/{collection["id"]}')
                    parts=[tmdb_title(row,'movie') for row in data.get('parts') or []
                           if isinstance(row,dict) and isinstance(row.get('id'),int) and not row.get('adult')]
                    parts.sort(key=lambda row:row.get('year') or '9999')
                    if parts:sections.append(dict(label=data.get('name') or 'Movie collection',items=parts))
            except MediaError as error:errors.append(str(error))
        try:
            data=self.tmdb(f'{kind}/{tmdb_id}/recommendations',page=1)
            items=[tmdb_title(row,kind) for row in data.get('results') or []
                   if isinstance(row,dict) and isinstance(row.get('id'),int) and not row.get('adult')]
            if items:sections.append(dict(label='Recommended',items=items))
        except MediaError as error:errors.append(str(error))
        if errors and not sections:raise MediaError('Collections are unavailable. '+' '.join(errors))
        return dict(sections=sections)

    def anime_episode_metadata(self,mal_id,airing=False):
        key='anime:episode_metadata:v1:'+str(mal_id)
        cached=self.get(key,86400 if airing else 86400*7)
        if cached and (cached.get('available') or self.get(key,86400)):
            return cached.get('episodes') or {}
        episodes={}; available=False
        try:
            mapping=http(f'{ANIMAP}/api/v1/map/mal/{int(mal_id)}',timeout=8)
            sources=mapping.get('sources') or []
            mal_source=rf'https://myanimelist\.net/anime/{int(mal_id)}(?:/[^?#]*)?/?'
            if any(re.fullmatch(mal_source,str(source)) for source in sources):
                kitsu_ids={match[1] for source in sources
                           if (match:=re.fullmatch(r'https://kitsu\.(?:app|io)/anime/(\d+)/?',str(source)))}
                if len(kitsu_ids)==1:
                    data=http(f'{ANIMAP}/api/kitsu/{next(iter(kitsu_ids))}/episodes',timeout=8)
                    rows=data.get('episodes') or []
                    if isinstance(rows,list):
                        duplicates=set()
                        for row in rows:
                            if not isinstance(row,dict):continue
                            number=row.get('number')
                            if not isinstance(number,int) or number<=0 or number>10000:continue
                            number=str(number)
                            if number in duplicates:continue
                            if number in episodes:
                                episodes.pop(number)
                                duplicates.add(number)
                                continue
                            name=row.get('title_en_us') or row.get('title_en_jp') or row.get('canonical_title') or ''
                            image=row.get('thumbnail') or ''
                            episode=dict(plot=row.get('description') or '',
                                         image=image if str(image).startswith('https://') else '',
                                         date=row.get('airdate') or '')
                            if name:episode['title']=name
                            episodes[number]=episode
        except (MediaError,ValueError,TypeError,AttributeError):
            pass
        available=bool(episodes)
        self.put(key,dict(available=available,episodes=episodes))
        return episodes
    def anime_episodes(self,r):
        title=r['title']; mal_id=title.get('malId') or title['id'].split(':')[-1]
        if title['kind']!='tv':raise MediaError('Anime movies do not have episodes.')
        if r.get('season') is None:return dict(seasons=['1'])
        page=int(str(r.get('page') or 'anime:1').split(':')[-1])
        metadata=self.anime_episode_metadata(mal_id,str(title.get('status') or '').lower()
                                              in ('currently_airing','releasing'))
        count=int(title.get('episodesCount') or 0)
        if count<=0:count=max((int(number) for number in metadata),default=0)
        items=[dict(season='1',number=number,title=f'Episode {number}',plot='',image='')
               |metadata.get(str(number),{})
               for number in range((page-1)*24+1,min(page*24,count)+1)]
        next_page=f'anime:{page+1}' if page*24<count else ''
        return dict(items=items,next=next_page)
    def browse_tmdb(self,kind,q,f,token):
        page=int(str(token).split(':')[-1]) if str(token).startswith('tmdb:') else 1
        params=dict(page=page,include_adult='false')
        if q: params['query']=q
        else:
            sort=SORTS.get(f.get('sort'),SORTS['popular'])
            if kind=='tv': sort=sort.replace('primary_release_date','first_air_date')
            genre=TMDB_GENRES[kind].get(f.get('genre'))
            if f.get('genre') and genre is None: raise MediaError('This genre is unavailable from TMDB. Choose a different genre.')
            params.update(sort_by=sort,with_genres=genre,with_origin_country=f.get('country'),**{'vote_average.gte':f.get('rating'),'vote_count.gte':f.get('votes')})
            date='first_air_date' if kind=='tv' else 'primary_release_date'
            if f.get('minYear'): params[date+'.gte']=str(f['minYear'])+'-01-01'
            if f.get('maxYear'): params[date+'.lte']=str(f['maxYear'])+'-12-31'
        d=self.tmdb(('search/' if q else 'discover/')+kind,**params)
        return [tmdb_title(t,kind) for t in d.get('results',[])],f'tmdb:{page+1}' if page<min(d.get('total_pages',1),500) else ''
    def browse_omdb(self,kind,q,f,token):
        page=int(str(token).split(':')[-1]) if str(token).startswith('omdb:') else 1
        d=self.omdb(s=q,type='series' if kind=='tv' else 'movie',page=page)
        items=[omdb_title(t) for t in d.get('Search',[]) if t.get('imdbID')]
        # OMDb search only supplies identity/poster/year; hydrate only for filters.
        if any(f.get(key) for key in ('genre','country','rating','votes','sort')):
            items=[self.details(dict(title=t)) for t in items]
        return items,f'omdb:{page+1}' if page*10<int(d.get('totalResults',0)) and page<100 else ''
    def details(self,r):
        if str(r['title']['id']).startswith('mal:'):return self.anime_details(r)
        t=r['title']; cached=self.get('detail:'+self.canonical(t['id']),86400)
        if cached and not r.get('refresh'): return cached
        errors=[]; result=None
        if self.config().get('tmdb_key'):
            try:
                t=self.identity(t)
                result=tmdb_title(self.tmdb(f'{t["kind"]}/{t["tmdbId"]}',append_to_response='external_ids,credits,videos'),t['kind'])
                if t.get('imdbId') and not result.get('imdbId'):
                    result['id']=result['imdbId']=t['imdbId']
            except MediaError as error:
                errors.append(str(error))
        if result is None and self.config().get('omdb_key') and t.get('imdbId'):
            try:
                d=self.omdb(i=t['imdbId'],plot='full')
                if d: result=omdb_title(d)
            except MediaError as error:
                errors.append(str(error))
        if result is None:
            raise MediaError('No title details found in configured providers. '+' '.join(errors))
        return self.put('detail:'+self.canonical(t['id']),self.save_title(t|result))
    def artwork(self,r):
        if str(r['title']['id']).startswith('mal:'):return dict(title=r['title'],warnings=[],version=3)
        t=r['title']; cachekey='art:'+self.canonical(t['id']); cached=self.get(cachekey,86400)
        if cached and cached.get('version')==3 and not cached.get('warnings') and not r.get('refresh'): return cached
        result={}; warnings=[]
        def optional(fn):
            try: fn()
            except MediaError as e: warnings.append(str(e))
        if self.config().get('tmdb_key'):
            def tmdb():
                nonlocal t
                t=self.identity(t); result['tmdbId']=t['tmdbId']
                d=self.tmdb(f'{t["kind"]}/{t["tmdbId"]}',append_to_response='images,videos,credits,external_ids',include_image_language='en,null')
                if d.get('external_ids',{}).get('imdb_id'):
                    result['imdbId']=d['external_ids']['imdb_id']
                    t=t|{'imdbId':result['imdbId']}
                images=d.get('images',{}); logos=images.get('logos',[])
                logos.sort(key=lambda x:(x.get('iso_639_1')=='en',x.get('vote_average',0),x.get('width',0)),reverse=True)
                if logos: result['logo']=image_url(logos[0]['file_path'])
                backdrops=images.get('backdrops',[])
                backdrops.sort(key=lambda x:(not x.get('iso_639_1'),x.get('vote_average',0),x.get('width',0)),reverse=True)
                if backdrops: result['backdrop']=image_url(backdrops[0]['file_path'])
                result['screenshots']=[dict(url=image_url(i['file_path']),thumbnail=image_url(i['file_path'],'w300')) for i in backdrops[:12] if i.get('file_path')]
                result['trailers']=tmdb_trailers(d)
                result['cast']=tmdb_credits(d)
            optional(tmdb)
        if not result.get('backdrop') and t.get('backdrop'): result['backdrop']=t['backdrop']
        if self.config().get('omdb_key'):
            def omdb():
                imdb_id=result.get('imdbId') or t.get('imdbId')
                if not imdb_id: return
                d=self.omdb(i=imdb_id,plot='full')
                if not d:return
                mapped=omdb_title(d)
                result['ratings']=merge_ratings(t.get('ratings',[]),result.get('ratings',[]),mapped['ratings'])
                # OMDb cannot supply backdrops/logos or linked people.
                for field in ('plot','poster','runtime','genres'):
                    if not t.get(field) and mapped.get(field): result[field]=mapped[field]
            optional(omdb)
        if self.config().get('mdblist_key') and t.get('imdbId'):
            def mdblist():
                d=http('https://api.mdblist.com/imdb/'+('show' if t['kind']=='tv' else 'movie')+'/'+t['imdbId']+'/',dict(apikey=self.config()['mdblist_key']))
                if d.get('backdrop') or d.get('backdrop_url'): result['backdrop']=d.get('backdrop') or d['backdrop_url']
                result['rottenTomatoesUrl']=d.get('tomatoes_url') or d.get('rt_url') or ''
                result['metacriticUrl']=d.get('metacritic_url') or ''
                result['ratings']=merge_ratings(t.get('ratings',[]),result.get('ratings',[]),[dict(source=x['source'],value=x['value'],url=x.get('url','')) for x in d.get('ratings',[]) if x.get('value') is not None])
            optional(mdblist)
        updated=self.save_title({k:v for k,v in t.items() if k in ('id','kind','imdbId','tmdbId')}|result)
        for field in ('cast','trailers'):
            if field in result: updated[field]=result[field]
        self.put('title:'+updated['id'],updated)
        return self.put(cachekey,dict(title=updated,warnings=warnings,version=3))
    def episodes(self,r):
        if str(r['title']['id']).startswith('mal:'):return self.anime_episodes(r)
        t=r['title']; season=r.get('season'); page=r.get('page','')
        if t['kind']!='tv': raise MediaError('Movies do not have episodes.')
        key='episodes:'+json.dumps([t['id'],season,page]); cached=self.get(key,3600)
        if cached:return cached
        try:
            t=self.identity(t)
            if season is None:
                d=self.tmdb(f'tv/{t["tmdbId"]}')
                return self.put(key,dict(seasons=[str(s['season_number']) for s in d.get('seasons',[])]))
            d=self.tmdb(f'tv/{t["tmdbId"]}/season/{int(season)}')
            result=dict(items=[dict(season=str(season),number=e['episode_number'],title=e.get('name',''),plot=e.get('overview',''),image=image_url(e.get('still_path'),'w300'),rating=e.get('vote_average')) for e in d.get('episodes',[])],next='')
        except MediaError:
            if not self.config().get('omdb_key') or not t.get('imdbId'): raise
            d=self.omdb(i=t['imdbId'],**({'Season':season} if season is not None else {}))
            if season is None:
                count=d.get('totalSeasons','0')
                return self.put(key,dict(seasons=[str(n) for n in range(1,int(count)+1)] if str(count).isdigit() else []))
            result=dict(items=[dict(season=str(season),number=int(e['Episode']),title=e.get('Title',''),plot='',image='',date=e.get('Released',''),rating=e.get('imdbRating') if e.get('imdbRating')!='N/A' else None) for e in d.get('Episodes',[])],next='')
        return self.put(key,result)
    def watch(self,r):
        t=r['title']; key=self.config().get('watchmode_key')
        if not key: raise MediaError('Add watchmode_key to media.json to load watch-provider links.')
        if not t.get('imdbId'):t=self.details(r)
        cached=self.get('watch:'+t['id'],86400)
        if cached is not None:return cached
        d=http('https://api.watchmode.com/v1/search/',dict(apiKey=key,search_field='imdb_id',search_value=t.get('imdbId')))
        rows=d.get('title_results',[])
        if not rows:return []
        rows=http(f'https://api.watchmode.com/v1/title/{rows[0]["id"]}/sources/',dict(apiKey=key))
        region=self.config().get('region','US'); preferred=[x for x in rows if x.get('region')==region]
        links={x['web_url']:dict(name=x.get('name','Watch')+' / '+x.get('type',''),url=x['web_url']) for x in (preferred or rows) if x.get('web_url','').startswith(('http://','https://'))}
        return self.put('watch:'+t['id'],list(links.values()))
    def spoilers(self,r):
        t=r['title']; imdb=t.get('imdbId','')
        anime=str(t.get('id','')).startswith('mal:')
        if not anime and not re.fullmatch(r'tt\d+',imdb):
            raise MediaError('An IMDb ID is required for spoilers.')
        key='spoiler:'+str(t['id'] if anime else imdb)
        cached=self.get(key)
        if cached:return cached|{'text':clean_spoiler(cached.get('text',''))}
        if anime:
            names=[t.get('title'),t.get('originalTitle'),*(t.get('aliases') or [])]
            names=[name.strip() for name in names if isinstance(name,str) and name.strip()]
            if not names:return dict(text='No Wikipedia plot is available.')
            results=http('https://en.wikipedia.org/w/api.php',dict(action='query',list='search',
                srsearch=names[0]+' anime',srlimit=10,srnamespace=0,format='json'))
            def normalized(value):return re.sub(r'[^a-z0-9]+',' ',value.lower()).strip()
            aliases={normalized(name) for name in names if normalized(name)}
            def matches(value):
                base=re.sub(r'\s*\([^()]+\)$','',value)
                return normalized(base) in aliases
            page=next((row['title'] for row in results.get('query',{}).get('search',[])
                if matches(row.get('title',''))),None)
            if not page:return dict(text='No Wikipedia plot is available.')
            url='https://en.wikipedia.org/wiki/'+urllib.parse.quote(page.replace(' ','_'))
        else:
            query='SELECT ?article WHERE { ?item wdt:P345 "'+imdb+'". ?article schema:about ?item; schema:isPartOf <https://en.wikipedia.org/>. } LIMIT 1'
            rows=http('https://query.wikidata.org/sparql',dict(query=query,format='json')).get('results',{}).get('bindings',[])
            if not rows:return dict(text='No Wikipedia plot is available.')
            url=rows[0]['article']['value']
            page=urllib.parse.unquote(url.split('/wiki/')[-1])
        params=dict(action='parse',page=page,format='json',formatversion=2)
        sections=http('https://en.wikipedia.org/w/api.php',params|dict(prop='sections')).get('parse',{}).get('sections',[])
        section=next((s['index'] for s in sections if s.get('line','').lower() in ('plot','synopsis','plot synopsis','story')),None)
        if section is None:return dict(text='No Wikipedia plot section is available.')
        raw=http('https://en.wikipedia.org/w/api.php',params|dict(prop='text',section=section)).get('parse',{}).get('text','')
        raw=re.sub(r'<(sup|table|style|h[1-6])\b.*?</\1>','',raw,flags=re.S)
        text=clean_spoiler(html.unescape(re.sub('<[^>]+>','',raw.replace('</p>','\n\n'))))
        return self.put(key,dict(text=text,url=url))
    def person(self,r):
        person=r['person']; id=person.get('id','')
        key='person:v3:'+id; cached=self.get(key,86400)
        if cached:return cached
        result=None
        if id.startswith('nm'):
            found=self.tmdb('find/'+id,external_source='imdb_id').get('person_results',[])
            if not found: raise MediaError('No matching person found in TMDB.')
            id='tmdb:'+str(found[0]['id'])
        if result is None and id.startswith('tmdb:'):
            d=self.tmdb('person/'+id.split(':')[-1],append_to_response='combined_credits')
            combined=d.get('combined_credits',{})
            titles=[tmdb_title(c,c['media_type'])|{'roles':['Actor' if section=='cast' else credit_role(c.get('job') or c.get('department'))]} for section in ('cast','crew') for c in combined.get(section,[]) if c.get('media_type') in ('movie','tv')]
            result=dict(name=d.get('name',''),biography=d.get('biography',''),image=image_url(d.get('profile_path'),'w185'),credits=titles)
        if result is None: raise MediaError('Person details are unavailable.')
        titles={}
        for title in result['credits']:
            existing=titles.setdefault(title['id'],title|{'roles':[]})
            existing['roles']=sorted(set(existing['roles']+[role for role in title.get('roles',[]) if role]))
        result['credits']=sorted(titles.values(),key=lambda t:int(t.get('year') or 0),reverse=True)
        return self.put(key,result)
    def launch_target(self,url):
        # A provider webpage and a playable media URL are distinct source types.
        direct=urllib.parse.urlparse(url).path.lower().endswith(('.mp4','.mkv','.webm','.m3u8','.mpd','.avi','.mov'))
        player=self.config().get('player',['mpv'])
        if direct:
            if not isinstance(player,list) or not player or not all(isinstance(x,str) for x in player):raise MediaError('player must be a nonempty JSON array of command arguments.')
            if not shutil.which(player[0]):raise MediaError('Configured media player is not installed: '+player[0])
            return dict(type='direct',command=player+['--',url])
        return dict(type='web',url=url)
    def handle(self,r):
        op=r['op']
        if op=='anime_genres':return self.anime_genres()
        if op=='anime_entry':return self.anime_entry(r)
        if op=='collections':return self.collections(r)
        if op=='local_titles':
            items=[]
            for local in self.local.list(r.get('kind','movie')):
                saved=self.get('title:'+self.canonical(local['id'])) or {}
                items.append(local | saved | {'local':True,'localPath':local['localPath'],
                                                'torrent':local['torrent']})
            return dict(items=items,next='')
        if op=='local_posters':
            missing=[title for title in self.handle({'op':'local_titles','kind':r.get('kind','movie')})['items']
                     if not title.get('poster')]
            def enrich(title):
                try:
                    result=self.details({'title':title})
                    if not result.get('poster'):
                        result=self.artwork({'title':result})['title']
                    return {'id':title['id'],'poster':result.get('poster') or ''}
                except MediaError:
                    return {'id':title['id'],'poster':''}
            with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
                return [item for item in pool.map(enrich, missing) if item['poster']]
        if op=='local_files':
            return self.local.files(r['title'])
        if op=='snapshot':
            if r.get('favorites'): return self.browse(r)
            key=self.browse_key(r.get('kind','movie'),r.get('query','').strip(),r.get('filters',{}),'')
            return self.get(key)
        if op=='personal':return self.personal(r['title']['id'])
        if op=='save':
            t=self.save_title(r['title']); id=self.canonical(t['id'])
            with self.db() as db:
                db.execute('BEGIN IMMEDIATE')
                row=db.execute('SELECT value FROM personal WHERE id=?',(id,)).fetchone()
                p=json.loads(row[0]) if row else dict(favorite=False,note='',url='')
                p.update({k:v for k,v in r['values'].items() if k in ('favorite','note','url')})
                db.execute('INSERT OR REPLACE INTO personal VALUES (?,?)',(id,json.dumps(p)))
            return p
        if op=='play':
            t=r['title']
            if str(t['id']).startswith('mal:'):
                sources=self.config().get('anime_sources',[])
                index=r.get('provider',0)
                if not isinstance(index,int) or index<0 or index>=len(sources):
                    raise MediaError('Choose an available anime source in media.json.')
                player=self.config().get('player',['mpv'])
                if (not isinstance(player,list) or not player or not all(isinstance(x,str) for x in player)
                        or Path(player[0]).name!='mpv' or not shutil.which(player[0])):
                    raise MediaError('Anime streams require mpv in the player setting.')
                try:
                    stream=anime_sources.resolve(sources[index],t,r.get('episode') or 1,r.get('mode','sub'))
                except anime_sources.SourceError as error:
                    raise MediaError(str(error)) from None
                command=player+['--referrer='+stream['referer']]
                if stream['subtitle']:command.append('--sub-file='+stream['subtitle'])
                return dict(type='direct',command=command+['--',stream['url']])
            if not r.get('online'):
                files=self.local.files(t)
                chosen=next((f for f in files if t['kind']=='movie' or
                             (r.get('season') is not None and r.get('episode') is not None and
                              int(f['season'])==int(r['season']) and int(f['episode'])==int(r['episode']))),None)
                if chosen:
                    player=self.config().get('player',['mpv'])
                    if not isinstance(player,list) or not player or not all(isinstance(x,str) for x in player):
                        raise MediaError('player must be a nonempty JSON array of command arguments.')
                    if not shutil.which(player[0]):raise MediaError('Configured media player is not installed: '+player[0])
                    return dict(type='direct',command=player+['--',chosen['path']])
            custom=None if r.get('online') else self.personal(t['id']).get('url'); providers=self.playback_providers(t['kind'])
            index=r.get('provider',0)
            if not custom and providers and (not isinstance(index,int) or index<0 or index>=len(providers)):
                raise MediaError('Playback provider is unavailable. Reopen the module to reload providers.')
            template=custom or (providers[index][1] if providers else '')
            if '{tmdbId}' in template and not t.get('tmdbId'):t=self.save_title(self.identity(t))
            if custom and '{' not in custom:
                if urllib.parse.urlparse(custom).scheme not in ('http','https'): raise MediaError('Custom URLs must use http or https.')
                return self.launch_target(custom)
            return self.launch_target(template_url(template,t,r.get('season'),r.get('episode')))
        if op=='init':
            providers=self.playback_providers(r.get('kind','movie'))
            return dict(configPath=str(self.config_path),providers=[name for name,url in providers],
                        episodeProviders=['{season}' in url or '{episode}' in url for name,url in providers],
                        animeProviders=[source['name'] for source in self.config().get('anime_sources',[])],
                        genres=list(TMDB_GENRES[r.get('kind','movie')]))
        if op not in ('browse','details','artwork','episodes','watch','spoilers','person'):raise MediaError('Unknown request.')
        return getattr(self,op)(r)

def main():
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from services.worker import serve
    backend = Backend()
    serve(backend.handle, errors=(MediaError,), latest=("browse", "details", "artwork", "personal", "episodes", "person", "watch", "spoilers"), controls=("save",))


if __name__=='__main__':main()
