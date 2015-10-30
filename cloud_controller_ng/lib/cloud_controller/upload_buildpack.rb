module VCAP::CloudController
  class UploadBuildpack
    attr_reader :buildpack_blobstore
    #package的blob store
    def initialize(blobstore)
      @buildpack_blobstore = blobstore
    end
    #1.	如果buildpack的key不为空，但是buildpack在blobstore中不存在，则将buildpack复制到blobstore中
    #          a)	cp_to_blobstore(source_path, destination_key, retries=2)
    #             1.	根据source_path打开源文件，
    #             2.	每个文件进行files create，创建的文件的key为destination_key
    #2.	更新buildpack 的key为new_key ，filename为newfilenama
    #3.	如果blobstore中依旧存在旧的buildpack则删除
    def upload_buildpack(buildpack, bits_file, new_filename)
      return false if buildpack.locked

      sha1 = File.new(bits_file).hexdigest
      new_key = "#{buildpack.guid}_#{sha1}"
      #buildpack的key不空，但在blobstore 中不存在此key的文件，则认为文件丢失
      missing_bits = buildpack.key && !buildpack_blobstore.exists?(buildpack.key)

      return false if !new_bits?(buildpack, new_key) && !new_filename?(buildpack, new_filename) && !missing_bits

      # replace blob if new
      #如果biludpack 文件丢失或者buildpack的key和新的key不一样，则复制
      if missing_bits || new_bits?(buildpack, new_key)
        buildpack_blobstore.cp_to_blobstore(bits_file, new_key)#对每个源文件，在blobstore中创建一个文件来存储该文件，创建的文件的key是新的key
      end

      old_buildpack_key = nil

      begin
        Buildpack.db.transaction do
          buildpack.lock!
          old_buildpack_key = buildpack.key
          buildpack.update_from_hash(key: new_key, filename: new_filename)#更新buildpack
        end
      rescue Sequel::Error
        BuildpackBitsDelete.delete_when_safe(new_key, 0)
        return false
      end

      if !missing_bits && old_buildpack_key && new_bits?(buildpack, old_buildpack_key)#如果依旧存在老的package则进行删除掉
        staging_timeout = VCAP::CloudController::Config.config[:staging][:timeout_in_seconds]
        BuildpackBitsDelete.delete_when_safe(old_buildpack_key, staging_timeout)
      end

      true
    end

    private
#如果buildpack 的key 和参数key不等，则认为是新的
    def new_bits?(buildpack, key)
      buildpack.key != key
    end

    def new_filename?(buildpack, filename)
      buildpack.filename != filename
    end
  end
end
