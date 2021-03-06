module VCAP::CloudController
  module Jobs
    module V3
      class DropletUpload
        attr_reader :max_attempts

        def initialize(local_path, droplet_guid)
          @local_path   = local_path
          @droplet_guid = droplet_guid
          @max_attempts = 3
        end
        #根据droplet_id查找droplet, 如果存在则cp_to_blobstore到此droplet上，最后更新droplet该model（也即数据库）
        def perform
          droplet = DropletModel.find(guid: @droplet_guid)

          if droplet
            digest = Digest::SHA1.file(@local_path).hexdigest

            blobstore.cp_to_blobstore(
              @local_path,
              File.join(@droplet_guid, digest)
            )

            droplet.update(droplet_hash: digest)
          end

          FileUtils.rm_f(@local_path)
        end

        def error(job, _)
          if !File.exist?(@local_path)
            @max_attempts = 1
          end

          if job.attempts >= max_attempts - 1
            FileUtils.rm_f(@local_path)
          end
        end

        def job_name_in_configuration
          :droplet_upload
        end

        def blobstore
          @blobstore ||= CloudController::DependencyLocator.instance.droplet_blobstore
        end
      end
    end
  end
end
