import QtQuick
import QtTest
import "../../media/RatingLinks.js" as Links

TestCase {
    name: "RatingLinks"
    function test_imdb_prefers_identity_to_bad_provider_link() {
        compare(Links.page({source:"imdb",url:"/broken"},{imdbId:"tt1464335"}),"https://www.imdb.com/title/tt1464335/");
        compare(Links.page({source:"imdb",url:"tt1464335"},{}),"https://www.imdb.com/title/tt1464335/");
    }
    function test_relative_provider_links_are_web_pages() {
        compare(Links.page({source:"metacritic",url:"/uncharted"},{kind:"movie"}),"https://www.metacritic.com/movie/uncharted");
        compare(Links.page({source:"tomatoes",url:"/m/uncharted_2022"},{kind:"movie"}),"https://www.rottentomatoes.com/m/uncharted_2022");
        compare(Links.page({source:"popcorn",url:"/m/uncharted_2022"},{kind:"movie"}),"https://www.rottentomatoes.com/m/uncharted_2022");
        compare(Links.page({source:"metacritic",url:"https://www.metacritic.com/movie/uncharted/"},{}),"https://www.metacritic.com/movie/uncharted/");
        verify(Links.page({source:"tomatoes",url:"file:///bad"},{title:"Example"}).startsWith("https://www.rottentomatoes.com/search"));
    }
    function test_rt_scores_are_adjacent() {
        const ratings=[{source:"tomatoes"},{source:"metacritic"},{source:"imdb"},{source:"popcorn"}];
        compare(Links.ordered(ratings).map(r => r.source).join(","),"imdb,tomatoes,popcorn,metacritic");
    }
}
