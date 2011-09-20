#!/usr/bin/env ruby
require 'rubygems'
require 'aws'
require 'fileutils'
require 'date'

include FileUtils

temp_directory = '/mnt/restore/answers'
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
prefix = "daily/#{restore_date}/answers.tar.bz2."

# Read each object in order and write to the answers.tar.bz2 file... saves manually cat'ing
#
File.open(File.join(temp_directory, 'answers.tar.bz2'), 'w+') do |f|
  backup_bucket.keys(:prefix => prefix).each do |key|
    puts "Fetching #{key.name}"
    backup_bucket.s3.interface.get(backup_bucket.name, key.name) do |data|
      f.write(data)
    end
  end
end

# Need to be clever here since the tar file contains too many subdirectories
# for ext3 and rather than change filesystems we can map the files 
# into a different structure when extracting them. This regex will create
# intermediate directories under answers that are derived from the first 3
# digits of the id folder of the file.
#
regex = %!'s,answers/\\([0-9]\\{3\\}\\),answers/\\1/\\1,'!

puts "Extracting data"
`tar -xvjf #{File.join(temp_directory, 'answers.tar.bz2')} -C #{extracted_dir} --transform=#{regex} --show-transformed-names`


cd(extracted_dir) do
  Dir.glob("answers/**/*") do |file| 
    if File.file?(file)
      key_name = file.gsub(%r!answers/[0-9]{3}!, 'answers')
      puts "Uploading #{file} to #{key_name}"
      target_bucket.put(key_name, File.open(file))
    end
  end
end
