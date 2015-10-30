require "spec_helper"
require "dea/config"

module Dea
  describe Config do

    subject(:config) { described_class.new(config_hash) }
    let(:disk_inode_limit) { 123456 }

    describe ".from_file" do
      let(:file_path) { File.expand_path("../../../config/dea.yml", __FILE__) }
      subject { described_class.from_file(file_path) }

      it "can load" do
        should be_a(described_class)
      end
    end

    describe "#initialize" do
      let(:config_hash) { { } }

      it "can load" do
        should be_a(described_class)
      end

      describe "the available keys and values" do
        let(:config_as_hash) do
          config.inject({}) do |hash, kv|
            hash[kv[0]] = kv[1]
            hash
          end
        end

        it "has the expected default keys" do
          config_as_hash.keys.should eq(Config::EMPTY_CONFIG.keys)
        end

        it "has the expected default values" do
          config_as_hash.values.should eq(Config::EMPTY_CONFIG.values)
        end
      end
    end

    describe "#placement_properties" do
      context "when the config hash has no key for placement_properties:" do
        let(:config_hash) { { } }

        it "has a sane default" do
          config["placement_properties"].should == { "zone" => "default" }
        end
      end

      context "when the config hash has a key for placement_properties:" do
        let(:config_hash) { { "placement_properties" => { "zone" => "CRAZY_TOWN" } } }

        it "uses the zone provided by the hash" do
          config["placement_properties"].should == { "zone" => "CRAZY_TOWN" }
        end
      end
    end

    describe "#staging_disk_inode_limit" do
      context "when the config hash has no key for staging disk inode limit" do
        let(:config_hash) { { "staging" => { } } }

        it "is 200_000 or larger" do
          expect(described_class::DEFAULT_STAGING_DISK_INODE_LIMIT).to be >= 200_000
        end

        it "provides a reasonable default" do
          expect(config.staging_disk_inode_limit).to eq(described_class::DEFAULT_STAGING_DISK_INODE_LIMIT)
        end
      end

      context "when the config hash has a key for staging disk inode limit" do
        let(:config_hash) { { "staging" => { "disk_inode_limit" => disk_inode_limit } } }

        it "provides a reasonable default" do
          expect(config.staging_disk_inode_limit).to eq(disk_inode_limit)
        end
      end
    end

    describe '#rootfs_path' do
      let(:stacks) do
        [
          {
            'name' => 'my-stack',
            'package_path' => '/path/to/rootfs',
          }
        ]
      end
      let(:config_hash) { { 'stacks' => stacks } }

      context 'when the stack name exists in the config' do
        let(:stack_name) { 'my-stack' }
        it 'returns the associated rootfs path' do
          expect(config.rootfs_path(stack_name)).to eq('/path/to/rootfs')
        end
      end

      context 'when the stack name does not exist in the config' do
        it 'raises an error' do
          expect(config.rootfs_path('not-exist')).to be_nil
        end
      end
    end

    describe "#instance_disk_inode_limit" do
      context "when the config hash has no key for instance disk inode limit" do
        let(:config_hash) { { "instance" => { } } }

        it "is 200_000 or larger" do
          expect(described_class::DEFAULT_INSTANCE_DISK_INODE_LIMIT).to be >= 200_000
        end

        it "provides a reasonable default" do
          expect(config.instance_disk_inode_limit).to eq(described_class::DEFAULT_INSTANCE_DISK_INODE_LIMIT)
        end
      end

      context "when the config hash has a key for instance disk inode limit" do
        let(:config_hash) { { "instance" => { "disk_inode_limit" => disk_inode_limit } } }

        it "provides a reasonable default" do
          expect(config.instance_disk_inode_limit).to eq(disk_inode_limit)
        end
      end
    end

    describe "registration interval validation" do
      context "when the interval is greater than zero" do
        let(:config_hash) { { "intervals" => { "router_register_in_seconds" => 10 } } }

        it "is valid" do
          expect { config.validate_router_register_interval! }.to_not raise_error
        end
      end

      context "when the interval is invalid" do
        context "when the interval is zero" do
          let(:config_hash) { { "intervals" => { "router_register_in_seconds" => 0 } } }

          it "is valid" do
            expect { config.validate_router_register_interval! }.to raise_error
          end
        end

        context "when the interval is negative" do
          let(:config_hash) { { "intervals" => { "router_register_in_seconds" => -5 } } }

          it "is valid" do
            expect { config.validate_router_register_interval! }.to raise_error
          end
        end
      end

      context "when the interval not specified" do
        let (:config_hash) { { "intervals" => { } } }

        it "is sets it to the default value" do
          expect { config.validate_router_register_interval! }.to_not raise_error
          expect(config["intervals"]["router_register_in_seconds"]).to eq(20)
        end
      end
    end
  end
end
