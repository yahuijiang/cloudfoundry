module VCAP::CloudController
  class PaginatedResult
    attr_reader :records, :total, :pagination_options
#app表中记录分页后的对象
    def initialize(records, total, pagination_options)
      @records            = records
      @total              = total
      @pagination_options = pagination_options
    end
  end
end
