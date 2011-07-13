require 'open-uri'
require 'rails'
require 'cgi'
require 'feedzirra'
require 'dbm'

def get_toprentals()
    api_key="xxxxxxxxxx"
    base_url = "http://api.rottentomatoes.com"
    url_path = "/api/public/v1.0/lists/dvds/top_rentals.json"

    url = "%s%s?apikey=%s" % [base_url, url_path, api_key]
    top_rentals = open(url).read
    # DEBUG top_rentals = open('top_rentals.json').read
    decoded_rentals = ActiveSupport::JSON.decode(top_rentals)

    decoded_rentals['movies'].each do |movie|
      name_year= "%s %s" % [movie['title'], movie['year']]
      yield name_year
    end
end

def search_btjunkie(search_term)
    query = CGI.escape(search_term)
    # o=52 -- sort by number of seeders
    url = "http://btjunkie.org/rss.xml?q=%s&o=52" % query
    results = open(url).read
    # DEBUG results = open('btjunkie.xml').read
    Feedzirra::Feed.parse(results).entries.each do |entry|
      d = {}
      d['entry_url'] = entry.entry_id
      d['torrent_url'] = "%s/download.torrent" % entry.url
      d['published'] = Time.parse(entry.published)
      # Split "long title name  [number_of_seeds/number_of_leaches]"
      full_title, d['title'], d['seeds'], d['leaches'] = \
          */(.*)\s\s\[([0-9]*)\/([0-9]*)\]$/.match(entry.title)
      # Turn to ints
      d['seeds'] = d['seeds'].to_i
      d['leaches'] = d['leaches'].to_i
      # Turn "Category: Video Size: 1253MB" into a hash
      d.merge!(Hash[ *entry.summary.scan(/(\S+): (\S+)/).flatten ])
      entry.summary.scan(/(\S+): (\S+)/).flatten do |key,val|
        d[key] = val
      end
      # Some sanity!
      matches = search_term.split.select { |w| d['title'].downcase.match(w.downcase) }
      if matches.length == search_term.split.length
          yield d
      end
    end
end

dfn = File.expand_path('~/.downloaded_movies')
store = File.file?(dfn) ? DBM.open(dfn) : DBM.new(dfn)

# Get top rentals
get_toprentals do |movie_string|

  # Check we haven't already downloaded this movie
  if store.has_key?(movie_string)
    puts "Already downloaded: %s" % movie_string
    next
  end

  # Search for movie on btjunkie
  p "Searching: %s" % movie_string
  search_btjunkie(movie_string) do |result|
    # Sanity checks and we want highdef baby :)
    if result['seeds'] > 10 and \
      ( result['title'].downcase.match('720p') or \
        result['title'].downcase.match('1080p') )

      # Download the torrent
      puts "Downloading: %s" % result['title']
      outpath = File.expand_path("~/Downloads/%s.torrent" % movie_string)
      p = Process.spawn("wget '%s' -O '%s'" % [ result['torrent_url'], outpath ])
      Process.waitpid(p);
      if $?.exitstatus == 0
        store[movie_string] = 1
        break
      end

    end
  end
end
