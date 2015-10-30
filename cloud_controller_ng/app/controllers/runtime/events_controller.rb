module VCAP::CloudController
  class EventsController < RestController::ModelController
    query_parameters :timestamp, :type, :actee

    def initialize(*args)
      super
      @opts.merge!(order_by: [:timestamp, :id])
    end
    #����guiɾ����Ӧ��model
    def delete(guid)
      do_delete(find_guid_and_validate_access(:delete, guid))
    end

    define_messages
    define_routes
  end
end
