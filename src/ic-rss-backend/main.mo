import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Time "mo:base/Time";
import Debug "mo:base/Debug";
import Int "mo:base/Int";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import CertifiedCache "mo:certified-cache";
import Http "mo:certified-cache/Http";

actor {
  type HttpRequest = Http.HttpRequest;
  type HttpResponse = Http.HttpResponse;

  // Podcast episode type
  type PodcastEpisode = {
    title : Text;
    description : Text;
    audioUrl : Text;
    pubDate : Text;
    duration : Text;
    guid : Text;
  };

  public type Podcast = {
    id : Text;
    title : Text;
    description : Text;
    link : Text;
    author : Text;
    imageUrl : Text;
    episodes : [PodcastEpisode];
  };

  stable var stablePodcasts : [Podcast] = [{
    id = "1";
    title = "Podcast 1";
    description = "A podcast about interesting topics.";
    link = "https://example.com/podcast1";
    author = "Author 1";
    imageUrl = "https://example.com/podcast1.jpg";
    episodes = [
      {
        title = "Episode 1: Introduction";
        description = "In this episode, we introduce our podcast and what to expect.";
        audioUrl = "https://example.com/episode1.mp3";
        pubDate = "Mon, 05 Jul 2023 10:00:00 GMT";
        duration = "00:30:00";
        guid = "episode1";
      },
      {
        title = "Episode 2: Deep Dive";
        description = "We take a deep dive into an interesting topic.";
        audioUrl = "https://example.com/episode2.mp3";
        pubDate = "Mon, 12 Jul 2023 10:00:00 GMT";
        duration = "00:45:00";
        guid = "episode2";
      },
    ];
  }];

  func fromStablePodcasts(podcasts : [Podcast]) : HashMap.HashMap<Text, Podcast> {
    podcasts.vals()
    |> Iter.map<Podcast, (Text, Podcast)>(
      _,
      func(p : Podcast) : (Text, Podcast) = (p.id, p),
    )
    |> HashMap.fromIter<Text, Podcast>(_, podcasts.size(), Text.equal, Text.hash);
  };

  var podcasts : HashMap.HashMap<Text, Podcast> = fromStablePodcasts(stablePodcasts);

  // System functions
  system func preupgrade() {
    stablePodcasts := podcasts.vals() |> Iter.toArray(_);
  };
  system func postupgrade() {
    ignore cache.pruneAll();
    podcasts := fromStablePodcasts(stablePodcasts);
  };

  // Cache setup
  var two_days_in_nanos = 2 * 24 * 60 * 60 * 1000 * 1000 * 1000;
  var cache = CertifiedCache.CertifiedCache<Text, Blob>(
    1,
    Text.equal,
    Text.hash,
    Text.encodeUtf8,
    func(b : Blob) : Blob { b },
    two_days_in_nanos + Int.abs(Time.now()),
  );

  public query func get_podcasts() : async [Podcast] {
    return podcasts.vals() |> Iter.toArray(_);
  };

  public query func http_request(req : HttpRequest) : async HttpResponse {
    // Only the html that has been run through concensus (http_request_update) can be returned
    // to the browser for security reasons. In a query call we can use the cached version or upgrade
    // to the update request sign the latest version of the html
    let cachedBody = cache.get(req.url);

    switch cachedBody {
      case (?body) {
        // Return the cached certified version
        return {
          status_code : Nat16 = 200;
          headers = [("content-type", "text/html"), cache.certificationHeader(req.url)];
          body = body;
          streaming_strategy = null;
          upgrade = null;
        };
      };
      case null {
        Debug.print("Request was not found in cache. Upgrading to update request.\n");
        return {
          status_code = 404;
          headers = [];
          body = Blob.fromArray([]);
          streaming_strategy = null;
          upgrade = ?true;
        };
      };
    };
  };

  public func http_request_update(req : HttpRequest) : async HttpResponse {
    let podcastId = Text.stripStart(req.url, #text("/rss/podcasts/"));
    label s switch (podcastId) {
      case (?id) {
        let ?podcast = podcasts.get(id) else break s;
        let rssContent = generateRSSFeed(podcast);
        let body = Text.encodeUtf8(rssContent);
        cache.put(req.url, body, null);
        return {
          status_code = 200;
          headers = [("Content-Type", "application/rss+xml")];
          body = body;
          streaming_strategy = null;
          upgrade = null;
        };
      };
      case (null) break s;
    };
    // Catch all
    return {
      status_code = 404;
      headers = [];
      body = Blob.fromArray([]);
      streaming_strategy = null;
      upgrade = null;
    };
  };

  // Generate RSS feed
  func generateRSSFeed(podcast : Podcast) : Text {
    var rss = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    rss #= "<rss version=\"2.0\" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\" xmlns:content=\"http://purl.org/rss/1.0/modules/content/\">\n";
    rss #= "  <channel>\n";
    rss #= "    <title>" # podcast.title # "</title>\n";
    rss #= "    <description>" # podcast.description # "</description>\n";
    rss #= "    <link>" # podcast.link # "</link>\n";
    rss #= "    <language>en-us</language>\n";
    rss #= "    <itunes:author>" # podcast.author # "</itunes:author>\n";
    rss #= "    <itunes:image href=\"" # podcast.imageUrl # "\"/>\n";

    for (episode in podcast.episodes.vals()) {
      rss #= "    <item>\n";
      rss #= "      <title>" # episode.title # "</title>\n";
      rss #= "      <description>" # episode.description # "</description>\n";
      rss #= "      <enclosure url=\"" # episode.audioUrl # "\" type=\"audio/mpeg\"/>\n";
      rss #= "      <pubDate>" # episode.pubDate # "</pubDate>\n";
      rss #= "      <itunes:duration>" # episode.duration # "</itunes:duration>\n";
      rss #= "      <guid isPermaLink=\"false\">" # episode.guid # "</guid>\n";
      rss #= "    </item>\n";
    };

    rss #= "  </channel>\n";
    rss #= "</rss>";
    return rss;
  };
};
