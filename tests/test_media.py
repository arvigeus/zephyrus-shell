import importlib.util
import json
import os
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
    def test_person_resolves_imdb_identity_through_tmdb_and_sorts_newest_first(self):
        self.configure({'tmdb_key':'test'})
        responses = [
            {'person_results':[{'id':10}]},
            {'name':'Actor','combined_credits':{'cast':[
                {'id':2,'media_type':'movie','title':'Later','release_date':'2020-01-01'},
                {'id':1,'media_type':'movie','title':'First','release_date':'1990-01-01','poster_path':'/poster.jpg'}
            ]}}
        ]
        with patch.object(self.backend,'tmdb',side_effect=responses) as api:
            result=self.backend.person({'person':{'id':'nm1'}})
        self.assertEqual([t['title'] for t in result['credits']],['Later','First'])
        self.assertEqual(result['credits'][1]['poster'],'https://image.tmdb.org/t/p/w500/poster.jpg')
        self.assertEqual(api.call_args_list[0].args,('find/nm1',))
        self.assertEqual(api.call_args_list[0].kwargs,{'external_source':'imdb_id'})

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
        self.configure({'tmdb_key':'test'})
        with patch.object(m,'http',return_value={'results':[{'id':12,'title':'Film'}],'total_pages':2}) as api:
            result=self.backend.browse(dict(kind='movie'))
            self.assertEqual([t['id'] for t in result['items']],['tmdb:movie:12'])
            self.assertEqual(result['next'],'tmdb:2')
            self.assertTrue(api.call_args.args[0].endswith('/discover/movie'))
    def test_tmdb_pagination_continues_same_provider(self):
        self.configure({'tmdb_key':'test-secret'})
        def api(url,params):
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

    def test_local_poster_enrichment_keeps_local_file(self):
        with patch.dict(os.environ, {'XDG_VIDEOS_DIR':str(self.backend.data / 'Videos')}):
            source = self.backend.data / 'source.mkv'
            source.write_bytes(b'video')
            path = self.backend.local.add(self.movie, source)
            self.assertFalse(self.backend.handle({'op':'local_titles','kind':'movie'})['items'][0].get('poster'))
            with patch.object(self.backend, 'details', return_value=self.movie | {'poster':'https://example.org/poster'}):
                posters = self.backend.handle({'op':'local_posters','kind':'movie'})
            self.assertEqual(posters, [{'id':'tt123','poster':'https://example.org/poster'}])
            self.backend.save_title(self.movie | {'poster':posters[0]['poster']})
            local = self.backend.handle({'op':'local_titles','kind':'movie'})['items'][0]
            self.assertEqual(local['poster'], posters[0]['poster'])
            self.assertEqual(local['localPath'], path)
    def test_optional_enrichment_failure_preserves_details(self):
        self.configure({'tmdb_key':'test'})
        self.backend.save_title(self.movie|{'plot':'Hydrated plot','cast':[{'name':'Actor'}]})
        with patch.object(m,'http',side_effect=m.MediaError('offline')):
            result=self.backend.artwork({'title':self.movie})
        self.assertEqual(result['title']['plot'],'Hydrated plot')
        self.assertTrue(result['warnings'])
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
        self.configure({'tmdb_key':'secret','providers':[{'name':'Example','movie_url':'https://example.org/{imdbId}?secret=private'}]})
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
        with self.assertRaisesRegex(m.MediaError,'name and movie_url'):
            self.backend.config()
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

    def test_artwork_uses_tmdb_cast_and_backdrop(self):
        self.configure({'tmdb_key':'test'})
        data={'images':{'backdrops':[{'file_path':'/backdrop.jpg'}]},
              'credits':{'cast':[{'id':1,'name':'Actor','character':'Lead'}]}}
        with patch.object(self.backend,'tmdb',return_value=data) as api:
            result=self.backend.artwork({'title':self.movie|{'tmdbId':42}})
        self.assertEqual(api.call_count,1)
        self.assertEqual(result['title']['cast'][0]['name'],'Actor')
        self.assertTrue(result['title']['backdrop'].endswith('/backdrop.jpg'))

    def test_tmdb_details_keep_existing_imdb_identity(self):
        self.configure({'tmdb_key':'test'})
        with patch.object(self.backend,'tmdb',return_value={'id':42,'title':'Movie','overview':'New plot'}):
            result=self.backend.details({'title':self.movie|{'tmdbId':42}})
        self.assertEqual(result['id'],'tt123')
        self.assertEqual(result['imdbId'],'tt123')
        self.assertEqual(result['tmdbId'],42)
        self.assertEqual(result['plot'],'New plot')

    def test_tmdb_episodes_load_seasons_and_episode_artwork(self):
        self.configure({'tmdb_key':'test'})
        title=self.movie|{'kind':'tv','tmdbId':42}
        def api(path,**params):
            if path=='tv/42': return {'seasons':[{'season_number':1}]}
            self.assertEqual(path,'tv/42/season/1')
            return {'episodes':[{'episode_number':1,'name':'Pilot','still_path':'/still.jpg'}]}
        with patch.object(self.backend,'tmdb',side_effect=api):
            self.assertEqual(self.backend.episodes({'title':title})['seasons'],['1'])
            result=self.backend.episodes({'title':title,'season':'1'})
        self.assertEqual(result['items'][0]['number'],1)
        self.assertEqual(result['items'][0]['image'],'https://image.tmdb.org/t/p/w300/still.jpg')

    def test_omdb_search_when_tmdb_fails_and_pagination(self):
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
            self.assertEqual(url,m.OMDB)
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
            self.assertEqual(url,m.OMDB)
            return {'Response':'False','Error':'Movie not found!'}
        with patch.object(m,'http',side_effect=api):
            self.assertEqual(self.backend.browse({'kind':'movie','query':'no matches'}),{'items':[],'next':''})
    def test_stale_catalogue_survives_tmdb_outage(self):
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
