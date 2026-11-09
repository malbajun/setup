# used in digest-crc gem as an extension compiler
#
require 'setup/loader'

class Setup::Rake
   extend ::Setup::Loader

   class InvalidRakefileError < StandardError; end

   TYPE = 'Rake::Application'
   PRELOAD_MATCHER = { /\/rakefile(.rb)?$/i => :preload }

   attr_reader :app, :rakefile, :options

   def blank?
      !@app
   end

   def present?
      !!@app
   end

   def tasks
      @tasks ||= @app&.tasks || []
   end

   # Executes one task with real build libraries inside the current Ruby process.
   # @param task_name [String] task name, optionally prefixed by the legacy @ marker
   # @return [Array<String>] executed task names without legacy markers
   def run_task task_name
      run_tasks([task_name])
   end

   # Loads the complete Rakefile and invokes the requested tasks in order.
   # @param task_names [Array<String>] task names with optional legacy @ markers
   # @param mode [Symbol, nil] :if_defined skips tasks absent from this Rakefile
   # @return [Array<String>] unique executed names in their requested order
   # Real libraries provide plugin tasks. Legacy markers are accepted without
   # spawning Ruby. Task failures propagate; the caller's directory, Rake
   # application and metadata adapters are restored after parallel workers finish,
   # including when one of the tasks fails.
   # Rake cleaning tasks are reloaded when cached, or required normally otherwise; the
   # caller's CLEAN/CLOBBER lists and cleaning-library require state are restored.
   def run_tasks task_names, mode = nil
      previous_application = ::Rake.application
      previous_directory = Dir.pwd
      clean_constants = %i(CLEAN CLOBBER)
      previous_clean = {}
      clean_constants.each {|name| previous_clean[name] = Object.const_get(name, false) if Object.const_defined?(name, false) }
      clean_library = $LOADED_FEATURES.find {|file| file.end_with?('/rake/clean.rb') }
      names = task_names.map {|name| name.to_s.delete_prefix('@') }.reject(&:empty?).uniq

      self.class.with_task_libraries do
         Dir.chdir(File.dirname(rakefile))
         @app = ::Rake::Application.new
         @tasks = nil
         ::Rake.application = @app
         @app.init('rake', ['--rakefile', rakefile])
         clean_constants.each {|name| Object.send(:remove_const, name) if Object.const_defined?(name, false) }
         clean_library ? Kernel.load(clean_library) : require('rake/clean')
         @app.load_rakefile
         names = names.select {|name| @app.lookup(name) } if mode == :if_defined
         begin
            names.each {|name| @app.invoke_task(name) }
         ensure
            @app.thread_pool.join
         end
      end

      names
   ensure
      ::Rake.application = previous_application
      Dir.chdir(previous_directory)
      clean_constants.each do |name|
         Object.send(:remove_const, name) if Object.const_defined?(name, false)
         Object.const_set(name, previous_clean[name]) if previous_clean.key?(name)
      end
      $LOADED_FEATURES.delete_if {|file| file.end_with?('/rake/clean.rb') } unless clean_library
      root = File.dirname(rakefile) + '/'
      self.class.mods.delete_if {|file, _| File.expand_path(file).start_with?(root) }
   end

   # Creates a metadata reader or a deferred runtime task runner.
   # @param rakefile [String] path to an existing Rakefile
   # @param options [Hash] :runtime skips the metadata import before execution
   # @return [Setup::Rake] the initialized reader or runner
   # Missing files raise InvalidRakefileError. Runtime mode loads real libraries
   # when tasks run; metadata mode retains its lightweight source import.
   def initialize rakefile, options = {}
      raise InvalidRakefileError unless File.file?(rakefile)

      @rakefile = File.expand_path(rakefile)
      @options = options
      @app = self.class.load(@rakefile).objects.first unless options[:runtime]
      @app&.load_imports
   end

   class << self
      # Reports whether complete Rake tasks currently own the library context.
      # Takes no parameters.
      # @return [Boolean] true inside runtime execution, including its worker threads
      def running_tasks?
         @running_tasks || false
      end

      # Exposes real build libraries while preserving metadata adapter constants.
      # @yield loads and invokes Rake tasks with ordinary library requirements
      # @return [Object] the block's return value
      # Takes no parameters. Mapped metadata adapters and autoloads are restored
      # even on failure. Previously required real libraries are cached and reused;
      # the Kernel require mapping is bypassed only inside the runtime scope.
      def with_task_libraries
         previous = {}
         previous_runtime = running_tasks?
         libraries = @task_libraries ||= {}
         adapters = @metadata_libraries ||= {}
         adapter_root = File.join(__dir__, 'extcore') + '/'

         Kernel::MODULES.each do |library, replacement|
            next if replacement.is_a?(Proc)

            name = library.capitalize.to_sym
            autoload = Object.autoload?(name)
            previous[name] = if autoload
               [:autoload, autoload]
            elsif Object.const_defined?(name, false)
               [:constant, Object.const_get(name, false)]
            else
               [:absent, nil]
            end

            location = Object.const_source_location(name)&.first
            if previous[name].first == :constant
               adapter = adapters[name].equal?(previous[name].last) || location&.start_with?(adapter_root)
               next unless adapter

               adapters[name] = previous[name].last
            end

            Object.send(:remove_const, name) if Object.const_defined?(name, false)
            Object.const_set(name, libraries[name]) if libraries.key?(name)
         end

         @running_tasks = true
         yield
      ensure
         @running_tasks = previous_runtime
         previous.each do |name, (kind, value)|
            if Object.const_defined?(name, false) && !Object.autoload?(name)
               location = Object.const_source_location(name)&.first
               libraries[name] = Object.const_get(name, false) unless location&.start_with?(adapter_root)
            end
            Object.send(:remove_const, name) if Object.const_defined?(name, false)
            Object.const_set(name, value) if kind == :constant
            Object.autoload(name, value) if kind == :autoload
         end
      end

      # preload callback
      def preload
         Rake.instance_variable_set(:@application, nil)
      end

      def load rakefile
         app_file(rakefile)
      end
   end
end
