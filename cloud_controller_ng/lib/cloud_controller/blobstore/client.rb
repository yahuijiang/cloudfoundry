require 'fileutils'
require 'find'
require 'fog'
require 'cloud_controller/blobstore/directory'
require 'cloud_controller/blobstore/blob'
require 'cloud_controller/blobstore/idempotent_directory'

module CloudController
  module Blobstore
    class Client
      class FileNotFound < StandardError
      end
      #client new，connection 的配置文件，dir_key，cdn，根目录。。。
      def initialize(connection_config, directory_key, cdn=nil, root_dir=nil, min_size=nil, max_size=nil)
        @root_dir = root_dir
        @connection_config = connection_config
        @directory_key = directory_key
        @cdn = cdn
        @min_size = min_size || 0
        @max_size = max_size
      end

      def local?
        @connection_config[:provider].downcase == 'local'
      end
      #blob store中是否存在key的文件
      def exists?(key)
        !file(key).nil?
      end

      def download_from_blobstore(source_key, destination_path)
        FileUtils.mkdir_p(File.dirname(destination_path))
        File.open(destination_path, 'w') do |file|
          (@cdn || files).get(partitioned_key(source_key)) do |*chunk|
            file.write(chunk[0])
          end
        end
      end

      def cp_r_to_blobstore(source_dir)
        Find.find(source_dir).each do |path|
          next unless File.file?(path)
          next unless within_limits?(File.size(path))

          sha1 = Digest::SHA1.file(path).hexdigest
          next if exists?(sha1)

          cp_to_blobstore(path, sha1)
        end
      end
      #将源文件从source_path copy 到blobdtore 上，retries次数为两次
      def cp_to_blobstore(source_path, destination_key, retries=2)
        start = Time.now.utc
        logger.info('blobstore.cp-start', destination_key: destination_key, source_path: source_path, bucket: @directory_key)
        size = -1
        log_entry = 'blobstore.cp-skip'

        File.open(source_path) do |file|#打开原路径中的每个文件
          size = file.size
          next unless within_limits?(size)

          begin
            mime_type = MIME::Types.of(source_path).first.try(:content_type)

            files.create(#每个文件进行files create，创建的文件的key为目标key
              key: partitioned_key(destination_key),
              body: file,
              content_type: mime_type || 'application/zip',
              public: local?,
            )
          # work around https://github.com/fog/fog/issues/3137
          # and Fog raising an EOFError SocketError intermittently
          rescue SystemCallError, Excon::Errors::SocketError, Excon::Errors::BadRequest => e
            logger.debug('blobstore.cp-retry',
                         error: e,
                         destination_key: destination_key,
                         remaining_retries: retries
                        )
            retries -= 1
            retry unless retries < 0
            raise e
          end

          log_entry = 'blobstore.cp-finish'
        end

        duration = Time.now.utc - start
        logger.info(log_entry,
                    destination_key: destination_key,
                    duration_seconds: duration,
                    size: size,
                   )
      end

      def cp_file_between_keys(source_key, destination_key)
        #查找要copy的源文件
        source_file = file(source_key)
        raise FileNotFound if source_file.nil?
        source_file.copy(@directory_key, partitioned_key(destination_key))

        dest_file = file(destination_key)#将destfile 赋值为destination_key指向的file

        if local?
          dest_file.public = 'public-read'
        end
        dest_file.save
      end

      def delete_all(page_size=1000)
        logger.info("Attempting to delete all files in #{@directory_key}/#{@root_dir} blobstore")

        files_to_destroy = []

        files.each do |blobstore_file|
          next unless /#{@root_dir}/.match(blobstore_file.key)
#设计思路的优点：虽然现在不支持multiple delete，但是为未来做了预留！！！！！！
          files_to_destroy << blobstore_file
          if files_to_destroy.length == page_size#每次删除1000个
            delete_files(files_to_destroy)#删除所有的file，#如果server支持multiple delete则进行delete_multiple_objects，否则删除
            files_to_destroy = []
          end
        end

        if files_to_destroy.length > 0
          delete_files(files_to_destroy)
        end
      end

      def delete_files(files_to_delete)
        #如果支持multiple delete则进行delete_multiple_objects，否则删除
        if connection.respond_to?(:delete_multiple_objects)
          # AWS needs the file key to work; other providers with multiple delete
          # are currently not supported. When support is added this code may
          # need an update.
          keys = files_to_delete.collect(&:key)
          connection.delete_multiple_objects(@directory_key, keys)
        else
          files_to_delete.each { |f| delete_file(f) }
        end
      end

      def delete(key)
        blob_file = file(key)
        delete_file(blob_file) if blob_file
      end
      #如果blob的file不为空的话则删除相应的file
      def delete_blob(blob)
        delete_file(blob.file) if blob.file
      end

      def download_uri(key)
        b = blob(key)
        b.download_url if b
      end
    #如果fog storage中村在key的file则创建一个新的Blob
      def blob(key)
        f = file(key)#根据k来判断在fog storage是否存在该文件
        Blob.new(f, @cdn) if f
      end

      # Deprecated should not allow to access underlying files
      #返回storage中的dir中的files，
      def files
        dir.files
      end

      private
      #销毁每个file
      def delete_file(file)
        file.destroy
      end
      #根据key找到blobstore中的相应的file
      def file(key)
        files.head(partitioned_key(key))
      end
      #将key连接在一起
      def partitioned_key(key)
        key = key.to_s.downcase
        key = File.join(key[0..1], key[2..3], key)
        if @root_dir
          key = File.join(@root_dir, key)
        end
        key
      end
      #返回一个fog storage dirctory，如果不存在则新建一个
      def dir
        @dir ||= directory.get_or_create
      end
      #IdempotentDirectory目录等于director目录
      def directory
        @directory ||= IdempotentDirectory.new(Directory.new(connection, @directory_key))#通过fog的storage和key生成一个connection，
        # connection中含有一个 directory，connection就是一个storage
      end
      #返回一个由connection_config 决定的fog的storage，
      def connection
        options = @connection_config
        options = options.merge(endpoint: '') if local?
        @connection ||= Fog::Storage.new(options)
      end

      def logger
        @logger ||= Steno.logger('cc.blobstore')
      end

      def within_limits?(size)
        size >= @min_size && (@max_size.nil? || size <= @max_size)
      end
    end
  end
end
