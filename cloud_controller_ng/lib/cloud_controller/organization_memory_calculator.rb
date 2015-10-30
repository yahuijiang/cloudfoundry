module VCAP::CloudController
  class OrganizationMemoryCalculator
    def self.get_memory_usage(org)
      memory_usage = 0
      #属于当前org的所有space
      spaces = Space.where(organization: org)
      #memory_useage 是当前org下的所有space中所有app memory*app的instance个数
      spaces.eager(:apps).all do |space|
        space.apps.each do |app|
          memory_usage += app.memory * app.instances if app.started?
        end
      end

      memory_usage
    end
  end
end
