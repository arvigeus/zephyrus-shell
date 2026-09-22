#!/usr/bin/env python3
"""Owned JSON-lines media worker. Metadata API keys stay in this process."""
import concurrent.futures
from contextlib import contextmanager
import hashlib
import html
import json
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

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'zephyrus-shell/media.json'
DATA = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'zephyrus-shell/media'
CACHE = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'zephyrus-shell/media'
IMDB = 'https://api.imdbapi.dev'
TMDB = 'https://api.themoviedb.org/3'
OMDB = 'https://www.omdbapi.com/'
GENRES = {'Action':28,'Adventure':12,'Animation':16,'Comedy':35,'Crime':80,'Documentary':99,'Drama':18,'Family':10751,'Fantasy':14,'History':36,'Horror':27,'Music':10402,'Mystery':9648,'Romance':10749,'Sci-Fi':878,'Thriller':53,'War':10752,'Western':37}
SORTS = {'popular':('POPULARITY','DESC','popularity.desc'), 'rating':('USER_RATING','DESC','vote_average.desc'), 'votes':('USER_RATING_COUNT','DESC','vote_count.desc'), 'newest':('RELEASE_DATE','DESC','primary_release_date.desc'), 'oldest':('RELEASE_DATE','ASC','primary_release_date.asc')}

class MediaError(Exception):
    def __init__(self, message, retryable=True):
        super().__init__(message)
        self.retryable = retryable

def http(url, params=None):
    if params:
        url += '?' + urllib.parse.urlencode({k:v for k,v in params.items() if v is not None and v != ''}, doseq=True)
    try:
        req = urllib.request.Request(url, headers={'User-Agent':'ZephyrusMedia/1.0', 'Accept':'application/json'})
        with urllib.request.urlopen(req, timeout=15) as response:
            return json.load(response)
    except urllib.error.HTTPError as e:
        e.close()
        raise MediaError(f'{urllib.parse.urlparse(url).hostname} returned HTTP {e.code}. Try again later.', retryable=e.code == 429 or e.code >= 500) from None
    except (OSError, ValueError):
        raise MediaError(f'Cannot reach {urllib.parse.urlparse(url).hostname}. Check your connection and configuration.') from None

def image_url(path, size='original'):
    return 'https://image.tmdb.org/t/p/' + size + path if path else ''

def imdb_title(d):
    rating = d.get('rating') or {}
    return dict(id=d['id'], imdbId=d['id'], kind='tv' if d.get('type') in ('tvSeries','tvMiniSeries','TV_SERIES','TV_MINI_SERIES') else 'movie', title=d.get('primaryTitle',''), year=d.get('startYear'), poster=(d.get('primaryImage') or {}).get('url',''), plot=d.get('plot',''), runtime=round((d.get('runtimeSeconds') or 0)/60), genres=d.get('genres',[]), countries=d.get('originCountries',d.get('countriesOfOrigin',[])), rating=rating.get('aggregateRating'), votes=int(rating.get('voteCount') or 0), ratings=[{'source':'IMDb','value':rating['aggregateRating']}] if rating.get('aggregateRating') else [], cast=[dict(id=p.get('id'),name=p.get('displayName',''),role=role) for field,role in [('directors','Director'),('writers','Writer'),('stars','Cast')] for p in d.get(field,[])])

def tmdb_title(d, kind):
    imdb = d.get('imdb_id') or d.get('external_ids',{}).get('imdb_id')
    return dict(id=imdb or f'tmdb:{kind}:{d["id"]}',imdbId=imdb or '',tmdbId=d['id'],kind=kind,title=d.get('title') or d.get('name',''),year=(d.get('release_date') or d.get('first_air_date',''))[:4],poster=image_url(d.get('poster_path'),'w500'),backdrop=image_url(d.get('backdrop_path')),plot=d.get('overview',''),runtime=d.get('runtime') or next(iter(d.get('episode_run_time',[])),0),genres=[g['name'] for g in d.get('genres',[])] or [name for name,id in GENRES.items() if id in d.get('genre_ids',[])],countries=d.get('production_countries',[]),rating=d.get('vote_average'),votes=d.get('vote_count',0),ratings=[{'source':'TMDB','value':round(d.get('vote_average',0),1)}])

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

def choose_backdrop(images):
    candidates=[i for i in images if i.get('url') and i.get('width',0)>i.get('height',0)*1.35]
    return max(candidates,key=lambda i:(any(w in i.get('type','').lower() for w in ('promo','backdrop','art')),min(i.get('width',0),3840)),default={}).get('url','')

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
        providers=config.get('providers',[])
        if not isinstance(providers,list): raise MediaError('providers must be a JSON array.')
        for provider in providers:
            if (not isinstance(provider,dict) or not isinstance(provider.get('name'),str)
                    or not provider['name'].strip()
                    or not any(isinstance(provider.get(key),str) and provider[key].strip() for key in ('movie_url','series_url','url'))
                    or any(key in provider and not isinstance(provider[key],str) for key in ('movie_url','series_url','url'))):
                raise MediaError('Each playback provider needs a name and movie_url and/or series_url strings (legacy url is also accepted).')
        return config
    def playback_providers(self,kind):
        key='series_url' if kind=='tv' else 'movie_url'
        return [(p['name'],p.get(key,p.get('url',''))) for p in self.config().get('providers',[]) if p.get(key,p.get('url','')).strip()]
    def imdb(self,path,params=None):
        health=self.get('provider:imdb') or {}
        if health.get('retryAfter',0)>time.time():
            raise MediaError('IMDbApi is temporarily unavailable; using configured alternatives.')
        try:
            return http(IMDB+path,params)
        except MediaError as error:
            if error.retryable: self.put('provider:imdb',dict(retryAfter=time.time()+300))
            raise
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
        merged=old|{k:v for k,v in t.items() if v is not None and v!='' and v!=[]}
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
    def browse(self,r):
        kind=r.get('kind','movie'); q=r.get('query','').strip(); f=r.get('filters',{}); token=r.get('page','')
        if r.get('favorites'):
            with self.db() as db: rows=db.execute('SELECT id,value FROM personal').fetchall()
            titles=[self.get('title:'+id) for id,p in rows if json.loads(p).get('favorite')]
            return dict(items=[t for t in titles if t and t['kind']==kind and q.lower() in t['title'].lower()],next='')
        key='browse:'+json.dumps([kind,q,f,token],sort_keys=True)
        cached=self.get(key,900)
        if cached and not r.get('refresh'): return cached
        errors=[]
        candidates=[('imdb',self.browse_imdb),('tmdb',self.browse_tmdb)]
        if q: candidates.append(('omdb',self.browse_omdb))
        current=str(token).split(':')[0] if str(token).startswith(('tmdb:','omdb:')) else ''
        if current: candidates=[candidate for candidate in candidates if candidate[0]==current]
        for name,provider in candidates:
            if name!='imdb' and not self.config().get(name+'_key'): continue
            try:
                items,next_token=provider(kind,q,f,token)
                break
            except MediaError as error: errors.append(str(error))
        else:
            stale=self.get(key)
            if stale: return stale | {'warning':'Offline: showing the saved catalogue; configured providers are unavailable.'}
            if not q and self.config().get('omdb_key') and not self.config().get('tmdb_key'):
                raise MediaError('IMDbApi is unavailable. OMDb supports title search, but discovery requires a TMDB key. Search for a title or add tmdb_key to media.json.')
            raise MediaError('No catalogue provider is available. '+' '.join(errors))
        items=[t for t in items if t['kind']==kind]
        if not q and not f.get('maxYear'):
            items=[t for t in items if int(t.get('year') or 0)<=time.localtime().tm_year]
        if q and f.get('country'):
            items=[t for t in items if f['country'].upper() in [c.upper() if isinstance(c,str) else (c.get('code') or c.get('iso_3166_1') or '').upper() for c in t.get('countries',[])]]
        if q:
            items=[t for t in items if (not f.get('genre') or f['genre'] in t.get('genres',[])) and (not f.get('minYear') or int(t.get('year') or 0)>=int(f['minYear'])) and (not f.get('maxYear') or int(t.get('year') or 9999)<=int(f['maxYear'])) and (not f.get('rating') or float(t.get('rating') or 0)>=float(f['rating'])) and (not f.get('votes') or int(t.get('votes') or 0)>=int(f['votes']))]
            sort=f.get('sort'); field={'rating':'rating','votes':'votes','newest':'year','oldest':'year'}.get(sort)
            if field: items.sort(key=lambda t:float(t.get(field) or 0),reverse=sort!='oldest')
        return self.put(key,dict(items=[self.save_title(t) for t in items],next=next_token))
    def browse_imdb(self,kind,q,f,token):
        if q:
            d=self.imdb('/search/titles',dict(query=q,limit=50))
        else:
            params=dict(types='TV_SERIES' if kind=='tv' else 'MOVIE',pageToken=token,genres=f.get('genre'),countryCodes=f.get('country'),startYear=f.get('minYear'),endYear=f.get('maxYear'),minAggregateRating=f.get('rating'),minVoteCount=f.get('votes'))
            if f.get('sort') in SORTS:
                sort=SORTS[f['sort']];params.update(sortBy='SORT_BY_'+sort[0],sortOrder=sort[1])
            d=self.imdb('/titles',params)
        return [imdb_title(t) for t in d.get('titles',[])],d.get('nextPageToken','') if not q else ''
    def browse_tmdb(self,kind,q,f,token):
        page=int(str(token).split(':')[-1]) if str(token).startswith('tmdb:') else 1
        params=dict(page=page,include_adult='false')
        if q: params['query']=q
        else:
            sort=SORTS.get(f.get('sort'),SORTS['popular'])[2]
            if kind=='tv': sort=sort.replace('primary_release_date','first_air_date')
            genre=GENRES.get(f.get('genre'))
            if kind=='tv': genre={'Action':10759,'Adventure':10759,'Sci-Fi':10765,'Fantasy':10765,'War':10768}.get(f.get('genre'),genre)
            if f.get('genre') and genre is None: raise MediaError('This genre is unavailable from TMDB fallback. Choose a different genre.')
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
        t=r['title']; cached=self.get('detail:'+self.canonical(t['id']),86400)
        if cached and not r.get('refresh'): return cached
        errors=[]
        try:
            if not t.get('imdbId'): raise MediaError('IMDb ID is unavailable.')
            result=imdb_title(self.imdb('/titles/'+t['imdbId']))
        except MediaError as error:
            errors.append(str(error))
            try:
                t=self.identity(t)
                result=tmdb_title(self.tmdb(f'{t["kind"]}/{t["tmdbId"]}',append_to_response='external_ids,credits,videos'),t['kind'])
            except MediaError as error:
                errors.append(str(error))
                if self.config().get('omdb_key') and t.get('imdbId'):
                    d=self.omdb(i=t['imdbId'],plot='full')
                    if not d: raise MediaError('No title details found in configured providers.')
                    result=omdb_title(d)
                else:
                    raise MediaError('No details provider is available. '+' '.join(errors))
        return self.put('detail:'+self.canonical(t['id']),self.save_title(t|result))
    def artwork(self,r):
        t=r['title']; cachekey='art:'+self.canonical(t['id']); cached=self.get(cachekey,86400)
        if cached and cached.get('version')==2 and not cached.get('warnings') and not r.get('refresh'): return cached
        result={}; warnings=[]
        def optional(fn):
            try: fn()
            except MediaError as e: warnings.append(str(e))
        def imdb():
            if t.get('imdbId'):
                result['backdrop']=choose_backdrop(self.imdb('/titles/'+t['imdbId']+'/images',dict(pageSize=50)).get('images',[]))
        def credits():
            if t.get('imdbId'):
                rows=[]; page=''; seen=set()
                while True:
                    data=self.imdb('/titles/'+t['imdbId']+'/credits',dict(pageSize=50,pageToken=page))
                    rows.extend(data.get('credits',[]))
                    page=data.get('nextPageToken','')
                    if not page or page in seen: break
                    seen.add(page)
                result['cast']=[dict(id=c.get('name',{}).get('id',''),name=c.get('name',{}).get('displayName',''),role=' / '.join([c.get('category','')]+c.get('characters',[])),job=c.get('category',''),department='Acting' if c.get('category','').lower() in ('actor','actress','cast') else 'Crew',image=(c.get('name',{}).get('primaryImage') or {}).get('url','')) for c in rows]
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
                result['trailers']=tmdb_trailers(d)
                result['cast']=tmdb_credits(d)
            optional(tmdb)
        # TMDB already supplies linked credits and a backdrop in one response.
        # Fetch IMDb's paginated credits/images only when those fields are missing.
        if not result.get('backdrop'):
            if t.get('backdrop'): result['backdrop']=t['backdrop']
            else: optional(imdb)
        if not result.get('cast'): optional(credits)
        imdb_errors=len(warnings)
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
        if result.get('backdrop') and result.get('cast'):
            warnings=warnings[imdb_errors:]
        updated=self.save_title({k:v for k,v in t.items() if k in ('id','kind','imdbId','tmdbId')}|result)
        for field in ('cast','trailers'):
            if field in result: updated[field]=result[field]
        self.put('title:'+updated['id'],updated)
        return self.put(cachekey,dict(title=updated,warnings=warnings,version=2))
    def episodes(self,r):
        t=r['title']; season=r.get('season'); page=r.get('page','')
        if t['kind']!='tv': raise MediaError('Movies do not have episodes.')
        key='episodes:'+json.dumps([t['id'],season,page]); cached=self.get(key,3600)
        if cached:return cached
        try:
            if not t.get('imdbId'): raise MediaError('TMDB title')
            if season is None:
                d=self.imdb('/titles/'+t['imdbId']+'/seasons')
                return self.put(key,dict(seasons=[str(s['season']) for s in d.get('seasons',[])]))
            d=self.imdb('/titles/'+t['imdbId']+'/episodes',dict(season=season,pageToken=page,pageSize=20))
            items=[dict(season=str(e.get('season',season)),number=e.get('episodeNumber'),title=e.get('title',''),plot=e.get('plot',''),image=(e.get('primaryImage') or {}).get('url',''),rating=(e.get('rating') or {}).get('aggregateRating')) for e in d.get('episodes',[])]
            result=dict(items=items,next=d.get('nextPageToken',''))
        except MediaError:
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
        if not re.fullmatch(r'tt\d+',imdb):raise MediaError('An IMDb ID is required for spoilers.')
        cached=self.get('spoiler:'+imdb)
        if cached:return cached|{'text':clean_spoiler(cached.get('text',''))}
        query='SELECT ?article WHERE { ?item wdt:P345 "'+imdb+'". ?article schema:about ?item; schema:isPartOf <https://en.wikipedia.org/>. } LIMIT 1'
        rows=http('https://query.wikidata.org/sparql',dict(query=query,format='json')).get('results',{}).get('bindings',[])
        if not rows:return dict(text='No Wikipedia plot is available.')
        title=urllib.parse.unquote(rows[0]['article']['value'].split('/wiki/')[-1]); params=dict(action='parse',page=title,format='json',formatversion=2)
        sections=http('https://en.wikipedia.org/w/api.php',params|dict(prop='sections')).get('parse',{}).get('sections',[])
        section=next((s['index'] for s in sections if s.get('line','').lower() in ('plot','synopsis','plot synopsis','story')),None)
        if section is None:return dict(text='No Wikipedia plot section is available.')
        raw=http('https://en.wikipedia.org/w/api.php',params|dict(prop='text',section=section)).get('parse',{}).get('text','')
        raw=re.sub(r'<(sup|table|style|h[1-6])\b.*?</\1>','',raw,flags=re.S)
        text=clean_spoiler(html.unescape(re.sub('<[^>]+>','',raw.replace('</p>','\n\n'))))
        return self.put('spoiler:'+imdb,dict(text=text,url=rows[0]['article']['value']))
    def person(self,r):
        person=r['person']; id=person.get('id','')
        key='person:v2:'+id; cached=self.get(key,86400)
        if cached:return cached
        result=None
        if id.startswith('nm'):
            try:
                d=self.imdb('/names/'+id)
                credits=[]; page=''; seen=set()
                while True:
                    data=self.imdb('/names/'+id+'/filmography',dict(pageSize=50,pageToken=page))
                    credits.extend(data.get('credits',[]))
                    page=data.get('nextPageToken','')
                    if not page or page in seen: break
                    seen.add(page)
                titles=[imdb_title(c['title'])|{'roles':[credit_role(c.get('category') or c.get('job'))]} for c in credits if c.get('title',{}).get('id')]
                result=dict(name=d.get('displayName',person.get('name','')),biography=d.get('biography',''),image=(d.get('primaryImage') or {}).get('url',''),credits=titles)
            except MediaError:
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
        if op=='snapshot':
            if r.get('favorites'): return self.browse(r)
            key='browse:'+json.dumps([r.get('kind','movie'),r.get('query','').strip(),r.get('filters',{}),''],sort_keys=True)
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
            t=r['title']; custom=None if r.get('online') else self.personal(t['id']).get('url'); providers=self.playback_providers(t['kind'])
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
            return dict(configPath=str(self.config_path),providers=[name for name,url in providers],episodeProviders=['{season}' in url or '{episode}' in url for name,url in providers])
        if op not in ('browse','details','artwork','episodes','watch','spoilers','person'):raise MediaError('Unknown request.')
        return getattr(self,op)(r)

def main():
    backend=Backend(); lock=threading.Lock(); latest={}
    superseded_ops={"browse","details","artwork","personal","episodes","person","watch","spoilers"}
    def run(r):
        try:
            if r.get('op') in superseded_ops and latest.get(r['op']) != r.get('id'):
                raise MediaError('Request superseded.')
            result=dict(id=r.get('id'),op=r.get('op'),result=backend.handle(r))
        except MediaError as e: result=dict(id=r.get('id'),op=r.get('op'),error=str(e))
        except Exception: result=dict(id=r.get('id'),op=r.get('op'),error='The media request could not be completed. Check the configuration or retry.')
        with lock: print(json.dumps(result),flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for line in sys.stdin:
            try:r=json.loads(line)
            except ValueError:continue
            latest[r.get('op')]=r.get('id')
            pool.submit(run,r)
if __name__=='__main__':main()
