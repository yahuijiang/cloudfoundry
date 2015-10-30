# coding: UTF-8

require "spec_helper"
require "digest/sha1"
require "dea/droplet"

describe Dea::Droplet do
  include_context "tmpdir"

  let(:payload) do
    "droplet"
  end

  let(:sha1) do
    Digest::SHA1.hexdigest(payload)
  end

  subject(:droplet) do
    Dea::Droplet.new(tmpdir, sha1)
  end

  it "should export its sha1" do
    droplet.sha1.should == sha1
  end

  it { should_not exist }

  it "should make sure its directory exists" do
    File.directory?(droplet.droplet_dirname).should be_true
  end

  describe "destroy" do
    it "should remove the associated directory" do
      File.exist?(droplet.droplet_dirname).should be_true

      with_event_machine do
        droplet.destroy { EM.stop }
        done
      end

      File.exist?(droplet.droplet_dirname).should be_false
    end
  end

  describe "download" do
    context "when unsucessful" do
      it "should fail when server is unreachable" do
        error = nil

        with_event_machine do
          droplet.download("http://127.0.0.1:12346/droplet") do |err|
            error = err
            done
          end
        end

        error.message.should match(/status: unknown/)
      end

      context "when response has status other than 200" do
        before do
          stub_request(:get, "http://127.0.0.1:12345/droplet").to_return(status: 404)
        end

        it "should fail" do
          error = nil

          with_event_machine do
            droplet.download("http://127.0.0.1:12345/droplet") do |err|
              error = err
              done
            end
          end

          error.message.should match(/status: 404/)
        end

        it "should not create droplet file" do
          with_event_machine do
            droplet.download("http://127.0.0.1:12345/droplet") do |err|
              done
            end
          end

          expect(File.exist?(droplet.droplet_path)).to be_false
        end
      end

      it "should fail when response payload has invalid SHA1" do
        stub_request(:get, "http://127.0.0.1:12345/droplet").to_return(body: "fooz")

        error = nil

        with_event_machine do
          droplet.download("http://127.0.0.1:12345/droplet") do |err|
            error = err
            done
          end
        end

        error.message.should match(/SHA1 mismatch/)
      end
    end

    context "when successful" do
      before do
        stub_request(:get, "http://127.0.0.1:12345/droplet").to_return(body: payload)
      end

      after do
        FileUtils.rm_f droplet.droplet_path
      end

      it "should call callback without error" do
        error = nil

        with_event_machine do
          droplet.download("http://127.0.0.1:12345/droplet") do |err|
            error = err
            done
          end
        end

        error.should be_nil
        droplet.should exist
      end
    end

    context "when the same dea is running multiple instances of the app" do
      before do
        @request = stub_request(:get, "http://127.0.0.1:12345/droplet").to_return(body: payload)
      end

      it "only downloads the droplet once" do
        called = 0
        with_event_machine do
          3.times do
            droplet.download("http://127.0.0.1:12345/droplet") do
              called += 1
            end
          end

          done
        end

        expect(@request).to have_been_made.times(1)
        expect(called).to eq(3)
      end
    end

    context "when the droplet is already downloaded" do
      before do
        FileUtils.mkdir_p(droplet.droplet_dirname)
        @request = stub_request(:get, "http://127.0.0.1:12345/droplet").to_return(body: payload)
      end

      context "and the sha matches" do
        before do
          File.open(droplet.droplet_path, "w") do |io|
            io.write payload
          end
        end

        it "does not download the file" do
          with_event_machine do
            droplet.download("http://127.0.0.1:12345/droplet") do
              done
            end
          end

          expect(@request).to_not have_been_made
        end
      end

      context "and the sha doesn't match" do
        before do
          File.open(droplet.droplet_path, "w") do |io|
            io.write "bogus-droplet"
          end
        end

        it "downloads the file" do
          with_event_machine do
            droplet.download("http://127.0.0.1:12345/droplet") do
              done
            end
          end

          expect(@request).to have_been_made
        end
      end
    end
  end

  describe "local_copy" do
    let(:source_file) { source_file = File.join(tmpdir, "source_file") }

    context "when copy was successful" do
      before { File.open(source_file, "w+") { |f| f.write("some data") } }
      after { FileUtils.rm_f(source_file) }

      it "saves file in droplet path" do
        droplet.local_copy(source_file) {}
        expect {
          File.exists?(droplet.droplet_path)
        }.to be_true

        File.read(source_file).should eq("some data")
      end

      it "calls the callback without error" do
        called = false
        droplet.local_copy(source_file) do |err|
          called = true
          err.should be_nil
        end
        called.should be_true
      end
    end

    context "when copy failed" do
      let(:wrong_source_file) { source_file = File.join(tmpdir, "wrong_source_file") }
      before { FileUtils.rm_f(wrong_source_file) }

      it "calls callback with error" do
        called = false
        droplet.local_copy(source_file) do |err|
          called = true
          err.should_not be_nil
        end
        called.should be_true
      end
    end
  end
end
