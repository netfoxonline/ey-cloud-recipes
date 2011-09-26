#!/usr/bin/env ruby
require 'rubygems'
require 'aws'
require 'fileutils'
require 'date'

#backup_bucket_name = 'catapult-backup'
backup_bucket_name = 'catapult-elearning-test-backups'
backup_type = {"resources" => "/data/catapult/shared/resources"}
$data_dir = "/mnt/backups"

# Catapult
destination_account = Aws::S3.new(
  'AKIAJN3V2WRSXHZ3YIBA', 
  'M3TQFP829iFDc8QpBDQhjDXxEaSDE9Z9Lz0BNBhg', 
  :connection_mode => :single
)

$destination_bucket = destination_account.bucket(backup_bucket_name)

def daily?
  true
end

def sun?
  !(`date` =~ /Sun/).nil?
end

def first_day_of_month?
  date = `date`.split
  date[2].to_i == 1
end

def half_year?
  date = `date`.split
  ["Jul", "Jan"].include? date[1] and first_day_of_month?
end


def upload_to_s3(filename, backupfile)
  key = Aws::S3::Key.create($destination_bucket, filename)
  key.put(File.open(backupfile))
end

# def delete_file(file_to_delete, backup_bucket)
#    exists = AWS::S3::S3Object.exists?(file_to_delete, backup_bucket)
#    AWS::S3::S3Object.delete(file_to_delete, backup_bucket) if exists
# end
# 
# def  get_all_files(backup_bucket) 
#   AWS::S3::Bucket.find(backup_bucket)
# end

# def number_of_backups_to_retain(backup_type)
#   f = 7 if backup_type =~ /daily/
#   f = 5 if backup_type =~ /weekly/
#   f = 12 if backup_type =~ /monthly/
#   f = 2 if backup_type =~ /yearly/
#   return f
# end
# 
# def remove_out_of_date_backups(backup_bucket, path, backup_type)
#   date_stamp = 2
#   establish_connection
#   b = get_all_files(backup_bucket) 
#   c=[]
#   files_to_delete = []
#   b.each {|file| c.push(file.key.split('.')[date_stamp]) if file.inspect =~ %r(#{path}) && 
#     file.inspect =~ %r(#{backup_type}) && !file.inspect.include?('drop')
#     && !file.key.split('.')[date_stamp].include?(/[a-zA-Z]/)} 
#   c = c.map {|s| Date.parse s}
#   if !c.empty?
#     d=c.sort.uniq
#     number_of_backups = d.size
#     b.each {|file| files_to_delete.push(file.key) if file.key =~ %r(#{d.first}) && 
#       file.key =~ %r(#{backup_type}) &&  
#       file.inspect =~ %r(#{path})}
#      files_to_delete.each {|file_to_delete| delete_file(file_to_delete, backup_bucket) if 
#       number_of_backups > number_of_backups_to_retain(path)}
#   end
# end

def datestamp
 (`echo $(date +%Y-%m-%d)`).chomp
end 

def datestamped_ext(file_name)
  (`echo #{file_name}.#{datestamp}.tar.bz2`).chomp
end 

def pathstamp(file_name)
  (`echo #{file_name}.#{datestamp}/`).chomp
end 

FileUtils.cd($data_dir) do
  conditions = { "daily/" => daily?, "weekly/" => sun?, "monthly/" => first_day_of_month?, "bi_yearly/" => half_year?}
  backup_type.each_pair do |backup_type, backup_path|
    backupfile = "#{backup_type}.tar.bz2"
    datestamped_file = datestamped_ext(backup_type)
    datestamped_path = pathstamp(backup_type)
    `tar -cjf #{backupfile} #{backup_path}`
    `split -a 2 -d -b 500M #{backupfile} #{backupfile}.`
  
    file_array = Dir.entries(Dir.pwd).sort
    file_array.delete_if {|x| x !~ /bz2.\d*/}
    if file_array.size > 0
      conditions.each_pair do |path, condition|
        frag_index = 0
        file_array.each do |backup_fragment|
          if condition
            upload_to_s3("#{path}#{datestamp}/#{datestamped_path}#{datestamped_file}.#{frag_index}", backup_fragment)
          end          
          frag_index += 1
        end
  #      remove_out_of_date_backups(backup_bucket, path, backup_type) if condition
      end
      `rm #{backupfile}.*`
    else
      conditions.each_pair do |path, condition|
        if condition
          upload_to_s3("#{path}#{datestamp}/#{datestamped_path}#{datestamped_file}", backupfile) 
  #        remove_out_of_date_backups(backup_bucket, path, backup_type)
        end
      end
    end
    #  %x(rm -rf #{backup_type})
  end

  date = `date`
  `touch #{datestamp}.resources.drop`
  `echo "backup of resources and source code completed #{date}" > #{datestamp}.resources.drop`
  upload_to_s3("/daily/#{datestamp}/resources.drop", "#{datestamp}.resources.drop", backup_bucket)
end
