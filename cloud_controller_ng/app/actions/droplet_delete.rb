module VCAP::CloudController
  class DropletDelete
    def delete(droplets)
      droplets = [droplets] unless droplets.is_a?(Array)
    #从blog中删除相应的droplet,生成一个blobstoredelete对象，放入队列中
      droplets.each do |droplet|#删除blobstore
        if droplet.blobstore_key
          blobstore_delete = Jobs::Runtime::BlobstoreDelete.new(droplet.blobstore_key, :droplet_blobstore, nil)
          Jobs::Enqueuer.new(blobstore_delete, queue: 'cc-generic').enqueue
        end

        droplet.destroy#销毁droplet
      end
    end
  end
end
