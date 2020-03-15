#!/usr/bin/env ruby

require 'sequel'
require 'json'
require 'awesome_print'
require 'pathname'

lib_path = '/mnt/i/medialib'

# timestamp can be encoded in filename (WinDV method)
#
# get the dates from the EXIF data in following prio
# DateTimeOriginal, CreateDate, FileModifyDate
#
# check against the mtime of the physical file
# if mtime is older than the exif time then take this
#
def extract_media_time(filename, mtime, exif)
  # is the filename date code by WinDV?
  # eg. mov.2008-02-03_16-13.03.avi
  m = filename.match(/(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})\.(\d{2})/)
  if m
    c  = m.captures
    media_time = Time.new(c[0].to_i, c[1].to_i, c[2].to_i, c[3].to_i, c[4].to_i, c[5].to_i)
    STDERR.puts "WinDV date: #{media_time}"
  else
    media_time = Time.parse(exif['FileModifyDate'])
    begin
      # STDERR.puts "2: #{exif['CreateDate']}"
      media_time = Time.parse(exif['CreateDate']) unless exif['CreateDate'].nil?
    rescue StandardError => e
      STDERR.puts "CreateDate: '#{exif['CreateDate']}': #{e}"
    end
    begin
      media_time = Time.parse(exif['DateTimeOriginal']) unless exif['DateTimeOriginal'].nil?
    rescue StandardError => e
      STDERR.puts "DateTimeOriginal: '#{exif['DateTimeOriginal']}': #{e}"
    end
  end

  file_time = Time.at(mtime)

  return file_time < media_time ? file_time : media_time
end

# after selecting one file out of the list of identical digests
# we'll queue it
# another file might show up with the exact same destination path
# but a different digest. that b/c one is geotagged and the other is
# not. We wanna keep the geotagged file
#
def insert_into_candidate_list(list, filename, src_path, dst_path, exif)
  unless list.key? dst_path
    # new entry
    list[dst_path] = { filename: filename, src_path: src_path, dst_path: dst_path, exif: exif }
  else
    # entry is know
    # if existing entry has no Latitude but the new has, we'll overwrite with new data
    if list[dst_path][:exif]['GPSLatitude'].nil? && !exif['GPSLatitude'].nil?
      list[dst_path] = { filename: filename, src_path: src_path, dst_path: dst_path, exif: exif }
    end
  end
end

def create_script(list)
  puts "#!/bin/bash"
  puts
  list.each_key do |fname|
    printf "mkdir -p %s\n", File.dirname(list[fname][:dst_path])
    printf "cp -i -v \"%s\" \"%s\"\n", list[fname][:src_path], list[fname][:dst_path]
    printf "echo \"%s\" >> \"%s/dirinfo.txt\"\n", list[fname][:src_path], File.dirname(list[fname][:dst_path])
  end
end

DB = Sequel.connect("sqlite://media.db")
media = DB[:media]
list = {}

#
# create an array which contains all digests
#
digests = media.distinct.select(:digest).map { |r| r[:digest] }

digests.each do |digest|
  files = media.where(digest: digest).order(:filename)
  files.each do |row|
    # STDERR.puts "1: #{row[:path]}"
    exif = JSON.parse(row[:exif])
    media_time = extract_media_time(row[:filename], row[:mtime], exif)
    year = media_time.year
    month = media_time.month
    day = media_time.day
    insert_into_candidate_list(list,
                               row[:filename],
                               row[:path],
                               format("%s/%04d-%02d/%04d-%02d-%02d/%s", lib_path, year, month, year, month, day, row[:filename]), exif)
    break
  end
end

create_script(list)

