require 'jobs/services/service_instance_state_fetch'

module VCAP::Services::ServiceBrokers::V2
  class Client
    CATALOG_PATH = '/v2/catalog'.freeze

    attr_reader :orphan_mitigator, :attrs

    def initialize(attrs)
      http_client_attrs = attrs.slice(:url, :auth_username, :auth_password)
      @http_client = VCAP::Services::ServiceBrokers::V2::HttpClient.new(http_client_attrs)
      @response_parser = VCAP::Services::ServiceBrokers::V2::ResponseParser.new(@http_client.url)
      @attrs = attrs
      @orphan_mitigator = VCAP::Services::ServiceBrokers::V2::OrphanMitigator.new
    end

    def catalog
      response = @http_client.get(CATALOG_PATH)
      @response_parser.parse_catalog(CATALOG_PATH, response)
    end

    def provision(instance, arbitrary_parameters: {}, accepts_incomplete: false)
      path = service_instance_resource_path(instance, accepts_incomplete: accepts_incomplete)

      body = {
        service_id: instance.service.broker_provided_id,
        plan_id: instance.service_plan.broker_provided_id,
        organization_guid: instance.organization.guid,
        space_guid: instance.space.guid,
      }

      body[:parameters] = arbitrary_parameters if arbitrary_parameters.present?
      response = @http_client.put(path, body)

      parsed_response = @response_parser.parse_provision(path, response)
      last_operation_hash = parsed_response['last_operation'] || {}
      return_values = {
        instance: {
          credentials: {},
          dashboard_url: parsed_response['dashboard_url']
        },
        dashboard_client: parsed_response['dashboard_client'],
        last_operation: {
          type: 'create',
          description: last_operation_hash['description'] || '',
        }
      }

      state = last_operation_hash['state']
      if state
        return_values[:last_operation][:state] = state
      else
        return_values[:last_operation][:state] = 'succeeded'
      end

      return_values
    rescue Errors::ServiceBrokerApiTimeout, Errors::ServiceBrokerBadResponse => e
      @orphan_mitigator.cleanup_failed_provision(@attrs, instance)
      raise e
    rescue Errors::ServiceBrokerResponseMalformed => e
      @orphan_mitigator.cleanup_failed_provision(@attrs, instance) unless e.status == 200
      raise e
    end

    def fetch_service_instance_state(instance)
      path = service_instance_last_operation_path(instance)
      response = @http_client.get(path)
      parsed_response = @response_parser.parse_fetch_state(path, response)
      last_operation_hash = parsed_response.delete('last_operation') || {}

      state = extract_state(instance, last_operation_hash)

      result = {
        last_operation:
          {
            state: state
          }
      }

      result[:last_operation][:description] = last_operation_hash['description'] if last_operation_hash['description']
      result.merge(parsed_response.symbolize_keys)
    end

    def create_service_key(key, arbitrary_parameters: {})
      path = service_binding_resource_path(key)
      body = {
          service_id:  key.service.broker_provided_id,
          plan_id:     key.service_plan.broker_provided_id
      }

      body[:parameters] = arbitrary_parameters if arbitrary_parameters.present?

      response = @http_client.put(path, body)
      parsed_response = @response_parser.parse_bind(path, response, service_guid: key.service.guid)

      attributes = {
        credentials: parsed_response['credentials']
      }

      attributes
    rescue Errors::ServiceBrokerApiTimeout, Errors::ServiceBrokerBadResponse => e
      @orphan_mitigator.cleanup_failed_key(@attrs, key)
      raise e
    end

    def bind(binding, arbitrary_parameters: {})
      path = service_binding_resource_path(binding)
      body = {
          service_id:  binding.service.broker_provided_id,
          plan_id:     binding.service_plan.broker_provided_id,
          app_guid:    binding.app_guid
      }

      body[:parameters] = arbitrary_parameters if arbitrary_parameters.present?

      response = @http_client.put(path, body)
      parsed_response = @response_parser.parse_bind(path, response, service_guid: binding.service.guid)

      attributes = {
        credentials: parsed_response['credentials']
      }
      if parsed_response.key?('syslog_drain_url')
        attributes[:syslog_drain_url] = parsed_response['syslog_drain_url']
      end

      attributes
    rescue Errors::ServiceBrokerApiTimeout,
           Errors::ServiceBrokerBadResponse,
           Errors::ServiceBrokerInvalidSyslogDrainUrl => e
      @orphan_mitigator.cleanup_failed_bind(@attrs, binding)
      raise e
    end

    def unbind(binding)
      path = service_binding_resource_path(binding)

      body = {
        service_id: binding.service.broker_provided_id,
        plan_id: binding.service_plan.broker_provided_id,
      }
      #调用httpclient 发出http delete 请求
      response = @http_client.delete(path, body)

      @response_parser.parse_unbind(path, response)
    rescue => e
      raise e.exception("Service instance #{binding.service_instance.name}: #{e.message}")
    end
      #通过http client进行post delete请求
    def deprovision(instance, accepts_incomplete: false)
      path = service_instance_resource_path(instance)

      body = {
        service_id: instance.service.broker_provided_id,
        plan_id:    instance.service_plan.broker_provided_id,
      }
      body.merge!(accepts_incomplete: true) if accepts_incomplete
      response = @http_client.delete(path, body)

      parsed_response = @response_parser.parse_deprovision(path, response) || {}
      last_operation_hash = parsed_response['last_operation'] || {}
      state = last_operation_hash['state']

      {
        last_operation: {
          type: 'delete',
          description: last_operation_hash['description'] || '',
          state: state || 'succeeded'
        }
      }
    rescue VCAP::Services::ServiceBrokers::V2::Errors::ServiceBrokerConflict => e
      raise VCAP::Errors::ApiError.new_from_details('ServiceInstanceDeprovisionFailed', e.message)
    rescue => e
      raise e.exception("Service instance #{instance.name}: #{e.message}")
    end

    def update(instance, plan, accepts_incomplete: false, arbitrary_parameters: nil, previous_values: {})
      path = service_instance_resource_path(instance, accepts_incomplete: accepts_incomplete)

      body = {
        service_id: instance.service.broker_provided_id,
        plan_id: plan.broker_provided_id,
        previous_values: previous_values
      }
      body[:parameters] = arbitrary_parameters if arbitrary_parameters
      response = @http_client.patch(path, body)

      parsed_response = @response_parser.parse_update(path, response)
      last_operation_hash = parsed_response['last_operation'] || {}
      state = last_operation_hash['state'] || 'succeeded'

      attributes = {
        last_operation: {
          type: 'update',
          state: state,
          description: last_operation_hash['description'] || '',
        },
      }

      if state == 'succeeded'
        attributes[:service_plan] = plan
      elsif state == 'in progress'
        attributes[:last_operation][:proposed_changes] = { service_plan_guid: plan.guid }
      end

      return attributes, nil
    rescue Errors::ServiceBrokerBadResponse,
           Errors::ServiceBrokerApiTimeout,
           Errors::ServiceBrokerResponseMalformed,
           Errors::ServiceBrokerRequestRejected,
           Errors::AsyncRequired => e

      attributes = {
        last_operation: {
          state: 'failed',
          type: 'update',
          description: e.message
        }
      }
      return attributes, e
    end

    private

    def extract_state(instance, last_operation_hash)
      return last_operation_hash['state'] unless last_operation_hash.empty?

      if instance.last_operation.type == 'delete'
        'succeeded'
      else
        'failed'
      end
    end

    def service_instance_last_operation_path(instance)
      "#{service_instance_resource_path(instance)}/last_operation"
    end

    def service_binding_resource_path(binding)
      "/v2/service_instances/#{binding.service_instance.guid}/service_bindings/#{binding.guid}"
    end

    def service_instance_resource_path(instance, opts={})
      path = "/v2/service_instances/#{instance.guid}"
      if opts[:accepts_incomplete]
        path += '?accepts_incomplete=true'
      end
      path
    end
  end
end
