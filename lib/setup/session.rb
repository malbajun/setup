require 'setup'
require 'setup/core_ext'
require 'setup/constants'
require 'setup/project'
require 'setup/configuration'
require 'setup/compiler'
require 'setup/installer'
require 'setup/tester'
require 'setup/documentor'
require 'setup/uninstaller'
require 'setup/deps'

module Setup

  #
  class Session

    # Session options.
    attr :options

    # New Session
    def initialize(options={})
      @options = options
      self.io ||= StringIO.new  # log instead ?
    end

    # #  O P T I O N S  # #

    ## Reset configuration?
    #def reset?
    #  @options[:reset]
    #end

    #def reset=(value)
    #  @options[:reset] = value
    #end

    #
    def io
      @options[:io]
    end

    #
    def io=(anyio)
      @options[:io] = anyio
    end

    #
    def trace?; @options[:trace]; end

    #
    def trace=(val)
      @options[:trace] = val
    end

    #
    def trial?; @options[:trial]; end
    alias_method :dryrun?, :trial?

    #
    def trial=(val)
      @options[:trial] = val
    end
    alias_method :dryrun=, :trial=

    #
    def quiet?; @options[:quiet]; end

    #
    def quiet=(val)
      @options[:quiet] = val
    end

    #
    def force?; @options[:force]; end

    #
    def force=(val)
      @options[:force] = val
    end

    #
    def compilable?
      configuration.compilable? && project.compilable?
    end

    def apply task
      configuration.setup
      __send__(task)
    end

    # #  S E T U P  T A S K S  # #

    # Run all tasks in sequence.
    #
    # * config
    # * make
    # * test      (optional)
    # * install
    #
    def all
      config
      make

      if configuration.test?
        ok = test
        exit 1 unless ok
      end
      install
      #if configuration.ri?
      #  document
      #end
    end

    # Run all build tasks in sequence.
    #
    # * config
    # * make
    # * document
    #
    def build
      config
      make
      document
      predeps
    end

    #
    def config
      log_header('Preconfig')
      #if reset?
      #  @configuration = Configuration.new(:reset=>true)
      #end
      if configuration.save_config_with(project)
        io.print "#{CONFIG_FILE} was saved. " unless quiet?
      else
        io.print "#{CONFIG_FILE} is current. " unless quiet?
      end
      io.puts "Edit to customize configuration." unless quiet?
      puts configuration if trace? && !quiet?
    end

    # Make the project by running custom build task, and then compile binary if any.
    def make
      pre

      if compilable?
        log_header('Compile')
        compiler.configure
        #abort "must run 'setup config' first" unless configuration.exist?
        compiler.make
      end
    end

    # What #make used to be called.
    alias_method :setup, :make

    def pre
       if defined? Rake
          configuration.pre&.map do |task_name|
             project.stat_sources.each do |(source, status)|
                if status == :valid && source.respond_to?(:rakes) and !source.rakes.blank?
                   task =
                      source.rakes.reduce(nil) do |t, rake|
                         t || rake.tasks.select {|x|x.name == task_name}.first
                      end

                   begin
                      stdout = $stdout
                      $stdout = $stderr

                      FileUtils.chdir(source.root) { task.invoke }
                   rescue Exception => e
                   ensure
                      $stderr = $stdout
                      $stdout = stdout
                   end
                end
             end
          end
       end
    end

    #
    def install
      #abort "must run 'setup config' first" unless configuration.exist?
      log_header('Install')
      installer.install
    end

    #
    def test
      return true unless tester.testable?
      log_header('Test')
      tester.test
    end

    #
    def document
      return unless configuration.doc?
      log_header('Document')
      documentor.document
    end

    #
    def clean
      log_header('Clean')
      compiler.clean
      documentor.clean
    end

    #
    def distclean
      log_header('Distclean')
      compiler.distclean
      documentor.distclean
      installer.distclean
    end

    #
    def uninstall
      if !File.exist?(INSTALL_RECORD)
        io.puts "Nothing is installed."
        return
      end
      log_header('Uninstall')
      uninstaller.uninstall
      io.puts('Ok.')
    end

    #
    def show
      #configuration.show
      puts configuration
    end

    def provides
      io.puts("Provides:") unless quiet?

      provs = depper.provs.map do |target, provs|
         io.puts("<#{target}>:") unless quiet?

         provs.map { |_, prov_list| prov_list }
      end.flatten.reverse.uniq.reverse

      provs.each do |prov|
         io.puts(prov)
      end
    end

    def requires
      io.puts("Requires:") unless quiet?

      reqs = depper.reqs.map do |target, reqs|
         io.puts("<#{target}>:") unless quiet?

         reqs.map { |_, req_list| req_list }
      end.flatten.reverse.uniq.reverse

      reqs.each do |req|
         io.puts(req)
      end
    end

    def predeps
      io.puts("Generating predeps:") unless quiet?

      FileUtils.mkdir_p("/var/tmp/reqs")
      depper.target_req_list.each do |names, deps|
         names.map {|x| x.gsub('/', '') }.each do |name|
            File.open(File.join("/var/tmp/reqs", name), "w+") { |f| f.puts(deps) }
         end
      end

      FileUtils.mkdir_p("/var/tmp/provs")
      depper.target_prov_list.each do |names, deps|
         names.map {|x| x.gsub('/', '') }.each do |name|
            File.open(File.join("/var/tmp/provs", name), "w+") { |f| f.puts(deps) }
         end
      end
    end

    # #  C O N T R O L L E R S / M O D E L S  # #

    def default_project_options
      %w(dl ri inc ext lib app exe conf test man sup data docsrc log).map do |kind|
        name = "src#{kind}dirses"
        dirs = configuration.send(name)
        dirs && [ name.to_sym, dirs ]
      end.compact.to_h.merge(alias_names: configuration.aliases,
                             version_replaces: configuration.version_replaces,
                             gem_version_replace: (configuration.gem_version_replace || {}).merge(configuration.use_gem_dependencies || {}))
    end

    def project_options
      configuration.project && loaded_project_options_from(configuration.project) || default_project_options
    end

    def loaded_project_options_from value
      new_options = configuration.new_options.to_h

      new_options.merge(value.merge(value.dup.delete(:options)))
    end

    #
    def project
      @project ||= Project.new(configuration, project_options)
    end
    #
    def configuration
      @configuration ||= Configuration.new
    end
    #
    def compiler
      @compiler ||= Compiler.new(project, configuration, options)
    end
    #
    def installer
      @installer ||= Installer.new(project, configuration, options)
    end
    #
    def tester
      @tester ||= Tester.new(project, configuration, options)
    end
    #
    def documentor
      @documentor ||= Documentor.new(project, configuration, options)
    end
    #
    def uninstaller
      @uninstaller ||= Uninstaller.new(project, configuration, options)
    end
    #
    def depper
      @depper ||= Deps.new(project: project, options: options)
    end

    # #  S U P P O R T  # #
  
    #
    def log_header(phase)
      return if quiet?
      if trial?
        str = "#{phase.upcase} (trail run)"
      else
        str = "#{phase.upcase}"
      end
      line = "- " * 35
      line[0..str.size+3] = str
      io.puts("\n- - #{line}\n\n")
    end

    #   #center = "            "
    #   #c = (center.size - phase.size) / 2
    #   #center[c,phase.size] = phase.to_s.upcase
    #   line = '- ' * 4 + ' -' * 28
    #   #c = (line.size - phase.size) / 2
    #   line[5,phase.size] = " #{phase.to_s.upcase} "
    #   io.puts "\n" + line + "\n\n"
    #end

  end

end

