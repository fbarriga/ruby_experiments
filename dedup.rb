require 'find'
require './subprocess.rb'
require 'mimemagic'
require 'mime/types'
require 'digest/md5'
require 'set'
require 'fileutils'
include FileUtils

TEST_FRAMES = 50
START_TIME = "00:01:00"
#SEARCH_DIR = File.expand_path("/Volumes/Store/duptest")
#SEARCH_DIR = File.expand_path("/Volumes/Storage/Downloads/asd")
SEARCH_DIR = File.expand_path("/Volumes/Data/Backups/asd")
TMP_DIR = File.expand_path("/Volumes/Store/tmp")

# Create directories if they don't exist
mkdir SEARCH_DIR if ! File.directory?(SEARCH_DIR)
mkdir TMP_DIR if ! File.directory?(TMP_DIR)

# Helper to run command silently and raise exception if didn't run correctly
def quietrun(cmd)
    s = Subprocess.new(*cmd, { :stdout => "/dev/null", :stderr => "/dev/null" })
    exit_code = s.poll_for_exit(300)
    if exit_code != 0
      raise "!!! FATAL: Command exit with code: %s (%s)" % [ exit_code, cmd ] 
    end
end

md5_hash = {}
dup_hash = {}

Dir.chdir(TMP_DIR) do
  Find.find(SEARCH_DIR) do |filename|
    
    # Skip if not a file or not video
    next if ! File.file?(filename)
    filemime = MimeMagic.by_path(filename)
    next if ! filemime || ! filemime.video?
    puts "*** Analysing: %s" % filename
    
    # Get some frames with mplayer
    print "\tMplayer "
    quietrun(['mplayer', '-nosound', '-vo', 'jpeg', '-ss', START_TIME, 
              '-frames', TEST_FRAMES.to_s, filename])
       
    # Sanity check       
    if %x(ls *.jpg).split("\n").length < 1
      puts "\n\tUnable to create images, skipping..."
      next
    end

    # Create 10x10 black/white threshold images
    print "|| ImageMagick "
    quietrun(['mogrify', '-resize', '16x16!', '-threshold', '50%',
              '-format', 'bmp', '*.jpg'])
              
    # Create MD5Sum for each image file
    print "|| MD5Sums\n"
    %x(ls *.bmp | sort -n).split("\n").each do |tmpimg|
      md5sum = Digest::MD5.file(tmpimg).to_s
      md5_hash[md5sum] = Set.new() if ! md5_hash.has_key?(md5sum)
      md5_hash[md5sum] << filename
      if md5_hash[md5sum].length > 1
        key = md5_hash[md5sum]
        # Increment count by 1
        dup_hash[key] = 0 if ! dup_hash.has_key?(key)
        dup_hash[key] += 1
      end
    end
    
    # Delete the images created by mogrify and mplayer
    rm(%x(ls *.bmp *.jpg).split("\n"))
    
  end
end

# Print duplicates
dup_hash.sort{|a,b| a[1] <=> b[1]}.each do |a,b|
  puts "--- Potential Duplicate: matching frames: %.02f%%" % (100*b/TEST_FRAMES)
  a.each { |filename| puts "\t%s" % filename }
end
