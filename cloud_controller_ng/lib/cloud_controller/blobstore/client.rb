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
      #client new��connection �������ļ���dir_key��cdn����Ŀ¼������
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
      #blob store���Ƿ����key���ļ�
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
      #��Դ�ļ���source_path copy ��blobdtore �ϣ�retries����Ϊ����
      def cp_to_blobstore(source_path, destination_key, retries=2)
        start = Time.now.utc
        logger.info('blobstore.cp-start', destination_key: destination_key, source_path: source_path, bucket: @directory_key)
        size = -1
        log_entry = 'blobstore.cp-skip'

        File.open(source_path) do |file|#��ԭ·���е�ÿ���ļ�
          size = file.size
          next unless within_limits?(size)

          begin
            mime_type = MIME::Types.of(source_path).first.try(:content_type)

            files.create(#ÿ���ļ�����files create���������ļ���keyΪĿ��key
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
        #����Ҫcopy��Դ�ļ�
        source_file = file(source_key)
        raise FileNotFound if source_file.nil?
        source_file.copy(@directory_key, partitioned_key(destination_key))

        dest_file = file(destination_key)#��destfile ��ֵΪdestination_keyָ���file

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
#���˼·���ŵ㣺��Ȼ���ڲ�֧��multiple delete������Ϊδ������Ԥ��������������
          files_to_destroy << blobstore_file
          if files_to_destroy.length == page_size#ÿ��ɾ��1000��
            delete_files(files_to_destroy)#ɾ�����е�file��#���server֧��multiple delete�����delete_multiple_objects������ɾ��
            files_to_destroy = []
          end
        end

        if files_to_destroy.length > 0
          delete_files(files_to_destroy)
        end
      end

      def delete_files(files_to_delete)
        #���֧��multiple delete�����delete_multiple_objects������ɾ��
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
      #���blob��file��Ϊ�յĻ���ɾ����Ӧ��file
      def delete_blob(blob)
        delete_file(blob.file) if blob.file
      end

      def download_uri(key)
        b = blob(key)
        b.download_url if b
      end
    #���fog storage�д���key��file�򴴽�һ���µ�Blob
      def blob(key)
        f = file(key)#����k���ж���fog storage�Ƿ���ڸ��ļ�
        Blob.new(f, @cdn) if f
      end

      # Deprecated should not allow to access underlying files
      #����storage�е�dir�е�files��
      def files
        dir.files
      end

      private
      #����ÿ��file
      def delete_file(file)
        file.destroy
      end
      #����key�ҵ�blobstore�е���Ӧ��file
      def file(key)
        files.head(partitioned_key(key))
      end
      #��key������һ��
      def partitioned_key(key)
        key = key.to_s.downcase
        key = File.join(key[0..1], key[2..3], key)
        if @root_dir
          key = File.join(@root_dir, key)
        end
        key
      end
      #����һ��fog storage dirctory��������������½�һ��
      def dir
        @dir ||= directory.get_or_create
      end
      #IdempotentDirectoryĿ¼����directorĿ¼
      def directory
        @directory ||= IdempotentDirectory.new(Directory.new(connection, @directory_key))#ͨ��fog��storage��key����һ��connection��
        # connection�к���һ�� directory��connection����һ��storage
      end
      #����һ����connection_config ������fog��storage��
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
