module VCAP::CloudController
  module Jobs
    module Runtime
      class BlobstoreDelete < VCAP::CloudController::Jobs::CCJob
        attr_accessor :key, :blobstore_name, :attributes

        def initialize(key, blobstore_name, attributes=nil)
          @key = key
          @blobstore_name = blobstore_name
          @attributes = attributes
        end
        #删除blobstore中的file
        def perform
          logger = Steno.logger('cc.background')
          logger.info("Attempting delete of '#{key}' from blobstore '#{blobstore_name}'")

          blobstore = CloudController::DependencyLocator.instance.public_send(blobstore_name)
          blob = blobstore.blob(key)#如果fog storage中村在key的file则创建一个新的Blob
          if blob && same_blob(blob)
            logger.info("Deleting '#{key}' from blobstore '#{blobstore_name}'")
            blobstore.delete_blob(blob)#如果blob 的file不为空，则调用blobstore client 来删除blob file
          end
        end

        def job_name_in_configuration
          :blobstore_delete
        end

        def max_attempts
          3
        end

        private

        def same_blob(blob)
          return true if attributes.nil?
          blob.attributes(*attributes.keys) == attributes
        end
      end
    end
  end
end
