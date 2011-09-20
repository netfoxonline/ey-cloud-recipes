#!/usr/bin/env ruby
require 'rubygems'
require 'aws'
require 'fileutils'
require 'date'

include FileUtils

temp_directory = '/mnt/restore/documents'
extracted_dir = File.join(temp_directory, 'extracted')
mkdir_p(temp_directory)
mkdir_p(extracted_dir)

restore_date = ARGV[0]
target_bucket_name = ARGV[1]

if restore_date !~ /\d\d\d\d-\d\d-\d\d/ || target_bucket_name.nil?
  puts "Usage: catapult_answers_restore.rb <restore-date(yyyy-mm-dd)> <target-bucket-name>"
  exit(1)
end


acct = Aws::S3.new(
  'AKIAJN3V2WRSXHZ3YIBA', 
  'M3TQFP829iFDc8QpBDQhjDXxEaSDE9Z9Lz0BNBhg', 
  :connection_mode => :single
)

backup_bucket = acct.bucket("catapult-backup")
target_bucket = acct.bucket(target_bucket_name)
prefix = "daily/#{restore_date}/documents.tar.gz."

# Read each object in order and write to the documents.tar.bz2 file... saves manually cat'ing
#
File.open(File.join(temp_directory, 'documents.tar.gz'), 'w+') do |f|
  backup_bucket.keys(:prefix => prefix).each do |key|
    puts "Fetching #{key.name}"
    backup_bucket.s3.interface.get(backup_bucket.name, key.name) do |data|
      f.write(data)
    end
  end
end

puts "Extracting data"
`tar -xzf #{File.join(temp_directory, 'documents.tar.gz')} -C #{extracted_dir}`

cd(extracted_dir) do
  Dir.glob("**/*") do |file| 
    if File.file?(file)
      puts "Uploading #{file} to #{file}"
      perms = 'public-read' if file =~ /^logos\//
      target_bucket.put(file, File.open(file), perms)
    end
  end
end
