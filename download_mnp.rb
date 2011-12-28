require 'open-uri'
require 'cgi'
require 'feedzirra'
require 'dbm'
require 'time'

def search_btjunkie(search_term)
    query = CGI.escape(search_term)
    # o=52 -- sort by number of seeders
    url1 = "http://btjunkie.org/rss.xml?q=%s&o=52" % query
    # url2 = "http://btjunkie.org/rss.xml?q=%s" % query
    begin
      results1 = open(url1).read
      # results2 = open(url2).read
    rescue Timeout::Error
      puts "Timed out..."
    rescue Errno::ECONNREFUSED
      puts "Connection refused..."
    end
    # DEBUG results = open('btjunkie.xml').read
    # for results in [results1, results2]
    for results in [results1]
      Feedzirra::Feed.parse(results).entries.each do |entry|
        d = {}
        d['entry_url'] = entry.entry_id
        d['torrent_url'] = "%s/download.torrent" % entry.url
        d['published'] = entry.published
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
        matches = search_term.split.select { |w| d['title'].downcase.include?(w.downcase) if d['title'] }
        if matches.length >= search_term.split.length
            yield d
        end
      end
    end
end

dfn = File.expand_path('~/.downloaded_mnp')
store = File.file?(dfn) ? DBM.open(dfn) : DBM.new(dfn)

# Get top rentals
searches = [
  'rape',
  'humiliated', 'humiliated.com',
  'disgraced18', 'disgraced18.com',
  'publicdisgrace', 'public disgrace',
  'shameonher', 'shame on her',
  'facialabuse','facial abuse',
  'ghettogaggers', 'ghetto gaggers',
  'latinaabuse', 'latina abuse',
  'meatholes', 'meat holes',
  'meatmembers', 'meat members',
  'midnightprowl', 'midnight prowl',
  'maxhardcore', 'max hardcore',
  'ggg', '666',
  'moodpictures', 'mood pictures',
  'elitepain', 'elite pain',
  'twins',
  # individuals
  'tobi pacific',
  'amina skye',
  'riyanna skie',
  'evilyn fierce',
  'shyla jennings',
  'sensi pearl',
  'caprice',
  'ebony goddexxx', 'ebony godexxx', 'claudia price',
  'gauge',
  'strokahontas',
  'tori black',
  'alexis texas',
  'sophia santi',
  'jynx maze',
  'juelz ventura', 'layna laurel',
  'aletta ocean',
  'rihanna rimes',
  'adrenalynn',
  'rebecca linares',
  'shazia sahari',
  'evelyn lin',
  'tanner mayes',
  'kimberely kane',
  'candice nicole',
  'capri anderson',
  'melody nikai',
  'megan vaughn',
  'alexis ford',
  'raven alexis',
  'indigo augustine',
  ]
searches.each do |search_string|

  # Search for movie on btjunkie
  p "Searching: %s" % search_string
  downloaded = 0
  search_btjunkie(search_string) do |result|

    # Limit to 5
    downloaded += 1
    break if downloaded > 5

    # Clean up title
    result['title'].gsub!('/','_')

    # Sanity checks
    if result['seeds'] > 1
      # Check we haven't already downloaded this movie
      if store.has_key?(result['entry_url'])
        # puts "Already downloaded: %s" % result['title']
        next
      end

      # Download the torrent
      puts "Downloading: %s" % result['title']
      outpath = File.expand_path("~/Downloads/%s.torrent" % result['title'])
      if File::file?(outpath)
        puts "!!! File already exists: %s" % outpath
      else
        p = IO.popen([ 'wget', '-q', result['torrent_url'], '-O', outpath ]); p.read; p.close
        if $?.exitstatus == 0
          store[result['entry_url']] = 1
        end
      end

    end
  end
end
