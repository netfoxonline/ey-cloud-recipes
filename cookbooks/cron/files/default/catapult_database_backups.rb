#!/usr/bin/env ruby
require 'rubygems'
require 'aws/s3'
require 'fileutils'
require 'date'

backup_bucket = 'catapult-elearning-test-backups'
backup_type = "catapult_production"
backupfile = "production_database"


def daily?
  true
end

def sun?
date = `date`
date =~ /Sun/
end

def first_day_of_month?
date = `date`.split
date[2].to_i == 1
end

def half_year?
date = `date`.split
["Jul", "Jan"].include? date[1] and date[2].to_i == 1
end

#def establish_connection
#  AWS::S3::Base.establish_connection!(
#                                      :access_key_id => 'AKIAJN3V2WRSXHZ3YIBA',
#                                      :secret_access_key => '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')
#end

def establish_connection
  AWS::S3::Base.establish_connection!(
                                      :access_key_id => '0VH2XJ540GSWV8MCBYG2',
                                      :secret_access_key => 'XFRQJjMzLIE6071pVQxSu7bKkQ9t1sdLBBfctr8e')
end

def upload_to_s3(filename, backupfile, bucket_name)
  AWS::S3::S3Object.store("#{filename}", 
                          open("#{backupfile}"), 
                         bucket_name,
                         :access => :public_read)
end

def delete_file(file_to_delete, backup_bucket)
   exists = AWS::S3::S3Object.exists?(file_to_delete, backup_bucket)
   AWS::S3::S3Object.delete(file_to_delete, backup_bucket) if exists
end

def  get_all_files(backup_bucket) 
  b =  AWS::S3::Bucket.find(backup_bucket)
end

def number_of_backups_to_retain(type)
  f = 7 if type =~ /daily/
  f = 5 if type =~ /weekly/
  f = 12 if type =~ /monthly/
  f = 2 if type =~ /yearly/
  return f
end

def remove_out_of_date_backups(backup_bucket, path, backupfile)
  date_stamp = 1
  establish_connection
  b = get_all_files(backup_bucket) 
  c=[]
  files_to_delete = []
  b.each {|file| c.push(file.key.split('.')[date_stamp]) if file.inspect =~ %r(#{path}) &&
    file.inspect =~ %r(#{backupfile})}
  c = c.map {|s| Date.parse s}
  if !c.empty?
    c=c.sort.uniq
    number_of_backups = c.size
    b.each {|file| files_to_delete.push(file.key) if file.key =~ %r(#{c.first}) && 
      file.key =~ %r(#{backupfile})  &&  
      file.inspect =~ %r(#{path})}
    files_to_delete.each {|file_to_delete| delete_file(file_to_delete, backup_bucket) if 
      number_of_backups > number_of_backups_to_retain(path)}
  end
end

def datestamp
 stamp = (`echo $(date +%Y-%m-%d)`).chomp
end 

def datestamped_ext(file_name)
  file_name = (`echo #{file_name}.#{datestamp}.tar.bz2`).chomp
end 

def pathstamp(file_name)
  path_name = (`echo #{file_name}.#{datestamp}/`).chomp
end 

datestamped_file = (`echo #{datestamped_ext(backupfile)}`).chomp
datestamped_path = pathstamp(backupfile)
conditions = { "/daily/" => daily?, "/weekly/" => sun?, "/monthly/" => first_day_of_month?, "/bi_yearly/" => half_year?}
bk_num = (`sudo -i eybackup -e postgresql -l #{backup_type} | grep "#{backup_type}.*pgz" | cut -d":" -f1 | sort -n | tail -1`).chomp
`sudo -i eybackup -e postgresql -d #{bk_num}:#{backup_type}`
FileUtils.chdir "/mnt/tmp"
file = (`ls -tr #{backup_type}.*.pgz | tail -1`).chomp
`sudo mv #{file} #{backupfile}`
establish_connection
conditions.each_pair do |path, condition|
  if condition
    upload_to_s3("#{path}#{datestamp}/#{datestamped_path}#{datestamped_file}", backupfile, backup_bucket) 
    remove_out_of_date_backups(backup_bucket, path, backupfile)
  end
end


date = `date`
`touch #{datestamp}.database.drop`
`echo "backup of production database completed #{date}" > #{datestamp}.database.drop`
upload_to_s3("/daily/#{datestamp}/database.drop", "#{datestamp}.database.drop", backup_bucket)
