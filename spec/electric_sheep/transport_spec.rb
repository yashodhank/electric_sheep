require 'spec_helper'

describe ElectricSheep::Transport do
  let(:job) { ElectricSheep::Metadata::Job.new(id: 'some-job') }

  let(:hosts) { ElectricSheep::Metadata::Hosts.new }

  let(:transport) { subject.new(job, logger, hosts, resource, metadata) }

  [:local_interactor, :logger, :metadata].each do |m|
    let(m) { mock }
  end

  let(:seq) { sequence('run') }

  let(:resource) do
    mock.tap do |resource|
      resource.stubs(:name).returns('resource.name')
      resource.stubs(:type).returns(:file)
    end
  end

  let(:remote_host) do
    mock.tap do |resource|
      resource.stubs(:local?).returns(false)
    end
  end

  let(:localhost) { ElectricSheep::Metadata::Hosts.new.localhost }

  class InteractorKlazz
    def in_session(&_block)
      yield
    end
  end

  module RemoteInteractor
    def remote_interactor
      @remote_interactor ||= InteractorKlazz.new
    end
  end

  module RemoteResource
    def remote_resource
      @remote_resource ||= Object.new
    end
  end

  NoRemoteResourceTransportKlazz = Class.new do
    include ElectricSheep::Transport
    include RemoteInteractor
    def self.required_method
      'remote_resource'
    end
  end

  NoRemoteInteractorTransportKlazz = Class.new do
    include ElectricSheep::Transport
    include RemoteResource
    def self.required_method
      'remote_interactor'
    end
  end

  TransportKlazz = Class.new do
    include ElectricSheep::Transport
    include RemoteInteractor
    include RemoteResource

    attr_reader :done
  end

  describe TransportKlazz do
    describe 'trying to stat a resource' do
      let(:interactor) { mock }

      it 'stats the resource using the interactor' do
        interactor.expects(:stat).with(resource).returns(1024)
        resource.expects(:stat!).with(1024)
        transport.send(:stat!, resource, interactor)
      end
      it 'rescues interactor failure' do
        logger.expects(:warn)
          .with('Unable to stat resource of type file: Exception')
        interactor.expects(:stat).with(resource).raises('Exception')
        transport.send(:stat!, resource, interactor)
      end
    end
  end

  describe 'with a local interactor' do
    before do
      ElectricSheep::Interactors::ShellInteractor.expects(:new).with(
        hosts.localhost, job, logger
      ).returns(local_interactor)
      local_interactor.expects(:in_session).in_sequence(seq).yields
      hosts.stubs(:get).with('localhost').returns(localhost)
      metadata.stubs(:agent).returns('airplane')
    end

    [NoRemoteResourceTransportKlazz, NoRemoteInteractorTransportKlazz]
      .each do |klazz|
      describe klazz do
        it 'complains remote_interactor is not implemented' do
          metadata.stubs(:to).returns('some-host')
          metadata.stubs(:action).returns('copy')
          resource.stubs(:local?).returns(true)
          logger.stubs(:info)
          transport.stubs(:stat!)
          ex = -> { transport.run! }.must_raise RuntimeError
          ex.message.must_equal 'Not implemented, please define ' \
            "#{klazz}##{klazz.required_method}"
        end
      end
    end

    describe TransportKlazz do
      { move: 'Moving', copy: 'Copying' }.each do |action, msg|
        def expects_delete(interactor, action)
          return false if action == :copy
          interactor.expects(:delete!).in_sequence(seq)
            .with(resource)
          resource.expects(:transient!).in_sequence(seq)
        end

        def ensure_done(input, output, action)
          expected = (action == :copy ? input : output)
          transport.run!.must_equal output
          transport.output.must_equal output
          transport.product.must_equal expected
        end

        describe "#{msg.downcase} a resource" do
          before do
            transport.remote_interactor.expects(:in_session).in_sequence(seq)
              .yields
            metadata.stubs(:action).returns(action)
          end

          it 'transfers from local to remote' do
            metadata.stubs(:to).returns('some-host')
            resource.stubs(:local?).returns(true)
            transport.remote_resource.stubs(:local?).returns(false)
            logger.expects(:info).in_sequence(seq)
              .with("#{msg} resource.name to some-host using airplane")
            transport.expects(:stat!).in_sequence(seq)
              .with(resource, local_interactor)
            transport.remote_interactor.expects(:upload!).in_sequence(seq)
              .with(resource, transport.remote_resource, local_interactor)
            expects_delete(local_interactor, action)
            transport.expects(:stat!).in_sequence(seq)
              .with(transport.remote_resource, transport.remote_interactor)
            ensure_done(resource, transport.remote_resource, action)
          end

          it 'transfers from remote to local' do
            metadata.stubs(:to).returns('localhost')
            resource.stubs(:local?).returns(false)
            transport.expects(:file_resource).with(localhost)
              .returns(output = mock)
            output.stubs(:local?).returns(true)
            logger.expects(:info).in_sequence(seq)
              .with("#{msg} resource.name to localhost using airplane")
            transport.expects(:stat!).in_sequence(seq)
              .with(resource, transport.remote_interactor)
            transport.remote_interactor.expects(:download!).in_sequence(seq)
              .with(resource, output, local_interactor)
            expects_delete(transport.remote_interactor, action)
            transport.expects(:stat!).in_sequence(seq)
              .with(output, local_interactor)
            ensure_done(resource, output, action)
          end
        end
      end
    end
  end
end
