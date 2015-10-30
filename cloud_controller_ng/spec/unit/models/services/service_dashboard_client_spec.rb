require 'spec_helper'

module VCAP::CloudController
  describe ServiceDashboardClient do
    let(:service_broker) { ServiceBroker.make }
    let(:other_broker) { ServiceBroker.make }
    let(:uaa_id) { 'claimed_client_id' }

    it { is_expected.to have_timestamp_columns }

    describe 'Associations' do
      it { is_expected.to have_associated :service_broker }
    end

    describe 'Validations' do
      it { is_expected.to validate_presence :uaa_id }
      it { is_expected.to validate_uniqueness :uaa_id }

      context 'when all fields are valid' do
        let(:client) { ServiceDashboardClient.make_unsaved(service_broker: service_broker) }

        it 'is valid' do
          expect(client).to be_valid
        end
      end
    end

    describe '.find_clients_claimed_by_broker' do
      before do
        ServiceDashboardClient.claim_client('client-1', service_broker)
        ServiceDashboardClient.claim_client('client-2', other_broker)
        ServiceDashboardClient.claim_client('client-3', service_broker)
      end

      it 'returns all clients claimed by the broker' do
        results = ServiceDashboardClient.find_claimed_client(service_broker)
        expect(results).to have(2).entries
        expect(results.map(&:uaa_id)).to match_array ['client-1', 'client-3']
      end
    end

    describe '.claim_client_for_broker' do
      context 'when the client is unclaimed' do
        it 'claims the client for the broker' do
          expect {
            ServiceDashboardClient.claim_client(uaa_id, service_broker)
          }.to change {
            ServiceDashboardClient.client_claimed?(uaa_id, service_broker)
          }.to(true)
        end
      end

      context 'when a claim without a broker id exists' do
        before do
          ServiceDashboardClient.make(service_broker: nil, uaa_id: uaa_id)
        end

        it 'claims the client for the broker' do
          expect {
            ServiceDashboardClient.claim_client(uaa_id, service_broker)
          }.to change {
            ServiceDashboardClient.client_claimed?(uaa_id, service_broker)
          }.to(true)
        end
      end

      context 'when the client is already claimed by another broker' do
        before do
          ServiceDashboardClient.claim_client(uaa_id, other_broker)
        end

        it 'raises an exception' do
          expect {
            ServiceDashboardClient.claim_client(uaa_id, service_broker)
          }.to raise_exception(Sequel::ValidationFailed)
        end
      end

      context 'when the client is already claimed by the specified broker' do
        before do
          ServiceDashboardClient.claim_client(uaa_id, service_broker)
        end

        it 'does not change the fact that the client is claimed by the broker' do
          expect {
            ServiceDashboardClient.claim_client(uaa_id, service_broker)
          }.not_to change {
            ServiceDashboardClient.client_claimed?(uaa_id, service_broker)
          }
        end
      end
    end

    describe '.remove_claim_on_client' do
      before do
        ServiceDashboardClient.claim_client(uaa_id, service_broker)
      end

      it 'removes the claim' do
        expect {
          ServiceDashboardClient.release_client(uaa_id)
        }.to change { ServiceDashboardClient.client_claimed?(uaa_id, service_broker) }.to(false)
      end
    end

    describe '.find_client_by_uaa_id' do
      context 'when no clients with the specified uaa_id exist' do
        it 'returns nil' do
          expect(ServiceDashboardClient.find_client_by_uaa_id('some-uaa-id')).to be_nil
        end
      end

      context 'when one client exists with the specified uaa_id' do
        let!(:client) {
          ServiceDashboardClient.make(uaa_id: 'some-uaa-id', service_broker: nil)
        }

        it 'returns the client' do
          expect(ServiceDashboardClient.find_client_by_uaa_id('some-uaa-id')).to eq(client)
        end
      end
    end
  end

  describe ServiceInstanceDashboardClient do
    let(:service_instance) { ManagedServiceInstance.make }
    let(:other_instance) { ManagedServiceInstance.make }
    let(:uaa_id) { 'claimed_client_id' }

    it { is_expected.to have_timestamp_columns }

    describe 'Associations' do
      it { is_expected.to have_associated :managed_service_instance }
    end

    describe 'Validations' do
      it { is_expected.to validate_presence :uaa_id }
      it { is_expected.to validate_uniqueness :uaa_id }

      context 'when all fields are valid' do
        let(:client) { ServiceInstanceDashboardClient.make_unsaved(managed_service_instance: service_instance) }

        it 'is valid' do
          expect(client).to be_valid
        end
      end
    end

    describe '.find_claimed_client' do
      before do
        ServiceInstanceDashboardClient.claim_client('client-1', service_instance)
        ServiceInstanceDashboardClient.claim_client('client-2', other_instance)
        ServiceInstanceDashboardClient.claim_client('client-3', service_instance)
      end

      it 'returns all clients claimed' do
        results = ServiceInstanceDashboardClient.find_claimed_client(service_instance)
        expect(results).to have(2).entries
        expect(results.map(&:uaa_id)).to match_array ['client-1', 'client-3']
      end
    end

    describe '.claim_client' do
      context 'when the client is unclaimed' do
        it 'claims the client' do
          expect {
            ServiceInstanceDashboardClient.claim_client(uaa_id, service_instance)
          }.to change {
            ServiceInstanceDashboardClient.client_claimed?(uaa_id, service_instance)
          }.to(true)
        end
      end

      context 'when a claim without a service instance exists' do
        before do
          ServiceInstanceDashboardClient.make(managed_service_instance: nil, uaa_id: uaa_id)
        end

        it 'claims the client for the service instance' do
          expect {
            ServiceInstanceDashboardClient.claim_client(uaa_id, service_instance)
          }.to change {
            ServiceInstanceDashboardClient.client_claimed?(uaa_id, service_instance)
          }.to(true)
        end
      end

      context 'when the client is already claimed by another service instance' do
        before do
          ServiceInstanceDashboardClient.claim_client(uaa_id, other_instance)
        end

        it 'raises an exception' do
          expect {
            ServiceInstanceDashboardClient.claim_client(uaa_id, service_instance)
          }.to raise_exception(Sequel::ValidationFailed)
        end
      end

      context 'when the client is already claimed by the specified service instance' do
        before do
          ServiceInstanceDashboardClient.claim_client(uaa_id, service_instance)
        end

        it 'does not change the fact that the client is claimed by the service instance' do
          expect {
            ServiceInstanceDashboardClient.claim_client(uaa_id, service_instance)
          }.not_to change {
            ServiceInstanceDashboardClient.client_claimed?(uaa_id, service_instance)
          }
        end
      end
    end

    describe '.release_client' do
      before do
        ServiceInstanceDashboardClient.claim_client(uaa_id, service_instance)
      end

      it 'removes the claim' do
        expect {
          ServiceInstanceDashboardClient.release_client(uaa_id)
        }.to change { ServiceInstanceDashboardClient.client_claimed?(uaa_id, service_instance) }.to(false)
      end
    end

    describe '.find_client_by_uaa_id' do
      context 'when no clients with the specified uaa_id exist' do
        it 'returns nil' do
          expect(ServiceInstanceDashboardClient.find_client_by_uaa_id('some-uaa-id')).to be_nil
        end
      end

      context 'when one client exists with the specified uaa_id' do
        let!(:client) {
          ServiceInstanceDashboardClient.make(uaa_id: 'some-uaa-id', managed_service_instance: nil)
        }

        it 'returns the client' do
          expect(ServiceInstanceDashboardClient.find_client_by_uaa_id('some-uaa-id')).to eq(client)
        end
      end
    end
  end
end