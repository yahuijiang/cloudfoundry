module VCAP::CloudController
  class IndexStopper
    def initialize(runners)
      @runners = runners
    end

    def stop_index(app, index)
      #如果runner for app 是diego，则想http发送一个delete的请求

      #如果runner for app 是dea， 则将stop dea的消息发送到messsage_bus中

      @runners.runner_for_app(app).stop_index(index)
    end
  end
end
