#!/usr/bin/env ruby
require 'rubygems'
require 'aws'
require 'fileutils'
require 'date'
require 'lockfile'

$data_dir = "/mnt/"

GIG = 2**30

# CodeFire
source_account = Aws::S3.new('0VH2XJ540GSWV8MCBYG2', 'XFRQJjMzLIE6071pVQxSu7bKkQ9t1sdLBBfctr8e')

  # Catapult
destination_account = Aws::S3.new('AKIAJN3V2WRSXHZ3YIBA', 'M3TQFP829iFDc8QpBDQhjDXxEaSDE9Z9Lz0BNBhg')

$source_bucket = source_account.bucket('catapult-elearning-staging')
$destination_bucket = destination_account.bucket("catapult-backup")


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

# TODO: Handle dir limit
def copy_obj(key)
  i = 1
  file_path = "#{i}_#{file_path}" if i.integer? and i >= 1
  FileUtils.mkdir_p(File.dirname(file_path))
  unless File.directory?(file_path)
    open(file_path, 'w') do |file|
      file.write(key.data)
    end
  end
end

def _copy_obj(key)
  number_of_allowable_subdirs_in_filesystem = 30000
  i = yield/number_of_allowable_subdirs_in_filesystem
  file_path = key.name.gsub(%r{^/}, '').gsub(%r{/\./}, '/')
  if yield == 30001
    dir_name = file_path.split("/")[0]
    `mv #{dir_name} 0_#{dir_name}`
  end
  file_path = "#{i}_#{file_path}" if i.integer? and i >= 1
  FileUtils.mkdir_p(File.dirname(file_path))
  unless File.directory?(file_path)
    open(file_path, 'w') do |file|
      file.write(key.data)
    end
  end
end

def ignored_file?(obj, backup_type)
  regexps_to_ignore = [ /#{Regexp.escape('.$folder$')}$/,
                        /#{Regexp.escape('_$folder$')}$/,
                        %r{^backup},
                        %r{^catapult-elearning:backups/},
                        %r{^resources/} ]
  regexps_to_ignore.any? { |regexp| obj.key =~ regexp }
end

def upload_to_s3(name, file)
  puts "Uploading #{name}"
  key = Aws::S3::Key.create($destination_bucket, name)
  key.put(open(file))
  #AWS::S3::S3Object.store("#{filename}", 
  #                        open("#{backupfile}"), 
  #                       bucket,
  #                       :access => :public_read)
end

# TODO: Refactor to use aws gem
def delete_file(file_to_delete, backup_bucket)
  puts "deleting file #{file_to_delete}"
  exists = AWS::S3::S3Object.exists?(file_to_delete, backup_bucket)
  puts "#{file_to_delete} exists" if exists
  AWS::S3::S3Object.delete(file_to_delete, backup_bucket) if exists
end

# TODO: Don't think this is used anywhere
def  get_all_files(backup_bucket) 
  puts "getting all files"
  AWS::S3::Bucket.find(backup_bucket)
end

def number_of_backups_to_retain(backup_type)
  f = 7 if backup_type =~ /daily/
  f = 5 if backup_type =~ /weekly/
  f = 12 if backup_type =~ /monthly/
  f = 2 if backup_type =~ /yearly/
  return f
end

def remove_out_of_date_backups(backup_bucket, path, backupfile)
  puts "entered remove_out_of_date_backups method"
  puts "with path = #{path}"
  date_stamp = 2
  b = get_all_files(backup_bucket) 
  c = [] # The list of dates representing the files that need to be deleted
  files_to_delete = []

  # Build C
  b.each do |file|
    if file.inspect =~ %r(#{path}) && file.inspect =~ %r(#{backupfile}) && !file.inspect.include?('drop') && !file.key.split('.')[date_stamp].include?(/[a-zA-Z]/)
       c.push(file.key.split('.')[date_stamp])
    end
  end
  puts "b.inspect = #{b.inspect}"
  puts "backupfile is #{backupfile}"
  puts "c.inspect -> #{c.inspect}"
  puts "c -> #{c}"

  # Convert c into Date objects
  c.map! { |s| Date.parse(s) }

  puts "this is c -> #{c.inspect}"

  # Find and delete old backups
  unless c.empty?
    d = c.sort.uniq
    puts "number of unique dates = #{d.size}"
    number_of_backups = d.size
    puts "number of backups is #{d.inspect}"

    files_to_delete = b.select do |file|
      file.key =~ %r(#{d.first}) && file.key =~ %r(#{backupfile}) && file.inspect =~ %r(#{path})
    end.map { |file| file.key }

    puts "files to delete = #{files_to_delete.inspect}"
    puts "number_of_backups_to_retain is #{number_of_backups_to_retain(path)}"
    puts "calling delete_file method" if number_of_backups >= number_of_backups_to_retain(path)

    files_to_delete.each do |file_to_delete|
      if number_of_backups > number_of_backups_to_retain(path)
        delete_file(file_to_delete, backup_bucket)
      end
    end
  end
end

def datestamp
  (`echo $(date +%Y-%m-%d)`).chomp
end 

def datestamped_ext(file_name)
  (`echo #{file_name}.#{datestamp}.tar.bz2`).chomp
end 

def pathstamp(file_name)
  (`echo #{file_name}.#{datestamp}/`).chomp
end 

def do_backup(backup_type)
  backupfile = "#{backup_type}.tar.bz2"
  datestamped_file = datestamped_ext(backup_type)
  datestamped_path = pathstamp(backup_type)
  conditions = { "/daily/" => daily?, "/weekly/" => sun?, "/monthly/" => first_day_of_month?, "/bi_yearly/" => half_year?}
  puts "making directory #{backup_type}"
  FileUtils.mkdir_p("#{$data_dir}#{backup_type}")
  puts "changing into directory #{backup_type}"
  FileUtils.chdir ("#{$data_dir}#{backup_type}")
  
  puts "Querying Source Bucket"
  $source_bucket.keys('prefix' => backup_type).each do |key|
    puts key
    copy_obj(key)
  end

=begin
  marker_str = ""
  dir_no = 0
  loop do                                                                        # This loop is due to restrictions
    b =  AWS::S3::Bucket.find(bucket, :marker => marker_str)                     # imposed by aws. Requests to list
    b.each do |obj|                                                              # objects contained in a bucket
      is_in_backup = yield(obj.key)                                              # will only return the first thousand
      copy_obj(obj, bucket) { dir_no } if !ignored_file?(obj, backup_type) && is_in_backup  # results. 
      dir_no += 1 if is_in_backup
    end                                                                          #
    break unless b.is_truncated
    marker_str = b.objects.last.key
  end
=end

  puts "exiting copy obj loop and changing out of dir"
  FileUtils.chdir($data_dir)
  puts "tarring #{backup_type}"
  `tar -cjf #{backupfile} #{backup_type}`
  if File.size(backupfile) > (2*GIG)  #issues with AWS handling uploads of files > 2Gb
    puts "splitting #{backupfile}"
    `split -a 2 -d -b 2G #{backupfile} #{backupfile}.`
  end
  file_array = Dir.entries(Dir.pwd).sort
  puts file_array
  file_array.delete_if {|x| x !~ /bz2.\d/ || x !~ %r(#{backup_type})} #look for any .tar.bzip2 files appended with a .number
  puts "processed file array #{file_array}"
  if file_array.size > 0
    conditions.each_pair do |path, condition|
      puts "Current conditions pair is #{path} #{condition}" 
      frag_index = 0
      file_array.each do |backup_fragment|
        if condition
          puts "uploading big #{backup_fragment} to s3 #{path}" 
          upload_to_s3("#{path}#{datestamp}/#{datestamped_path}#{datestamped_file}.#{frag_index}", backup_fragment)
        end
        frag_index += 1
      end
      puts "removing out of date #{backupfile} file fragments from #{path}" if condition
      #remove_out_of_date_backups(backup_bucket, path, backup_type) if condition
    end
    `rm #{backupfile}.*`
  else
    conditions.each_pair do |path, condition|
      if condition
        puts "uploading #{backupfile} to s3 #{path}" 
        upload_to_s3("#{path}#{datestamp}/#{datestamped_path}#{datestamped_file}", backupfile)
        puts "removing out of date #{backupfile} files" 
        #       remove_out_of_date_backups(backup_bucket, path, backup_type) 
      end
    end
  end
  %x(rm -rf #{backup_type})
end

lockfile = Lockfile.new("#{$data_dir}/backup.lock")
begin
  lockfile.lock
  do_backup("documents")# { |key| key !~ %r{^answers/} && key !~ %r{\/$} } 
  do_backup("answers")#   { |key| key =~ %r{^answers/} && key !~ %r{\/$} } 

  date = `date`
  `touch #{datestamp}.answers.drop`
  `echo "backup of answers and documents completed #{date}" > #{datestamp}.answers.drop`
  upload_to_s3("/daily/#{datestamp}/answers.drop", "#{datestamp}.answers.drop")
rescue
  puts $!
  puts $!.backtrace
ensure
  lockfile.unlock
end
