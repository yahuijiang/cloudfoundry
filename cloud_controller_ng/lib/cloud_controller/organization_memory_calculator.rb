module VCAP::CloudController
  class OrganizationMemoryCalculator
    def self.get_memory_usage(org)
      memory_usage = 0
      #���ڵ�ǰorg������space
      spaces = Space.where(organization: org)
      #memory_useage �ǵ�ǰorg�µ�����space������app memory*app��instance����
      spaces.eager(:apps).all do |space|
        space.apps.each do |app|
          memory_usage += app.memory * app.instances if app.started?
        end
      end

      memory_usage
    end
  end
end
