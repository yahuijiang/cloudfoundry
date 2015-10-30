module VCAP::CloudController
  class ProcessDelete
    def delete(processes)
      processes = [processes] unless processes.is_a?(Array)
      #销毁相应的进程
      processes.each(&:destroy)
    end
  end
end
