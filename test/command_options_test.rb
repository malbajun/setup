require 'minitest/autorun'
require 'stringio'
require 'setup/command'

class CommandOptionsTest < Minitest::Test
   class RecordingSession
      attr_reader :applied

      def initialize
         @applied = []
      end

      def apply(task)
         @applied << task
      end

      def quiet?
         true
      end
   end

   def with_command(arguments)
      previous = ARGV.dup
      ARGV.replace(arguments)
      command = Setup::Command.new
      config = Setup::Configuration.new(reset: true)
      session = RecordingSession.new
      command.instance_variable_set(:@configuration, config)
      command.instance_variable_set(:@session, session)
      yield command, config, session
   rescue SystemExit => error
      flunk "Unexpected CLI exit: #{error.status}"
   ensure
      ARGV.replace(previous)
   end

   def test_unknown_inline_options_preserve_tasks_and_known_values
      args = ['config', '--future-part=anything', '--with-parts=exec,check', 'install', '--new-switch']
      with_command(args) do |command, config, session|
         capture_io { command.run }
         assert_equal ['config', 'install'], session.applied
         assert_equal ['exec', 'check'], config.with_parts
      end
   end

   def test_unknown_separated_value_is_ignored_before_a_known_option
      with_command(['--future-setting', 'value', 'show', '--with-parts', 'doc']) do |command, config, session|
         capture_io { command.run }
         assert_equal ['show'], session.applied
         assert_equal ['doc'], config.with_parts
      end
   end

   def test_an_unknown_switch_does_not_consume_a_known_task
      with_command(['--future-switch', 'config', 'install']) do |command, _config, session|
         capture_io { command.run }
         assert_equal ['config', 'install'], session.applied
      end
   end

   def test_multiple_unknown_long_and_short_options_are_ignored
      with_command(['show', '-Z', '--another=value', '--last', 'value']) do |command, _config, session|
         capture_io { command.run }
         assert_equal ['show'], session.applied
      end
   end

   def test_only_new_options_preserve_the_default_task
      with_command(['--future=on']) do |command, _config, session|
         capture_io { command.run }
         assert_equal ['all'], session.applied
      end
   end

   def test_missing_values_for_known_options_still_fail
      with_command(['show', '--prefix']) do |command, _config, session|
         capture_io { assert_raises(OptionParser::MissingArgument) { command.run } }
         assert_empty session.applied
      end
   end

   def test_invalid_tasks_still_fail
      with_command(['unknown-task']) do |command, _config, session|
         capture_io do
            error = assert_raises(SystemExit) { command.run }
            assert_equal 1, error.status
         end
         assert_empty session.applied
      end
   end

   def test_help_works_without_an_explicit_task
      with_command(['--help']) do |command, _config, session|
         output, = capture_io do
            error = assert_raises(SystemExit) { command.run }
            assert_equal 0, error.status
         end
         assert_includes output, '--with-parts'
         assert_empty session.applied
      end
   end
end
