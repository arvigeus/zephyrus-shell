import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('media_backend', Path(__file__).resolve().parents[1] / 'media/backend.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class MediaTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.backend = m.Backend(root/'config/media.json',root/'data',root/'cache')
        self.movie = dict(id='tt123',imdbId='tt123',kind='movie',title='Movie')
    def configure(self, value):
        self.backend.config_path.write_text(json.dumps(value))
    def test_person_filmography_pages_and_sorts_newest_first(self):
        responses = [
            {'displayName':'Actor'},
            {'credits':[{'title':{'id':'tt2','primaryTitle':'Later','startYear':2020}}], 'nextPageToken':'older'},
            {'credits':[{'title':{'id':'tt1','primaryTitle':'First','startYear':1990,'primaryImage':{'url':'https://example.org/poster'}}}, {'title':{'id':'tt2','primaryTitle':'Later','startYear':2020}}]},
        ]
        with patch.object(self.backend,'imdb',side_effect=responses) as api:
            result=self.backend.person({'person':{'id':'nm1'}})
        self.assertEqual([t['id'] for t in result['credits']],['tt2','tt1'])
        self.assertEqual(result['credits'][1]['poster'],'https://example.org/poster')
        self.assertEqual(api.call_args.args[1]['pageToken'],'older')

    def test_person_combines_cast_and_crew_roles_without_duplicate_titles(self):
        data={'name':'Person','combined_credits':{
            'cast':[{'id':1,'media_type':'movie','title':'Both roles','release_date':'2024-01-01'}],
            'crew':[{'id':1,'media_type':'movie','title':'Both roles','release_date':'2024-01-01','job':'Director'},
                    {'id':2,'media_type':'movie','title':'Crew only','release_date':'2025-01-01','job':'Executive Producer'}]}}
        with patch.object(self.backend,'tmdb',return_value=data):
            result=self.backend.person({'person':{'id':'tmdb:10'}})
        self.assertEqual([t['title'] for t in result['credits']],['Crew only','Both roles'])
        self.assertEqual(result['credits'][1]['roles'],['Actor','Director'])
        self.assertEqual(result['credits'][0]['roles'],['Producer'])

    def test_separate_kinds_and_pagination(self):
        with patch.object(m,'http',return_value={'titles':[{'id':'tt123','type':'movie','primaryTitle':'Film'},{'id':'tt456','type':'tvSeries','primaryTitle':'Series'}],'nextPageToken':'next'}) as api:
            result=self.backend.browse(dict(kind='movie'))
            self.assertEqual([t['id'] for t in result['items']],['tt123'])
            self.assertEqual(result['next'],'next')
            self.assertEqual(api.call_args.args[1]['types'],'MOVIE')
    def test_tmdb_fallback_continues_same_provider(self):
        self.configure({'tmdb_key':'test-secret'})
        def api(url,params):
            if url.startswith(m.IMDB): raise m.MediaError('offline')
            return {'results':[{'id':12,'title':'Fallback'}],'total_pages':3}
        with patch.object(m,'http',side_effect=api) as request:
            first=self.backend.browse({'kind':'movie'})
            self.assertEqual(first['next'],'tmdb:2')
            self.backend.browse({'kind':'movie','page':'tmdb:2'})
            self.assertEqual(request.call_args.args[1]['page'],2)
    def test_favorites_and_notes_survive_identity_merge_and_refresh(self):
        t=dict(id='tmdb:movie:12',tmdbId=12,kind='movie',title='Film')
        self.backend.handle(dict(op='save',title=t,values={'favorite':True,'note':'Keep','url':'https://example.org/play'}))
        canonical=self.backend.save_title(t|{'imdbId':'tt123'})
        self.assertEqual(canonical['id'],'tt123')
        self.assertEqual(self.backend.personal('tt123')['note'],'Keep')
        self.assertEqual(self.backend.personal(t['id'])['url'],'https://example.org/play')
        self.backend.save_title(canonical|{'plot':'Refreshed'})
        self.assertTrue(self.backend.personal('tt123')['favorite'])
        self.assertEqual(len(self.backend.browse({'kind':'movie','favorites':True})['items']),1)
        self.assertEqual(self.backend.browse({'kind':'tv','favorites':True})['items'],[])
    def test_optional_enrichment_failure_preserves_details(self):
        self.backend.save_title(self.movie|{'plot':'Hydrated plot','cast':[{'name':'Actor'}]})
        with patch.object(m,'http',side_effect=m.MediaError('offline')):
            result=self.backend.artwork({'title':self.movie})
        self.assertEqual(result['title']['plot'],'Hydrated plot')
        self.assertTrue(result['warnings'])
    def test_artwork_prefers_landscape_promotional(self):
        items=[{'url':'portrait','width':800,'height':1200,'type':'promo'},{'url':'still','width':1920,'height':1080,'type':'still'},{'url':'art','width':1600,'height':900,'type':'promotional'}]
        self.assertEqual(m.choose_backdrop(items),'art')
        self.assertEqual(m.choose_backdrop(items[:1]),'')
    def test_episode_template_and_invalid_input(self):
        title=self.movie|{'kind':'tv','tmdbId':42}
        self.assertEqual(m.template_url('https://example.org/{kind:film|show}/{tmdbId}/{season}/{episode}',title,2,3),'https://example.org/show/42/2/3')
        for template in ('https://example.org/{unknown}','javascript:bad','https://example.org/{episode}'):
            with self.assertRaises(m.MediaError):m.template_url(template,title)
        with self.assertRaises(m.MediaError):self.backend.episodes({'title':self.movie})
    def test_custom_url_is_used_verbatim(self):
        self.backend.handle(dict(op='save',title=self.movie,values={'url':'https://example.org/watch?id=42'}))
        result=self.backend.handle(dict(op='play',title=self.movie))
        self.assertEqual(result['url'],'https://example.org/watch?id=42')
    def test_config_secrets_do_not_cross_ui_boundary(self):
        self.configure({'tmdb_key':'secret','providers':[{'name':'Example','url':'https://example.org/{imdbId}?secret=private'}]})
        output=json.dumps(self.backend.handle({'op':'init'}))
        self.assertNotIn('secret',output)
        self.assertNotIn('private',output)
    def test_error_redacts_credentials(self):
        from urllib.error import HTTPError
        with patch.object(m.urllib.request,'urlopen',side_effect=HTTPError('https://example.org/?api_key=secret',403,'secret',{},None)):
            with self.assertRaises(m.MediaError) as raised:m.http('https://example.org/',{'api_key':'secret'})
        self.assertNotIn('secret',str(raised.exception))
    def test_direct_stream_player_arguments_are_not_shell_code(self):
        self.configure({'player':['mpv','--fullscreen']})
        with patch.object(m.shutil,'which',return_value='/usr/bin/mpv'):
            target=self.backend.launch_target('https://example.org/stream.m3u8?token=$(echo secret)')
        self.assertEqual(target['type'],'direct')
        self.assertEqual(target['command'],['mpv','--fullscreen','--','https://example.org/stream.m3u8?token=$(echo secret)'])
        self.assertEqual(self.backend.launch_target('https://example.org/watch/123')['type'],'web')
    def test_provider_config_requires_documented_objects(self):
        self.configure({'providers':['https://example.org/{imdbId}']})
        with self.assertRaisesRegex(m.MediaError,'name and movie_url'):
            self.backend.config()
        self.configure({'providers':[{'name':'Example','url':'https://example.org/{imdbId}'}]})
        self.assertEqual(self.backend.handle({'op':'init'})['providers'],['Example'])
    def test_separate_movie_and_series_provider_urls(self):
        self.configure({'providers':[
            {'name':'Movies only','movie_url':'https://example.org/film/{imdbId}'},
            {'name':'Both','movie_url':'https://example.net/movie/{tmdbId}',
             'series_url':'https://example.net/show/{imdbId}/{season}/{episode}'},
        ]})
        self.assertEqual(self.backend.handle({'op':'init','kind':'movie'})['providers'],['Movies only','Both'])
        series=self.backend.handle({'op':'init','kind':'tv'})
        self.assertEqual(series['providers'],['Both'])
        self.assertEqual(series['episodeProviders'],[True])
        result=self.backend.handle({'op':'play','online':True,'provider':0,'title':self.movie|{'kind':'tv'},'season':2,'episode':7})
        self.assertEqual(result['url'],'https://example.net/show/tt123/2/7')
        result=self.backend.handle({'op':'play','online':True,'provider':1,'title':self.movie|{'tmdbId':42}})
        self.assertEqual(result['url'],'https://example.net/movie/42')
        with self.assertRaisesRegex(m.MediaError,'provider is unavailable'):
            self.backend.handle({'op':'play','online':True,'provider':-1,'title':self.movie})
        with self.assertRaisesRegex(m.MediaError,'season is unavailable'):
            self.backend.handle({'op':'play','online':True,'provider':0,'title':self.movie|{'kind':'tv'}})

    def test_artwork_skips_redundant_imdb_requests_when_tmdb_supplies_fields(self):
        self.configure({'tmdb_key':'test'})
        data={'images':{'backdrops':[{'file_path':'/backdrop.jpg'}]},
              'credits':{'cast':[{'id':1,'name':'Actor','character':'Lead'}]}}
        with patch.object(self.backend,'tmdb',return_value=data), patch.object(self.backend,'imdb') as imdb:
            result=self.backend.artwork({'title':self.movie|{'tmdbId':42}})
        imdb.assert_not_called()
        self.assertEqual(result['title']['cast'][0]['name'],'Actor')
        self.assertTrue(result['title']['backdrop'].endswith('/backdrop.jpg'))

    def test_outage_cooldown_is_shared_across_worker_restarts_and_expires(self):
        with patch.object(m,'http',side_effect=m.MediaError('offline')) as api:
            for backend in [self.backend,m.Backend(self.backend.config_path,self.backend.data,self.backend.cache)]:
                with self.assertRaises(m.MediaError):backend.imdb('/titles')
            self.assertEqual(api.call_count,1)
        self.backend.put('provider:imdb',{'retryAfter':0})
        with patch.object(m,'http',return_value={'titles':[]}) as api:
            self.backend.imdb('/titles')
            self.assertEqual(api.call_count,1)
    def test_not_found_does_not_disable_imdb(self):
        with patch.object(m,'http',side_effect=m.MediaError('not found',retryable=False)) as api:
            for path in ['/titles/tt123','/titles/tt456']:
                with self.assertRaises(m.MediaError):self.backend.imdb(path)
            self.assertEqual(api.call_count,2)
    def test_omdb_search_fallback_and_pagination(self):
        self.configure({'tmdb_key':'tmdb-secret','omdb_key':'omdb-secret'})
        def api(url,params):
            if url!=m.OMDB: raise m.MediaError('offline')
            self.assertEqual(params['type'],'series')
            return {'Response':'True','Search':[{'imdbID':'tt456','Title':'Series','Type':'series','Year':'2019–2023','Poster':'N/A'}],'totalResults':'22'}
        with patch.object(m,'http',side_effect=api) as request:
            result=self.backend.browse({'kind':'tv','query':'Series'})
            self.assertEqual(result['next'],'omdb:2')
            self.assertEqual(result['items'][0]['kind'],'tv')
            self.assertEqual(result['items'][0].get('poster',''),'')
            result=self.backend.browse({'kind':'tv','query':'Series','page':result['next']})
            self.assertEqual(request.call_args.args[1]['page'],2)
            self.assertEqual(result['next'],'omdb:3')
    def test_omdb_details_fallback_preserves_personal_data(self):
        self.configure({'omdb_key':'test'})
        self.backend.handle(dict(op='save',title=self.movie,values={'favorite':True,'note':'Keep this'}))
        def api(url,params):
            if url==m.IMDB+'/titles/tt123':raise m.MediaError('offline')
            self.assertEqual(url,m.OMDB)
            self.assertEqual(params['i'],'tt123')
            return {'imdbID':'tt123','Type':'movie','Title':'Movie','Plot':'Full plot','Year':'2024','Runtime':'112 min','imdbRating':'8.2','imdbVotes':'123,456','Actors':'A, B','Ratings':[{'Source':'Internet Movie Database','Value':'8.2/10'}]}
        with patch.object(m,'http',side_effect=api):
            result=self.backend.details({'title':self.movie,'refresh':True})
        self.assertEqual(result['plot'],'Full plot')
        self.assertEqual(result['runtime'],112)
        self.assertEqual(result['votes'],123456)
        self.assertEqual(self.backend.personal('tt123')['note'],'Keep this')
    def test_omdb_seasons_and_episodes(self):
        self.configure({'omdb_key':'test'})
        title=self.movie|{'kind':'tv'}
        def api(url,params):
            if url.startswith(m.IMDB):raise m.MediaError('offline')
            if 'Season' not in params:return {'totalSeasons':'2'}
            return {'Episodes':[{'Episode':'1','Title':'Pilot','Released':'2020-01-01','imdbRating':'N/A'}]}
        with patch.object(m,'http',side_effect=api):
            self.assertEqual(self.backend.episodes({'title':title})['seasons'],['1','2'])
            result=self.backend.episodes({'title':title,'season':'1'})
        self.assertEqual(result['items'][0]['number'],1)
        self.assertIsNone(result['items'][0]['rating'])
    def test_omdb_discovery_explains_search_instead_of_fake_results(self):
        self.configure({'omdb_key':'test'})
        with patch.object(m,'http',side_effect=m.MediaError('offline')):
            with self.assertRaisesRegex(m.MediaError,'discovery requires a TMDB key'):
                self.backend.browse({'kind':'movie'})
    def test_omdb_rejections_do_not_echo_upstream_secrets(self):
        self.configure({'omdb_key':'private-value'})
        with patch.object(m,'http',return_value={'Response':'False','Error':'Invalid API key private-value'}):
            with self.assertRaises(m.MediaError) as error:self.backend.omdb(i='tt123')
        self.assertNotIn('private-value',str(error.exception))
    def test_omdb_no_results_is_a_successful_empty_page(self):
        self.configure({'omdb_key':'test'})
        def api(url,params):
            if url.startswith(m.IMDB):raise m.MediaError('offline')
            return {'Response':'False','Error':'Movie not found!'}
        with patch.object(m,'http',side_effect=api):
            self.assertEqual(self.backend.browse({'kind':'movie','query':'no matches'}),{'items':[],'next':''})
    def test_stale_catalogue_survives_both_primary_and_fallback_outages(self):
        self.configure({'tmdb_key':'test'})
        key='browse:'+json.dumps(['movie','',{},''],sort_keys=True)
        self.backend.put(key,dict(items=[self.movie],next=''))
        with self.backend.db() as db:db.execute('UPDATE cache SET updated=0')
        with patch.object(m,'http',side_effect=m.MediaError('offline')):
            result=self.backend.browse({'kind':'movie'})
        self.assertEqual(result['items'][0]['id'],'tt123')
        self.assertIn('Offline',result['warning'])

    def test_trailers_exclude_promotional_clips_and_deduplicate(self):
        videos=[dict(key='clip',site='YouTube',type='Featurette',name='Behind the scenes'),dict(key='trailer',site='YouTube',type='Trailer',name='Official trailer',official=True),dict(key='trailer',site='YouTube',type='Trailer',name='Official trailer',official=True)]
        trailers=m.tmdb_trailers({'videos':{'results':videos}})
        self.assertEqual(len(trailers),1)
        self.assertTrue(trailers[0]['url'].endswith('trailer'))
    def test_full_cast_includes_all_crew_jobs_and_actors(self):
        actors=[dict(id=i,name=str(i),character='Character') for i in range(45)]
        crew=[dict(id=90,name='Director',job='Director',department='Directing'),dict(id=91,name='Editor',job='Editor',department='Editing')]
        credits=m.tmdb_credits({'credits':{'cast':actors,'crew':crew}})
        self.assertEqual(len(credits),47)
        self.assertEqual(credits[-1]['job'],'Editor')
        self.assertEqual(credits[0]['department'],'Acting')
    def test_spoiler_cleanup_preserves_story_and_cleans_cached_heading(self):
        self.assertEqual(m.clean_spoiler('Plot[edit]\nA story about the Plot family.'),'A story about the Plot family.')
        self.backend.put('spoiler:tt123',{'text':'Plot[edit]\nThe story.','url':'https://en.wikipedia.org/wiki/Example'})
        self.assertEqual(self.backend.spoilers({'title':self.movie})['text'],'The story.')

    def test_offline_catalogue(self):
        key='browse:'+json.dumps(['movie','',{},''],sort_keys=True)
        self.backend.put(key,dict(items=[self.movie],next=''))
        with self.backend.db() as db:db.execute('UPDATE cache SET updated=0')
        with patch.object(m,'http',side_effect=m.MediaError('offline')):
            result=self.backend.browse({'kind':'movie'})
        self.assertEqual(result['items'][0]['id'],'tt123')
        self.assertIn('Offline',result['warning'])

if __name__=='__main__':unittest.main()
