#!/usr/bin/env ruby
require 'rubygems'
require 'aws'
require 'fileutils'
require 'date'

include FileUtils

environment_name = 'CatapultRecoveryTest' # TODO parameterise
temp_directory = '/mnt/restore/db'
mkdir_p(temp_directory)

restore_date = if ARGV.first =~ /\d\d\d\d-\d\d-\d\d/
  ARGV.first
else
  puts "Please specify the restore date like 'yyyy-mm-dd' not #{ARGV.first}"
  exit(1)
end

acct = Aws::S3.new(
  'AKIAJN3V2WRSXHZ3YIBA', 
  'M3TQFP829iFDc8QpBDQhjDXxEaSDE9Z9Lz0BNBhg', 
  :connection_mode => :single
)

backup_bucket = acct.bucket("catapult-backup")
prefix = "daily/#{restore_date}/catapult_production.pgz."

# Read each object in order and write to the catapult_production.pgz file... saves manually cat'ing
#
File.open(File.join(temp_directory, 'catapult_production.pgz'), 'w+') do |f|
  backup_bucket.keys(:prefix => prefix).each do |key|
    puts "Fetching #{key.name}"
    backup_bucket.s3.interface.get(backup_bucket.name, key.name) do |data|
      f.write(data)
    end
  end
end

puts "Restoring database"

# TODO parameterise the DB name
#
`sudo -u postgres pg_restore -d #{environment_name}_production #{File.join(temp_directory, 'catapult_production.pgz')}`
