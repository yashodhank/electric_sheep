require 'spec_helper'
require 'timecop'

describe ElectricSheep::Commands::Database::MongoDBDump do
  include Support::Command

  it{
    defines_options :user, :password
  }

  it 'has registered as "mongodb_dump"' do
    ElectricSheep::Agents::Register.command("mongodb_dump").must_equal subject
  end

  describe "executing the command" do

    before do
      @project, @logger, @shell, @host = ElectricSheep::Metadata::Project.new,
        mock, mock, mock
      @resource_path="\\$MyDatabase-20140605-040302"
      @shell.expects(:expand_path).with("$MyDatabase-20140605-040302").returns("/project/dir/#{@resource_path}")
      @shell.expects(:host).returns(@host)
      database = ElectricSheep::Resources::Database.new name: '$MyDatabase'
      @project.start_with! database

      @command = subject.new(@project, @logger, @shell, @metadata = mock)

      @seq = sequence('command')
      @logger.expects(:info).in_sequence(@seq).with "Creating a dump of the \"$MyDatabase\" MongoDB database"
    end

    def assert_product
      product = @project.last_product
      product.wont_be_nil
      product.path.must_equal "$MyDatabase-20140605-040302"
    end

    def assert_command
      @command.run!
      assert_product
    end

    it 'executes the backup command' do
      @metadata.stubs(:user).returns(nil)
      @metadata.stubs(:password).returns(nil)
      Timecop.travel Time.utc(2014, 6, 5, 4, 3, 2) do
        @shell.expects(:exec).in_sequence(@seq).
          with("mongodump -d \\$MyDatabase "+
            "-o /project/dir/#{@resource_path} &> /dev/null"
          )
        assert_command
      end
    end

    it 'appends credentials to the command' do
      @metadata.stubs(:user).returns('$operator')
      @metadata.stubs(:password).returns('$secret')
      Timecop.travel Time.utc(2014, 6, 5, 4, 3, 2) do
        @shell.expects(:exec).in_sequence(@seq).
          with("mongodump -d \\$MyDatabase "+
            "-o /project/dir/#{@resource_path} " +
            "-u \\$operator -p \\$secret " +
            "&> /dev/null"
          )
        assert_command
      end
    end

  end
end
