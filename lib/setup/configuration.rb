require 'rbconfig'
require 'fileutils'
require 'erb'
require 'yaml'
require 'shellwords'
require 'setup'
require 'setup/core_ext'
require 'setup/constants'

module Setup

  # Stores platform information and general install settings.
  #
  class Configuration

    # Ruby System Configuration
    RBCONFIG  = ::RbConfig::CONFIG

    ## Confgiuration file
    #CONFIG_FILE = 'SetupConfig'  # '.cache/setup/config'

    # Custom configuration file.
    META_CONFIG_FILE = META_EXTENSION_DIR + '/metaconfig.rb'

    #
    def self.options
      @@options ||= []
    end

    #
    # TODO: better methods for path type
    #
    def self.option(name, *args) #type, description)
      options << [name.to_s, *args] #type, description]
      attr_accessor(name)
    end

    option :prefix          , :path, 'path prefix of target environment'
    option :bindir          , :path, 'directory for commands'
    option :libdir          , :path, 'directory for libraries'
    option :datadir         , :path, 'directory for shared data'
    option :mandir          , :path, 'directory for man pages'
    option :docdir          , :path, 'directory for documentation'
    option :rbdir           , :path, 'directory for ruby scripts'
    option :sodir           , :path, 'directory for ruby extentions'
    option :ridir           , :path, 'directory for ruby ri documents'
    option :sysconfdir      , :path, 'directory for system configuration files'
    option :localstatedir   , :path, 'directory for local state data'

    option :libruby         , :path, 'directory for ruby libraries'
    option :librubyver      , :path, 'directory for standard ruby libraries'
    option :librubyverarch  , :path, 'directory for standard ruby extensions'
    option :siteruby        , :path, 'directory for version-independent aux ruby libraries'
    option :siterubyver     , :path, 'directory for aux ruby libraries'
    option :siterubyverarch , :path, 'directory for aux ruby binaries'

    option :gemhome         , :path, 'home directory for ruby gem libraries'

    option :rubypath        , :prog, 'path to set to #! line'
    option :rubyprog        , :prog, 'ruby program used for installation'
    option :makeprog        , :prog, 'make program to compile ruby extentions'

    option :extconfopt      , :opts, 'options to pass-thru to extconf.rb'

    option :shebang         , :pick, 'shebang line (#!) editing mode (all,ruby,never)'

    option :no_test, :t     , :bool, 'run pre-installation tests'
    # TODO: remove no_ri option in future version
    #option :no_ri,   :d     , :bool, 'generate ri documentation (deprecated and ignored)'
    option :no_doc          , :bool, 'install doc/ directory'
    option :no_ext          , :bool, 'compile/install ruby extentions'

    #option :rdoc            , :pick, 'generate rdoc documentation'
    #option :rdoc_template   , :pick, 'rdoc document template to use'
    #option :testrunner      , :pick, 'Runner to use for testing (auto|console|tk|gtk|gtk2)'

    option :install_prefix  , :path, 'install to alternate root location'
    option :root            , :path, 'a chroot location, defaulting to <install_prefix>'

    option :installdirs     , :pick, 'install location mode (auto,site,std,home,gem)'
    option :type            , :pick, 'install location mode (auto,site,std,home,gem)'
    option :mode            , :pick, 'file accounting mode (usual,lust)'

    option :pre             , :pick, 'issue rake tasks from the comma-separated list before the action'

    # custom property
    #
    def install_prefix
      @install_prefix ||= '/'
    end

    # custom property
    #
    def root
      @root ||= install_prefix || '/'
    end

    # Turn all of CONFIG into methods.

    ::RbConfig::CONFIG.each do |key,val|
      next if key == "configure_args"
      name = key.to_s.downcase.to_sym
      #name = name.sub(/^--/,'')
      #name = name.gsub(/-/,'_')
      define_method(name){ val } if !self.instance_methods.include?(name)
    end

    # Turn all of CONFIG["configure_args"] into methods.
    config_args = Shellwords.shellwords(::RbConfig::CONFIG["configure_args"])
    config_args.each do |ent|
      if ent.index("=")
        key, val = *ent.split("=")
      else
        key, val = ent, true
      end
      name = key.downcase
      name = name.sub(/^--/,'')
      name = name.gsub(/-/,'_')
      define_method(name){ val }
    end

    #
    def options
      #(class << self ; self ; end).options
      self.class.options
    end

    # #  I N I T I A L I Z E  # #

    # New ConfigTable
    def initialize(values={})
      initialize_metaconfig
      initialize_defaults
      initialize_environment
      initialize_configfile unless values[:reset]
#      initialize_gemfile

      values.each{ |k,v| __send__("#{k}=", v) }
      yield(self) if block_given?
    end

    #
    def initialize_metaconfig
      if File.exist?(META_CONFIG_FILE)
        script = File.read(META_CONFIG_FILE)
        (class << self; self; end).class_eval(script)
      end
    end

    # By default installation is to site locations, tests will
    # not be run, ri documentation will not be generated, but
    # the +doc/+ directory will be installed.
    def initialize_defaults
      self.type    = 'auto'
      self.mode    = 'usual'
      self.no_ri   = true
      self.no_test = true
      self.no_doc  = false
      self.no_ext  = false
    end

    # Get configuration from environment.
    def initialize_environment
      options.each do |name, *args|
        if value = ENV["RUBYSETUP_#{name.to_s.upcase}"]
          __send__("#{name}=", value)
        end
      end
    end

    # Load configuration.
    def initialize_configfile
      if exist?
        erb = ERB.new(File.read(CONFIG_FILE))
        txt = erb.result(binding)
        dat = YAML.load(txt)
        dat.each do |k, v|
          next if 'type' == k
          next if 'mode' == k
          next if 'installdirs' == k
          k = k.gsub('-','_')
          __send__("#{k}=", v) if respond_to?("#{k}=")
        end
        # do these last
        if dat['mode']
          self.mode = dat['mode']
        end
        if dat['type']
          self.type = dat['type']
        end
        if dat['installdirs']
          self.installdirs = dat['installdirs']
        end
      #else
      #  raise Error, $!.message + "\n#{File.basename($0)} config first"
      end
    end

    # Load configuration.
    def initialize_gemfile
      gemfile = has_gemfile? && IO.read('Gemfile') || ""

      if has_gemspec? && gemfile !~ /gemspec/
        gemfile << "gemspec\n"
      end

      File.open('Gemfile', 'w') { |f| f.puts(gemfile) }
    end

    attr_accessor :reset

    # #  B A S E  D I R E C T O R I E S  # #

    #
    #def base_libruby
    #  "lib/ruby"
    #end

    # Base bin directory
    def base_bindir
      @base_bindir ||= subprefix('bindir')
    end

    # Base libdir
    def base_libdir
      @base_libdir ||= subprefix('libdir')
    end

    #
    def base_datadir
      @base_datadir ||= subprefix('datadir')
    end

    #
    def base_mandir
      @base_mandir ||= subprefix('mandir')
    end

    # NOTE: This removed the trailing <tt>$(PACKAGE)</tt>.
    def base_docdir
      @base_docdir || File.dirname(subprefix('docdir'))
    end

    #
    def base_rubylibdir
      @rubylibdir ||= subprefix('rubylibdir')
    end

    #
    def base_rubyarchdir
      @base_rubyarchdir ||= subprefix('archdir')
    end

    # Base directory for system configuration files
    def base_sysconfdir
      @base_sysconfdir ||= subprefix('sysconfdir')
    end

    # Base directory for local state data
    def base_localstatedir
      @base_localstatedir ||= subprefix('localstatedir')
    end

    # Returns pure bindir
    def _bindir
      @_bindir ||= RbConfig::CONFIG['bindir']
    end

    # Returns true when ruby bindir matches root bindir
    def prefix_changed?
      bindir != _bindir
    end


    # #  C O N F I G U R A T I O N  # #

    #
    def mode
      @mode ||= 'usual'
    end

    #
    def mode=(val)
      @mode = val
    end

    def type
      @type ||= 'auto'
    end

    #
    def type=(val)
      @type = val
      case val.to_s
      when 'auto'
      when 'std', 'ruby'
        @rbdir = librubyver       #'$librubyver'
        @sodir = librubyverarch   #'$librubyverarch'
        @ridir = librubyri        #'$librubyri'
      when 'site'
        @rbdir = siterubyver      #'$siterubyver'
        @sodir = siterubyverarch  #'$siterubyverarch'
        @ridir = siterubyri       #'$siterubyri'
      when 'gem'
        @rbdir = gemrubylib       #'$gemrubylib'
        @sodir = gemrubyextarch   #'$gemrubyextarch'
        @ridir = gemrubyri        #'$gemrubyri'
      when 'home'
        self.prefix = File.join(home, '.local')  # TODO: Use XDG
        @rbdir = nil #'$libdir/ruby'
        @sodir = nil #'$libdir/ruby'
      else
        raise Error, "bad config: use type=(auto|ruby|site|home|gem) [#{val}]"
      end
    end

    # Alias for `#type`.
    alias_method :installdirs, :type

    # Alias for `#type=`.
    alias_method :installdirs=, :type=

    # Path prefix of target environment
    def prefix
      @prefix ||= RBCONFIG['prefix']
    end

    # Set path prefix of target environment
    def prefix=(path)
      @prefix = pathname(path)
    end

    # Directory for ruby libraries
    def libruby
      @libruby ||= RBCONFIG['prefix'] + "/lib/ruby"
    end

    # Set directory for ruby libraries
    def libruby=(path)
      path = pathname(path)
      @librubyver = librubyver.sub(libruby, path)
      @librubyverarch = librubyverarch.sub(libruby, path)
      @libruby = path
    end

    # Directory for standard ruby libraries
    def librubyver
      @librubyver ||= RBCONFIG['rubylibdir']
    end

    # Set directory for standard ruby libraries
    def librubyver=(path)
      @librubyver = pathname(path)
    end

    # Directory for standard ruby extensions
    def librubyverarch
      @librubyverarch ||= RBCONFIG['archdir']
    end

    # Set directory for standard ruby extensions
    def librubyverarch=(path)
      @librubyverarch = pathname(path)
    end

    # Get default directory for RI documentation in a system for core modules
    def librubyri
      @librubyri ||= RBCONFIG['ridir']
    end

    # Directory for version-independent aux ruby libraries
    def siteruby
      @siteruby ||= RBCONFIG['sitedir']
    end

    # Set directory for version-independent aux ruby libraries
    def siteruby=(path)
      path = pathname(path)
      @siterubyver = siterubyver.sub(siteruby, path)
      @siterubyverarch = siterubyverarch.sub(siteruby, path)
      @siteruby = path
    end

    # Directory for aux ruby libraries
    def siterubyver
      @siterubyver ||= RBCONFIG['sitelibdir']
    end

    # Set directory for aux ruby libraries
    def siterubyver=(path)
      @siterubyver = pathname(path)
    end

    # Directory for aux ruby binary libraries
    def siterubyverarch
      @siterubyverarch ||= RBCONFIG['sitearchdir']
    end

    # Set directory for aux arch ruby binaries
    def siterubyverarch=(path)
      @siterubyverarch = pathname(path)
    end

    # Get default directory for RI documentation in a system for site modules
    def siterubyri
       @siterubyri ||= File.join(RBCONFIG['ridir'], 'site')
    end

    # Returns gem home folder, if not specified sets and returns the default one
    def gemhome
      @gemhome ||= ::Gem.paths.home
    end

    # Set gem home folder
    def gemhome=(path)
      @gemhome = pathname(path)
    end

    # Ruby gem libraries folder
    def gemrubylib
#      @gemrubylib ||= File.join(gemhome, 'gems', Setup::Gem.new.fullname, "lib")
    end

    # Ruby gem ri documentation folder
    def gemrubyri
#      @gemrubyri ||= File.join(gemhome, 'doc', Setup::Gem.new.fullname, "ri")
    end

    # Ruby gem extensions folder
    def gemrubyextarch
#      @gemrubyextarch ||= (
#        arch = [ ::Gem.platforms.last.cpu, ::Gem.platforms.last.os ].join('-')
#        File.join(gemhome, 'extensions', arch, ::Gem.extension_api_version, Setup::Gem.new.fullname))
    end

    # Ruby gem specifications folder
    def gemrubyspec
      @gemrubyspec ||= File.join(gemhome, 'specifications')
    end

    # Directory for commands
    def bindir
      @bindir || File.join(prefix, base_bindir)
    end

    # Set directory for commands
    def bindir=(path)
      @bindir = pathname(path)
    end

    # Directory for libraries
    def libdir
      @libdir || File.join(prefix, base_libdir)
    end

    # Set directory for libraries
    def libdir=(path)
      @libdir = pathname(path)
    end

    # Directory for shared data
    def datadir
      @datadir || File.join(prefix, base_datadir)
    end

    # Set directory for shared data
    def datadir=(path)
      @datadir = pathname(path)
    end

    # Directory for man pages
    def mandir
      @mandir || File.join(prefix,  base_mandir)
    end

    # Set directory for man pages
    def mandir=(path)
      @mandir = pathname(path)
    end

    # Directory for documentation
    def docdir
      @docdir || File.join(prefix, base_docdir)
    end

    # Set directory for documentation
    def docdir=(path)
      @docdir = pathname(path)
    end

    # Directory for ruby scripts
    def rbdir
      @rbdir || File.join(prefix, base_rubylibdir)
    end

    # Directory for ruby extentions
    def sodir
      @sodir || File.join(prefix, base_rubyarchdir)
    end

    # Directory for system configuration files
    # TODO: Can this be prefixed?
    def sysconfdir
      @sysconfdir ||= base_sysconfdir
    end

    # Set directory for system configuration files
    def sysconfdir=(path)
      @sysconfdir = pathname(path)
    end

    # Directory for local state data
    # TODO: Can this be prefixed?
    def localstatedir
      @localstatedir ||= base_localstatedir
    end

    # Set directory for local state data
    def localstatedir=(path)
      @localstatedir = pathname(path)
    end

    #
    def rubypath
      #@rubypath ||= RBCONFIG['libexecdir']
      @rubypath ||= File.join(RBCONFIG['bindir'], RBCONFIG['ruby_install_name'] + RBCONFIG['EXEEXT'])
    end

    #
    def rubypath=(path)
      @rubypath = pathname(path)
    end

    #
    def rubyprog
      @rubyprog || rubypath
    end

    #
    def rubyprog=(command)
      @rubyprog = command
    end

    # TODO: Does this handle 'nmake' on windows?
    def makeprog
      @makeprog ||= (
        if arg = RBCONFIG['configure_args'].split.detect {|arg| /--with-make-prog=/ =~ arg }
          arg.sub(/'/, '').split(/=/, 2)[1]
        else
          'make'
        end
      )
    end

    #
    def makeprog=(command)
      @makeprog = command
    end

    #
    def extconfopt
      @extconfopt ||= ''
    end

    #
    def extconfopt=(string)
      @extconfopt = string
    end

    # Default is +ruby+.
    def shebang
      @shebang ||= 'ruby'
    end

    # There are three options: +all+, +ruby+, +never+.
    def shebang=(val)
      if %w(all ruby never).include?(val)
        @shebang = val
      else
        raise Error, "bad config: use SHEBANG=(all|ruby|never) [#{val}]"
      end
    end

    # 
    def no_ext
      @no_ext
    end

    #
    def no_ext=(val)
      @no_ext = boolean(val)
    end

    #
    def no_test
      @no_test
    end

    #
    def no_test=(val)
      @no_test = boolean(val)
    end

    #
    def no_doc
      @no_doc
    end

    #
    def no_doc=(val)
      @no_doc = boolean(val)
    end


    # @deprecated Will be remove in future version. Currently ignored.
    def no_ri
      @no_ri
    end

    # @deprecated Will be remove in future version. Currently ignored.
    def no_ri=(val)
      @no_ri = boolean(val)
    end


    #def rdoc            = 'no'
    #def rdoctemplate    = nil
    #def testrunner      = 'auto' # needed?

    # Compile native extensions?
    def compilable?
      !no_ext
    end

    # Run unit tests?
    def test?
      !no_test
    end

    # Generate ri documentation?
    #def ri?
    #  !no_ri
    #end

    # Install doc directory?
    def doc?
      !no_doc
    end


    # #  C O N V E R S I O N  # #

    #
    def to_h
      h = {}
      options.each do |name, *args|
        h[name.to_s] = __send__(name)
      end
      h
    end

    #
    def to_s
      to_yaml.sub(/\A---\s*\n/,'')
    end

    #
    def to_yaml(*args)
      to_h.to_yaml(*args)
    end

    # Save configuration.
    def save_config
      out = to_yaml
      dir = File.dirname(CONFIG_FILE)
      unless File.exist?(dir)
        FileUtils.mkdir_p(dir)
      end
      if File.exist?(CONFIG_FILE)
        txt = File.read(CONFIG_FILE)
        return nil if txt == out
      end          
      File.open(CONFIG_FILE, 'w'){ |f| f << out }
      true
    end

    # Does the configuration file exist?
    def exist?
      File.exist?(CONFIG_FILE)
    end

    # Does the gemfile file exist?
    def has_gemfile?
      File.exist?('Gemfile')
    end

    # Does the gemfile file exist?
    def has_gemspec?
      Dir.foreach('.').select { |f| f =~ /.gemspec$/ }.any?
    end
    #
    #def show
    #  fmt = "%-20s %s\n"
    #  OPTIONS.each do |name|
    #    value = self[name]
    #    reslv = __send__(name)
    #    case reslv
    #    when String
    #      reslv = "(none)" if reslv.empty?
    #    when false, nil
    #      reslv = "no"
    #    when true
    #      reslv = "yes"
    #    end
    #    printf fmt, name, reslv
    #  end
    #end

  private

    def pathname(path)
      path.gsub(%r<\\$([^/]+)>){ self[$1] }
    end

    #def absolute_pathname(path)
    #  File.expand_path(path).gsub(%r<\\$([^/]+)>){ self[$1] }
    #end

    # Boolean attribute. Can be assigned true, false, nil, or
    # a string matching yes|true|y|t or no|false|n|f.
    def boolean(val, name=nil)
      case val
      when true, false, nil
        val
      else
        case val.to_s.downcase
        when 'y', 'yes', 't', 'true'
           true
        when 'n', 'no', 'f', 'false'
           false
        else
          raise Error, "bad config: use --#{name}=(yes|no) [\#{val}]"
        end
      end
    end

    #
    def subprefix(path, with='')
      val = RBCONFIG[path]
      raise "Unknown path -- #{path}" if val.nil?
      prefix = Regexp.quote(RBCONFIG['prefix'])
      val.sub(/\A#{prefix}/, with)
    end

    #
    def home
      ENV['HOME'] || raise(Error, 'HOME is not set.')
    end

    # Get unresloved attribute.
    #def [](name)
    #  instance_variable_get("@#{name}")
    #end

    # Set attribute.
    #def []=(name, value)
    #  instance_variable_set("@#{name}", value)
    #end

    # Resolved attribute. (for paths)
    #def resolve(name)
    #  self[name].gsub(%r<\\$([^/]+)>){ self[$1] }
    #end

  end #class ConfigTable

end #module Setup








    # Pathname attribute. Pathnames are automatically expanded
    # unless they start with '$', a path variable.
    #def self.attr_pathname(name)
    #  class_eval %{
    #    def #{name}
    #      @#{name}.gsub(%r<\\$([^/]+)>){ self[$1] }
    #    end
    #    def #{name}=(path)
    #      raise Error, "bad config: #{name.to_s.upcase} requires argument" unless path
    #      @#{name} = (path[0,1] == '$' ? path : File.expand_path(path))
    #    end
    #  }
    #end

    # List of pathnames. These are not expanded though.
    #def self.attr_pathlist(name)
    #  class_eval %{
    #    def #{name}
    #      @#{name}
    #    end
    #    def #{name}=(pathlist)
    #      case pathlist
    #      when Array
    #        @#{name} = pathlist
    #      else
    #        @#{name} = pathlist.to_s.split(/[:;,]/)
    #      end
    #    end
    #  }
    #end

    # Adds boolean support.
    #def self.attr_accessor(*names)
    #  bools, attrs = names.partition{ |name| name.to_s =~ /\?$/ }
    #  attr_boolean *bools
    #  super *attrs
    #end


    # # provide verbosity (default is true)
    # attr_accessor :verbose?

    # # don't actually write files to system
    # attr_accessor :no_harm?

=begin
    # Metaconfig file is '.config/setup/metaconfig{,.rb}'.
    def inintialize_metaconfig
      path = Dir.glob(METACONFIG_FILE).first
      if path && File.file?(path)
        MetaConfigEnvironment.new(self).instance_eval(File.read(path), path)
      end
    end

    #= Meta Configuration
    # This works a bit differently from 3.4.1.
    # Defaults are currently not supported but remain in the method interfaces.
    class MetaConfigEnvironment
      def initialize(config) #, installer)
        @config    = config
        #@installer = installer
      end

      #
      def config_names
        @config.descriptions.collect{ |n, t, d| n.to_s }
      end

      #
      def config?(name)
        @config.descriptions.find do |sym, type, desc|
          sym.to_s == name.to_s
        end
      end

      #
      def bool_config?(name)
        @config.descriptions.find do |sym, type, desc|
          sym.to_s == name.to_s && type == :bool
        end
        #@config.lookup(name).config_type == 'bool'
      end

      #
      def path_config?(name)
        @config.descriptions.find do |sym, type, desc|
          sym.to_s == name.to_s && type == :path
        end
        #@config.lookup(name).config_type == 'path'
      end

      #
      def value_config?(name)
        @config.descriptions.find do |sym, type, desc|
          sym.to_s == name.to_s && type != :prog
        end
        #@config.lookup(name).config_type != 'exec'
      end

      #
      def add_config(name, default, desc)
        @config.descriptions << [name.to_sym, nil, desc]
        #@config.add item
      end

      #
      def add_bool_config(name, default, desc)
        @config.descriptions << [name.to_sym, :bool, desc]
        #@config.add BoolItem.new(name, 'yes/no', default ? 'yes' : 'no', desc)
      end

      #
      def add_path_config(name, default, desc)
        @config.descriptions << [name.to_sym, :path, desc]
        #@config.add PathItem.new(name, 'path', default, desc)
      end

      #
      def set_config_default(name, default)
        @config[name] = default
      end

      #
      def remove_config(name)
        item = @config.descriptions.find do |sym, type, desc|
          sym.to_s == name.to_s
        end
        index = @config.descriptions.index(item)
        @config.descriptions.delete(index)
        #@config.remove(name)
      end
    end
=end

# Designed to work with Ruby 1.6.3 or greater.

