#!/usr/bin/env ruby
require 'rubygems'
require 'aws'
require 'fileutils'
require 'date'
require 'lockfile'
require 'logger'

# Mixin module for Time that adds scheduling support
# for determining whether to copy the backup to additional
# folders.
#
module BackupSchedule
  def weekly?
    self.wday == 0
  end
  
  def monthly?
    self.day == 1
  end
  
  def half_yearly?
    (self.month == 1 || self.month == 7) && monthly?
  end
end

# The main S3Backup class.
#
# This allows you to create backup sets from one
# S3 bucket and store them as tarred and compressed
# objects in another S3 bucket. 
#
# To use:
# 
#  Create an S3Backup instance and pass it a block
#  that defines the backup sets to create from the
#  source_bucket. E.g.
#
#  S3Backup.new(source, dest, datadir) do
#     
#    # Define your backup using the backup method.
#    #
#    # Backups must have a label which is used as
#    # the name of the tar file created in S3.
#    # In addition to that you can either pass a 
#    # :prefix option, which will only backup S3 
#    # objects which start with the prefix, like so:
#    backup("answers", :prefix => "answers/")
#
#    # Or you can pass a block which will be called
#    # for each key in the bucket. If the block returns
#    # true the object with that key will be added to
#    # the backup set, like so:
#    backup("answers") {|key| key.match(/^answers\//) }
#
#  end
#
#  With this in place, the S3Backup class will take care
#  of downloading the required objects, adding them to the
#  tar file, compressing the tar and uploading them to the
#  destination S3 bucket. If all goes well, the dest bucket
#  should have a tar.bz2 file for each backup set, along with
#  at tar.contents.txt file listing the contents of the tar.bz2
#  file and a drop file listing the backed up set names.
#
#  The backups will be prepended with "daily/yyyy-mm-dd/" and
#  if required by the BackupSchedule module they will be copied
#  to weekly, monthly or bi_yearly folders in S3.
#
#  TODO: Eventually further extract into a base class that can
#        be used for database and resource backup jobs.
#
class S3Backup
  include FileUtils
  attr_reader :log
  
  def initialize(source_bucket, dest_bucket, datadir, &block)    
    @log = Logger.new(STDOUT)
    @source_bucket = source_bucket
    @dest_bucket   = dest_bucket
    @datadir       = File.expand_path(datadir)
    @timestamp     = Time.now
    @datestamp     = @timestamp.strftime("%Y-%m-%d")
    @sets = []
    
    @timestamp.extend(BackupSchedule)
    
    if block_given?
      Lockfile.new("#{$data_dir}/backup.lock").lock do
        begin
          instance_eval(&block)
          write_drop_file
        rescue Exception => e
          log.fatal("Exception occured: #{e}")
        end
      end
    end
  end
  
  # Create a backup set from the source bucket.
  #
  # This allows multiple sets from the same source
  # bucket to be created. The source bucket can be
  # partitioned using the :prefix option or by passing
  # a block to backup. The block should take a S3 key
  # name and return true if that object should be
  # included in the backup.
  #
  # + set_name: A label applied to the backup set.
  #             will be used for the tarfile name.
  #
  # Note that this method incrementally builds the tar
  # file and remove each S3 object file from the file
  # system as it is added to the tar file. This keeps
  # the number of temporary files to a minimum.
  #
  # TODO: Consider improving this to only access the source bucket once.
  #
  def backup(set_name, options = {})
    @sets << set_name
    tarfile = File.join(@datadir, "#{set_name}.tar")
    log.info("Querying Source Bucket")
    
    cd(@datadir) do
      @source_bucket.keys('prefix' => options[:prefix]).each do |key|
        if !block_given? || yield(key.name)
          log.info("Backing up #{key.name}")
          tempfile = copy_obj(key)
          add_to_tar(tarfile, tempfile)
          rm_temp(tempfile)
        end
      end
    end
    
    contents_file = "#{tarfile}.contents.txt"
    File.open(contents_file, "w") do |cnts|
      cnts << list_contents(tarfile)
    end
    
    archive_file = compress(tarfile)
    save_to_s3(archive_file)
    save_to_s3(contents_file)
  end
  
private
  def copy_obj(key)
    file_path = key.name
    FileUtils.mkdir_p(File.dirname(file_path))
    unless File.directory?(file_path)
      open(file_path, 'w') do |file|
        file.write(key.data)
      end
    end
    return file_path
  end
  
  def add_to_tar(tarfile, infile)
    `tar -rf #{tarfile} "#{infile}"`
  end
  
  # Remove a file and it's parent directories while they are empty
  def rm_temp(file)
    return if file == "."
    if File.directory?(file)
      if is_empty_dir?(file)
        rm_r(file)
        rm_temp(File.dirname(file))
      end
    else
      rm(file)
      rm_temp(File.dirname(file))
    end
  end
  
  def is_empty_dir?(path)
    Dir[File.join(path, "*")].empty?
  end
  
  def list_contents(tarfile)
    `tar -tf #{tarfile}`
  end
  
  def compress(file)
    `bzip2 #{file}`
    return "#{file}.bz2"
  end
  
  def save_to_s3(file)
    base_name = "#{@datestamp}/#{File.basename(file)}"
    key_name = "daily/#{base_name}"
    log.info("Saving #{file} to #{key_name} in #{@dest_bucket.name}")
    
    key = Aws::S3::Key.create(@dest_bucket, key_name)
    key.put(File.open(file))
    
    if @timestamp.weekly?
      log.info("Copying to weekly/ in #{@dest_bucket.name}")
      key.copy("weekly/#{base_name}")
    end
    
    if @timestamp.monthly?
      log.info("Copying to monthly/ in #{@dest_bucket.name}")
      key.copy("monthly/#{base_name}")
    end
    
    if @timestamp.half_yearly?
      log.info("Copying to bi_yearly/ in #{@dest_bucket.name}")
      key.copy("bi_yearly/#{base_name}")
    end
    
    return key
  end
  
  def write_drop_file
    name = "daily/#{@datestamp}/#{@sets.join("_")}.drop"
    key = Aws::S3::Key.create(@dest_bucket, name)
    key.put("backup of answers and documents completed at #{@timestamp}")
  end
end

data_dir = "/mnt"

# CodeFire
source_account = Aws::S3.new(
  '0VH2XJ540GSWV8MCBYG2', 
  'XFRQJjMzLIE6071pVQxSu7bKkQ9t1sdLBBfctr8e', 
  :connection_mode => :single
)

# Catapult
destination_account = Aws::S3.new(
  'AKIAJN3V2WRSXHZ3YIBA', 
  'M3TQFP829iFDc8QpBDQhjDXxEaSDE9Z9Lz0BNBhg', 
  :connection_mode => :single
)

source_bucket = source_account.bucket('catapult-elearning-staging')
destination_bucket = destination_account.bucket("catapult-backup")

S3Backup.new(source_bucket, destination_bucket, data_dir) do
  backup("answers", :prefix => "answers")
  
  backup("documents") do |key|
    [ /#{Regexp.escape('.$folder$')}$/,
      /#{Regexp.escape('_$folder$')}$/,
      %r{^backup},
      %r{^catapult-elearning:backups/},
      %r{^resources/},
      %r{^answers} ].none? { |regexp| key =~ regexp }
  end
end


# SG: I've remove the code from below that has been replaced by code above, but kept deletion stuff there for future reference.
#
# # TODO: Refactor to use aws gem
# def delete_file(file_to_delete, backup_bucket)
#   puts "deleting file #{file_to_delete}"
#   exists = AWS::S3::S3Object.exists?(file_to_delete, backup_bucket)
#   puts "#{file_to_delete} exists" if exists
#   AWS::S3::S3Object.delete(file_to_delete, backup_bucket) if exists
# end
# 
# # TODO: Don't think this is used anywhere
# def  get_all_files(backup_bucket) 
#   puts "getting all files"
#   AWS::S3::Bucket.find(backup_bucket)
# end
# 
# def number_of_backups_to_retain(backup_type)
#   f = 7 if backup_type =~ /daily/
#   f = 5 if backup_type =~ /weekly/
#   f = 12 if backup_type =~ /monthly/
#   f = 2 if backup_type =~ /yearly/
#   return f
# end
# 
# def remove_out_of_date_backups(backup_bucket, path, backupfile)
#   puts "entered remove_out_of_date_backups method"
#   puts "with path = #{path}"
#   date_stamp = 2
#   b = get_all_files(backup_bucket) 
#   c = [] # The list of dates representing the files that need to be deleted
#   files_to_delete = []
# 
#   # Build C
#   b.each do |file|
#     if file.inspect =~ %r(#{path}) && file.inspect =~ %r(#{backupfile}) && !file.inspect.include?('drop') && !file.key.split('.')[date_stamp].include?(/[a-zA-Z]/)
#        c.push(file.key.split('.')[date_stamp])
#     end
#   end
#   puts "b.inspect = #{b.inspect}"
#   puts "backupfile is #{backupfile}"
#   puts "c.inspect -> #{c.inspect}"
#   puts "c -> #{c}"
# 
#   # Convert c into Date objects
#   c.map! { |s| Date.parse(s) }
# 
#   puts "this is c -> #{c.inspect}"
# 
#   # Find and delete old backups
#   unless c.empty?
#     d = c.sort.uniq
#     puts "number of unique dates = #{d.size}"
#     number_of_backups = d.size
#     puts "number of backups is #{d.inspect}"
# 
#     files_to_delete = b.select do |file|
#       file.key =~ %r(#{d.first}) && file.key =~ %r(#{backupfile}) && file.inspect =~ %r(#{path})
#     end.map { |file| file.key }
# 
#     puts "files to delete = #{files_to_delete.inspect}"
#     puts "number_of_backups_to_retain is #{number_of_backups_to_retain(path)}"
#     puts "calling delete_file method" if number_of_backups >= number_of_backups_to_retain(path)
# 
#     files_to_delete.each do |file_to_delete|
#       if number_of_backups > number_of_backups_to_retain(path)
#         delete_file(file_to_delete, backup_bucket)
#       end
#     end
#   end
# end
