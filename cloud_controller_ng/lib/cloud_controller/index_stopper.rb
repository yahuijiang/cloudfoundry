module VCAP::CloudController
  class IndexStopper
    def initialize(runners)
      @runners = runners
    end

    def stop_index(app, index)
      #���runner for app ��diego������http����һ��delete������

      #���runner for app ��dea�� ��stop dea����Ϣ���͵�messsage_bus��

      @runners.runner_for_app(app).stop_index(index)
    end
  end
end
