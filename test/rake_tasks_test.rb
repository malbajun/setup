require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'setup'
require 'setup/rake_app'

class RakeTasksTest < Minitest::Test
   def setup
      @directory = Dir.mktmpdir('setup-rake-')
      @application = Rake.application
      @working_directory = Dir.pwd
   end

   def teardown
      $LOAD_PATH.delete(@directory)
      $LOADED_FEATURES.delete_if {|file| file.start_with?(@directory + '/') }
      Setup::Rake.instance_variable_get(:@task_libraries)&.delete(:Hoe)
      FileUtils.remove_entry(@directory)
      assert_same @application, Rake.application
      assert_equal @working_directory, Dir.pwd
      refute Setup::Rake.running_tasks?
   end

   def write file, contents
      path = File.join(@directory, file)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, contents + "\n")
      path
   end

   def runner
      Setup::Rake.new(File.join(@directory, 'Rakefile'), runtime: true)
   end

   def session tasks, rakes = [runner]
      source = Struct.new(:rakes).new(rakes)
      object = Setup::Session.new
      object.instance_variable_set(:@configuration, Struct.new(:pre).new(tasks))
      object.instance_variable_set(:@project, Struct.new(:stat_sources).new([[source, :valid]]))
      object
   end

   def test_imported_prerequisites_run_in_the_current_ruby
      write 'Rakefile', "import 'tasks.rake'\ntask(:prepare) { File.write('result', Process.pid.to_s) }"
      write 'tasks.rake', "task(:generate => :prepare) { File.open('result', 'a') { |file| file.puts ':generated' } }"
      assert_equal ['generate'], runner.run_task('generate')
      assert_equal "#{Process.pid}:generated\n", File.read(File.join(@directory, 'result'))
   end

   def test_legacy_marker_does_not_spawn_ruby
      write 'Rakefile', "task(:generate) { File.write('result', Process.pid.to_s) }"
      assert_equal ['generate'], session(['@generate']).pre
      assert_equal Process.pid.to_s, File.read(File.join(@directory, 'result'))
   end

   def test_real_plugin_tasks_are_loaded_and_metadata_adapter_is_restored
      require 'setup/extcore/hoe'
      adapter = Hoe
      write 'hoe.rb', <<~RUBY
         require 'rake/clean'
         class Hoe
            def self.spec(name)
               CLEAN.include 'obsolete'
               Rake::Task.define_task(:lexer) { File.open('result', 'a') { |file| file.puts Process.pid } }
            end
         end
      RUBY
      $LOAD_PATH.unshift(@directory)
      write 'Rakefile', "require 'hoe'\nHoe.spec 'example'\ntask :generate => :lexer"
      object = session(['generate'])
      2.times do
         assert_equal ['generate'], object.pre
         assert_same adapter, Hoe
      end
      assert_equal [Process.pid.to_s, Process.pid.to_s], File.readlines(File.join(@directory, 'result')).map(&:strip)
   end

   def test_task_failure_propagates
      write 'Rakefile', "task(:generate) { raise 'generation failed' }"
      error = assert_raises(RuntimeError) { session(['generate']).pre }
      assert_equal 'generation failed', error.message
   end

   def test_cached_cleaning_tasks_are_recreated_for_the_new_application
      require 'rake/clean'
      previous_clean = CLEAN
      write 'obsolete', 'remove this file'
      write 'Rakefile', "require 'rake/clean'\nCLEAN.include 'obsolete'\ntask :generate => :clean"
      assert_equal ['generate'], session(['generate']).pre
      refute File.exist?(File.join(@directory, 'obsolete'))
      assert_same previous_clean, CLEAN
      refute_includes CLEAN.to_a, 'obsolete'
   end

   def test_worker_threads_use_real_task_libraries
      require 'setup/extcore/hoe'
      adapter = Hoe
      write 'hoe.rb', "class Hoe\n def self.generate; File.write('result', Process.pid.to_s); end\nend"
      $LOAD_PATH.unshift(@directory)
      write 'Rakefile', "task(:generate) { Thread.new { require 'hoe'; Hoe.generate }.value }"
      assert_equal ['generate'], session(['generate']).pre
      assert_equal Process.pid.to_s, File.read(File.join(@directory, 'result'))
      assert_same adapter, Hoe
   end

   def test_missing_task_is_reported
      write 'Rakefile', 'task :other'
      error = assert_raises(ArgumentError) { session(['absent']).pre }
      assert_match 'Rake tasks not found: absent', error.message
   end

   def test_parallel_workers_finish_inside_the_real_library_scope_after_failure
      result = File.join(@directory, 'worker-context')
      write 'Rakefile', <<~RUBY
         started = Queue.new
         Rake.application.options.thread_pool_size = 2
         task :worker do
            started << true
            sleep 0.05
            File.write(#{result.dump}, Setup::Rake.running_tasks?.to_s)
         end
         task(:fail) { started.pop; raise 'generation failed' }
         multitask :generate => [:worker, :fail]
      RUBY
      object = runner
      assert_raises(RuntimeError) { object.run_task('generate') }
      object.app.thread_pool.join
      assert_equal 'true', File.read(result)
   end

   def test_one_rakefile_is_not_run_twice_for_duplicate_sources
      write 'Rakefile', "task(:generate) { File.open('result', 'a') { |file| file.puts 'once' } }"
      assert_equal ['generate'], session(['generate', 'generate'], [runner, runner]).pre
      assert_equal "once\n", File.read(File.join(@directory, 'result'))
   end
end
