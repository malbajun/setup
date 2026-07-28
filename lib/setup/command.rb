require 'setup/session'
require 'optparse'

begin
require 'rake'
rescue Exception
end

module Setup

  # Command-line interface for Setup.rb.

  class Command

    # Initialize and run.

    def self.run(*argv)
      new.run(*argv)
    end

    # Hash of <tt>task => description</tt>.

    def self.tasks
      @tasks ||= {}
    end

    # Task names listed in order of information.

    def self.order
      @order ||= []
    end

    # Define a task.

    def self.task(name, description)
      tasks[name] = description
      order << name
    end

    task 'show'     , "show current configuration"
    task 'all'      , "config, compile and install"
    task 'build'    , "run make, and document consequently"
    task 'config'   , "save/customize configuration settings"
    task 'make'     , "run custom build task and then compile ruby extentions"
    task 'document' , "generate ri/rdoc documentation"
    task 'test'     , "run test suite"
    task 'install'  , "install project files"
    task 'clean'    , "does `make clean' for each extention"
    task 'distclean', "does `make distclean' for each extention"
    task 'uninstall', "uninstall previously installed files"
    task 'provides' , "show provides for all or specified sources"
    task 'requires' , "show requires for all or specffied sources"
    task 'predeps'  , "stores requires and provides for all sources"

    # Run command.

    def run(*argv)
      ARGV.replace(argv) unless argv.empty?

      #session = Session.new(:io=>$stdio)
      #config  = session.configuration

      tasks = ARGV.select{ |a| a !~ /^[-]/ }
      tasks = 'all' if tasks.empty?

      #task = 'doc' if task == 'document'

      if (task_names | tasks) != task_names
        $stderr.puts "Not a valid task -- #{task}"
        exit 1
      end

      parser  = OptionParser.new
      options = {}

      parser.banner = "Usage: #{File.basename($0)} [TASK] [OPTIONS]"

      optparse_header(parser, options)
      optparse_all(parser, options)
      optparse_common(parser, options)

      begin
        parser.parse!(ARGV)
      rescue OptionParser::InvalidOption
        $stderr.puts $!.to_s.capitalize
        exit 1
      end

      # This ensures we are in a project directory.
      # rootdir = session.project.rootdir

      print_header

      begin
        $stderr.puts "(#{RUBY_ENGINE} #{RUBY_VERSION} #{RUBY_PLATFORM})"
      rescue
        $stderr.puts "(#{RUBY_VERSION} #{RUBY_PLATFORM})"
      end

      tasks.each do |task|
         if configuration.compat
           Setup::Base.bash(configuration.compat, task, "--prefix=#{configuration.install_prefix}")
         end

         begin
           session.apply(task)
         rescue Error => err
           raise err if $DEBUG
           $stderr.puts $!.message
           $stderr.puts "Try 'setup.rb --help' for detailed usage."
           abort $!.message #exit 1
         end
      end

      puts unless session.quiet?
    end

    # Setup session.

    def session
      @session ||= Session.new(io: $stdout)
    end

    # Setup configuration. This comes from the +session+ object.

    def configuration
      @configuration ||= session.configuration
    end

    #
    def optparse_header(parser, options)
      parser.banner = "USAGE: #{File.basename($0)} [command] [options]"
      parser.separator ""
      parser.separator "Commands:"
      self.class.tasks.each do |name, desc|
        parser.separator "\t" + name + " " * (29 - name.size) + desc
      end
    end

    # Setup options for +show+ task.

    def optparse_show(parser, options)
      optparse_all(parser, options)
    end

    # Setup options for +all+ task.

    def optparse_all(parser, options)
      optparse_config(parser, options)
      optparse_document(parser, options)
      optparse_install(parser, options)
      optparse_test(parser, options)
    end

    # Setup options for +config+ task.

    def optparse_config(parser, options)
      parser.separator ""
      parser.separator "Configuration options:"
      #parser.on('--reset', 'reset configuration to default settings') do
      #  session.reset = true
      #end
      configuration.options.each do |args|
        args = args.dup
        desc = args.pop
        type = args.pop
        name, shortcut = *args
        #raise ArgumentError unless name, type, desc
        optname = name.to_s.gsub('_', '-')
        case type
        when :bool
          if optname.index('no-') == 0
            optname = "[no-]" + optname.sub(/^no-/, '')
            opts = shortcut ? ["-#{shortcut}", "--#{optname}", desc] : ["--#{optname}", desc]
            parser.on(*opts) do |val|
              configuration.__send__("#{name}=", !val)
            end
          else
            optname = "[no-]" + optname.sub(/^no-/, '')
            opts = shortcut ? ["-#{shortcut}", "--#{optname}", desc] : ["--#{optname}", desc]
            parser.on(*opts) do |val|
              configuration.__send__("#{name}=", val)
            end
          end
        else
          opts = shortcut ? ["-#{shortcut}", "--#{optname} #{type.to_s.upcase}", desc] :
                            ["--#{optname} #{type.to_s.upcase}", desc]
          parser.on(*opts) do |val|
            configuration.__send__("#{name}=", val)
          end
        end
      end
    end

    # Setup options for +install+ task.

    def optparse_install(parser, options)
      parser.separator ''
      parser.separator 'Install options:'
      parser.on('--chroot PATH', 'alternate chroot location') do |val|
        configuration.chroot = val
      end
      # install prefix overrides target prefix when installing
      parser.on('--prefix PATH', 'install to alternate root location') do |val|
        configuration.install_prefix = val
      end
      # type can override config
      parser.on('--type TYPE', "install location mode (auto,site,ruby,home,gem)") do |val|
        configuration.type = val
      end
      # test can be override config
      parser.on('-t', '--[no-]test', "run pre-installation tests") do |bool|
        configuration.test = bool
      end
      # file accounting mode
      parser.on('-m', '--mode MODE', "file accounting mode (flex,strict)") do |bool|
        configuration.mode = bool
      end
      # replace shebang line
      parser.on('-s', '--shebang SHEBANG', "replace a shebang line for a newly installed executables (<blank>,auto,env,ruby,<custom>)") do |shebang|
        configuration.shebang = shebang
      end
    end

    # Setup options for +document+ task.

    def optparse_document(parser, options)
      parser.separator ""
      parser.separator "Document options:"
      parser.on("--[no-]doc", "generate ri/yri documentation (default is --doc)") do |val|
        configuration.no_doc = val
      end
    end

    # Setup options for +test+ task.

    def optparse_test(parser, options)
      parser.separator ""
      parser.separator "Test options:"
      parser.on("-t", "--[no-]test", "run tests (default is --no-test)") do |val|
        configuration.no_test = val
      end
      #parser.on("--runner TYPE", "Test runner (auto|console|gtk|gtk2|tk)") do |val|
      #  ENV['RUBYSETUP_TESTRUNNER'] = val
      #end
    end

    # Setup options for +uninstall+ task.

    #def optparse_uninstall(parser, options)
    #  parser.separator ""
    #  parser.separator "Uninstall options:"
    #  parser.on("--prefix [PATH]", "Installation prefix") do |val|
    #    session.options[:install_prefix] = val
    #  end
    #end

    # Common options for every task.

    def optparse_common(parser, options)
      parser.separator ""
      parser.separator "General options:"

      parser.on("-q", "--quiet", "Suppress output") do
        session.quiet = true
        configuration.new_options.log_level = :none
      end

      parser.on("-f", "--force", "Force operation") do
        session.force = true
      end

      parser.on("--trace", "--verbose", "Watch execution") do |val|
        session.trace = true
      end

      parser.on("--trial", "--no-harm", "Do not write to disk") do |val|
        session.trial = true
      end

      parser.on("--debug", "Turn on debug mode") do |val|
        $DEBUG = true
      end

      parser.on('--install_prefix PATH', 'alternate install prefix location') do |val|
        configuration.install_prefix = val
      end

      # pre action
      parser.on('--pre LIST', 'Issue rake tasks from the comma-separated list before the action') do |val|
         configuration.pre = val.split(',').select {|x|x && x != ""}
      end

      # gem version replace
      parser.on('--gem-version-replace LIST', 'Make replacements in the found specs from the comma-separated list') do |val|
        configuration.gem_version_replace = val
      end

      # gem version replace
      parser.on('--version-replace VERSION', 'Replace version for the current source explicitly') do |val|
        configuration.version_replace = val
      end

      # ignore path token list
      parser.on('--ignore-path-tokens LIST', 'Ignore sources by a token contained in its path, which is specified in the comma-separated list') do |val|
        configuration.ignore_path_tokens = val
      end

      # ignore name list
      parser.on('--ignore-names LIST', 'Ignore sources by a name specified in the comma-separated list') do |val|
        configuration.ignore_names = val
      end

      # regard path token list
      parser.on('--regard-path-tokens LIST', 'Regard sources by a token contained in its path, which is specified in the comma-separated list') do |val|
        configuration.regard_path_tokens = val
      end

      # regard name list
      parser.on('--regard-names LIST', 'Regard sources by a name specified in the comma-separated list') do |val|
        configuration.regard_names = val
      end

      # use source
      parser.on('--use SOURCE', 'Apply the following options to the source named by this one') do |val|
        configuration.current_source_name = val
      end

      # use source's set
      parser.on('--set SET', 'Apply the following options to the set named by this one') do |val|
        configuration.current_set = val
      end

      # infer source and its set from package name
      parser.on('--package PACKAGE', 'Apply the following options to the set named by this one') do |val|
        configuration.package = val
      end

      # use source's set
      parser.on('--alias ALIASES', 'Aliases thr current source with the new names') do |val|
        configuration.current_alias = val
      end

      # use source's set
      parser.on('--join JOINS', 'Join the following sets into a single one for the current source') do |val|
        configuration.join = val
      end

      # set custom root folder for current module
      parser.on('--root PATH', 'Set custom root folder for current module') do |val|
        configuration.root = val
      end

      # generate the configations but use compatible script instead to act
      parser.on('--compat SCRIPT', 'generate the configations but use compatible script instead to act') do |val|
        configuration.compat = val
      end

      # use source's set
      parser.on('--prefixes PREFIXES', 'Aliases thr current source with the new names') do |val|
        configuration.current_prefix = val
      end

      # use dependency source for the set
      parser.on('--dep-source DEP_SOURCES', 'redefine dependency source for the set, default: auto') do |val|
        configuration.current_dep_source = val
      end

      parser.on('--use-gem-dependencies DEPS', '') do |val|
        configuration.use_gem_dependencies = val
      end

      parser.on('--use-gem-version DEPS', '') do |gem_version|
         hash = gem_version.split(",").map do |gv|
            v = gv.split(":")
            !v.empty? && (v + ["0"])[0..1] || nil
         end.compact.to_h
         configuration.use_gem_version_list = configuration.use_gem_version_list.merge(hash)
      end

      parser.on("--debug-io=[FILE|NAME|BLANK|DASH]", String, "IO for debug level. Value is file name, or --/stderr for stderr, or -/stdout for stdout, or blank to disable") do |str|
         configuration.new_options.debug_io = str
      end

      parser.on("--info-io=[FILE|NAME|BLANK|DASH]", "IO for info level. Value is file name, or --/stderr for stderr, or -/stdout for stdout, or blank to disable") do |str|
         configuration.new_options.info_io = str
      end

      parser.on("-v", "--verbose=[LEVEL]", String, "Run verbosely with levels: none, error, warn, info, or debug") do |v|
         configuration.new_options.log_level = v
      end

      parser.separator ""
      parser.separator "Inform options:"

      # Tail options (eg. commands in option form)
      parser.on_tail("-h", "--help", "display this help information") do
        #puts help
        puts parser
        exit
      end

      parser.on_tail("--version", "-v", "Show version") do
        puts File.basename($0) + ' v' + Setup::VERSION #Version.join('.')
        exit
      end

      parser.on_tail("--copyright", "Show copyright") do
        puts Setup::COPYRIGHT #opyright
        exit
      end
    end

    # List of task names.
    #--
    # TODO: shouldn't this use +self.class.order+ ?
    #++

    def task_names
      #self.class.order
      self.class.tasks.keys
    end

    # Output Header.
    #
    # TODO: This is not yet used. It might be nice to have,
    # but not sure what it should contain or look like.

    def print_header
      #unless session.quiet?
      #  if session.project.name
      #    puts "= #{session.project.name} (#{rootdir})"
      #  else
      #    puts "= #{rootdir}"
      #  end
      #end
      #$stderr << "#{session.options.inspect}\n" if session.trace? or session.trial?
    end

  end

end

