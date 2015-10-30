module VCAP::CloudController
  class UploadBuildpack
    attr_reader :buildpack_blobstore
    #package��blob store
    def initialize(blobstore)
      @buildpack_blobstore = blobstore
    end
    #1.	���buildpack��key��Ϊ�գ�����buildpack��blobstore�в����ڣ���buildpack���Ƶ�blobstore��
    #          a)	cp_to_blobstore(source_path, destination_key, retries=2)
    #             1.	����source_path��Դ�ļ���
    #             2.	ÿ���ļ�����files create���������ļ���keyΪdestination_key
    #2.	����buildpack ��keyΪnew_key ��filenameΪnewfilenama
    #3.	���blobstore�����ɴ��ھɵ�buildpack��ɾ��
    def upload_buildpack(buildpack, bits_file, new_filename)
      return false if buildpack.locked

      sha1 = File.new(bits_file).hexdigest
      new_key = "#{buildpack.guid}_#{sha1}"
      #buildpack��key���գ�����blobstore �в����ڴ�key���ļ�������Ϊ�ļ���ʧ
      missing_bits = buildpack.key && !buildpack_blobstore.exists?(buildpack.key)

      return false if !new_bits?(buildpack, new_key) && !new_filename?(buildpack, new_filename) && !missing_bits

      # replace blob if new
      #���biludpack �ļ���ʧ����buildpack��key���µ�key��һ��������
      if missing_bits || new_bits?(buildpack, new_key)
        buildpack_blobstore.cp_to_blobstore(bits_file, new_key)#��ÿ��Դ�ļ�����blobstore�д���һ���ļ����洢���ļ����������ļ���key���µ�key
      end

      old_buildpack_key = nil

      begin
        Buildpack.db.transaction do
          buildpack.lock!
          old_buildpack_key = buildpack.key
          buildpack.update_from_hash(key: new_key, filename: new_filename)#����buildpack
        end
      rescue Sequel::Error
        BuildpackBitsDelete.delete_when_safe(new_key, 0)
        return false
      end

      if !missing_bits && old_buildpack_key && new_bits?(buildpack, old_buildpack_key)#������ɴ����ϵ�package�����ɾ����
        staging_timeout = VCAP::CloudController::Config.config[:staging][:timeout_in_seconds]
        BuildpackBitsDelete.delete_when_safe(old_buildpack_key, staging_timeout)
      end

      true
    end

    private
#���buildpack ��key �Ͳ���key���ȣ�����Ϊ���µ�
    def new_bits?(buildpack, key)
      buildpack.key != key
    end

    def new_filename?(buildpack, filename)
      buildpack.filename != filename
    end
  end
end
