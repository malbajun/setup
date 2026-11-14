require 'rbconfig'
require 'fileutils'
require 'erb'
require 'yaml'
require 'shellwords'
require 'setup'
require 'setup/core_ext'
require 'setup/constants'
require 'setup/source_parts'

module Setup

  # Stores platform information and general install settings.
  #
  class Configuration
    attr_reader :project

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
      options << [name.to_s.gsub('-', '_'), *args] #type, description]
      attr_accessor(name.to_s.gsub('-', '_'))
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
    option :logdir          , :path, 'directory for log files'
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

    option :no_test, :t     , :bool, 'run pre-installation tests'
    # TODO: remove no_ri option in future version
    #option :no_ri,   :d     , :bool, 'generate ri documentation (deprecated and ignored)'
    option :no_doc          , :bool, 'install doc/ directory'
    option :no_ext          , :bool, 'compile/install ruby extentions'

    #option :rdoc            , :pick, 'generate rdoc documentation'
    #option :rdoc_template   , :pick, 'rdoc document template to use'
    #option :testrunner      , :pick, 'Runner to use for testing (auto|console|tk|gtk|gtk2)'

    option :install_prefix  , :path, 'install to alternate root location'
    option :chroot          , :path, 'a chroot location, defaulting to <install_prefix>'

    option :installdirs     , :pick, 'install location mode (auto,site,std,home,gem)'
    option :type            , :pick, 'install location mode (auto,site,std,home,gem)'
    option :mode            , :pick, 'file accounting mode (flex,strict)'

    option :pre             , :pick, 'issue rake tasks from the comma-separated list before the action'

    option :'gem-version-replace' , :pick, 'make replacements in the found specs from the comma-separated list'

    option :'ignore-names'  , :pick, 'ignore sources with the specified comma-separated name list'

    option :'regard-names'  , :pick, 'regard sources with the specified comma-separated name list'

    option :'ignore-source-parts', :pick, 'omit SOURCE:lib+doc+exec+devel+app installation parts; * matches all sources'
    option :'regard-source-parts', :pick, 'retain selected source parts over ignore-source-parts'

    def ignore_source_parts=(value)
      @ignore_source_parts = Setup::SourceParts.normalize(value)
    end

    def regard_source_parts=(value)
      @regard_source_parts = Setup::SourceParts.normalize(value)
    end

    def ignore_source_parts
      @ignore_source_parts || {}
    end

    def regard_source_parts
      @regard_source_parts || {}
    end

    def source_part_enabled?(source, part)
      Setup::SourceParts.matches?(regard_source_parts, source.name, part) ||
        !Setup::SourceParts.matches?(ignore_source_parts, source.name, part)
    end

    def source_core_part(source)
      source.is_a?(Setup::Source::Gem) ? :lib : :app
    end

    # RPM build/install policy overrides an earlier saved SetupConfig. Explicit
    # caller values are applied afterwards, including empty selectors to clear it.
    def initialize_source_parts_environment
      %w[IGNORE REGARD].each do |kind|
        key = "RPM_RUBY_#{kind}_SOURCE_PART_LIST"
        __send__("#{kind.downcase}_source_parts=", ENV[key]) if ENV.key?(key)
      end
    end

    option :'ignore-path-tokens' , :pick, 'ignore sources with the specified comma-separated list of path tokens'

    option :'regard-path-tokens' , :pick, 'regard sources with the specified comma-separated list of path tokens'

    option :shebang         , :pick, 'replace a shebang line for a newly installed executables ("",auto,env,ruby,<custom>)'

    option :use             , :pick, 'apply the following to the module options'
    option :root            , :path, 'set custom root folder for current module'
    option :'version-replace' , :pick, 'replace version for the current source explicitly'
    option :compat          , :pick, 'generate the configations but use compatible script instead to act'
    option :aliases         , :pick, ''
    option :joins           , :pick, ''
    option :prefixes        , :pick, ''
    option :dep_sources     , :pick, ''

    %w(dl ri inc ext lib app exe conf test man sup data docsrc log).map do |kind|
      funcs = <<-DEF
        option "src#{kind}dirs", :path, "Redefined directories for #{kind} space for the current source or at whole"

        def src#{kind}dirses= value
          @src#{kind}dirses = value || {}
        end

        def src#{kind}dirses
          @src#{kind}dirses ||= {}
        end

        def src#{kind}dirs= value
          @src#{kind}dirses = src#{kind}dirses.merge(current_source_name =>
                                                    (value.is_a?(Array) &&
                                                     value ||
                                                     value.split(/[:;,]/)))
        end

        def src#{kind}dirs
          src#{kind}dirses[current_source_name] || src#{kind}dirses[nil] || []
        end
      DEF

      class_eval(funcs)
    end

    # custom property
    #
    def install_prefix
      @install_prefix ||= '/'
    end

    # custom property
    #
    def gem_version_replace= value
      @gem_version_replace =
      if value.is_a?(String)
        tokens = (value || ENV['RUBY_GEMVERSION_REPLACE_LIST'] || '').split(/[,;:]/)
        tokens.map(&:strip).select {|x| x.size > 0 }.map do |x|
           match = x.match(/^([^\s]+)\s+(.*)/)

           [ match[1], match[2] ]
        end.to_h
      else
        value
      end
    end

    def use_gem_version_list= value
       @gem_version_replace = gem_version_replace.merge(value)
    end

    def use_gem_version_list
       @gem_version_replace
    end

    def ignore_path_tokens= value
      @ignore_path_tokens =
      if value.is_a?(String)
        tokens = (value || '').split(/[,;:]/)
        tokens.map(&:strip).select {|x| x.size > 0 }.map do |x|
           tokina = x.split("/")

           tokina.size > 1 ? %r{(?:^|/)#{tokina.join('[^\/]*')}(?:$|/)} : x
        end
      else
        value
      end
    end

    def ignore_path_tokens
       @ignore_path_tokens || []
    end

    def regard_path_tokens= value
      @regard_path_tokens =
      if value.is_a?(String)
        tokens = (value || '').split(/[,;:]/)
        tokens.map(&:strip).select {|x| x.size > 0 }.map do |x|
           tokina = x.split("/")

           tokina.size > 1 ? %r{(?:^|/)#{tokina.join('[^\/]*')}(?:$|/)} : x
        end
      else
        value
      end
    end

    def regard_path_tokens
       @regard_path_tokens || []
    end

    # Stores ignore filters from generated RPM macros or existing configuration.
    # @param value [String, Array<String, Regexp>, nil] source name filters
    # @return [Array<String, Regexp>, nil] decoded filters, or the unchanged non-string value
    # Strings preserve canonical regexp wrappers and legacy separator/slash forms.
    def ignore_names= value
      @ignore_names = decode_name_filters(value)
    end

    def ignore_names
       @ignore_names || []
    end

    # Stores regard filters from generated RPM macros or existing configuration.
    # @param value [String, Array<String, Regexp>, nil] source name filters
    # @return [Array<String, Regexp>, nil] decoded filters, or the unchanged non-string value
    # Strings preserve canonical regexp wrappers and legacy separator/slash forms.
    def regard_names= value
      @regard_names = decode_name_filters(value)
    end

    def regard_names
       @regard_names || []
    end

    # Decodes a source name list without evaluating Ruby expressions.
    # @param value [String, Array<String, Regexp>, nil] configured source filters
    # @return [Array<String, Regexp>, nil] decoded strings/patterns or unchanged input
    # Non-string values pass through. Canonical Regexp#to_s entries are compiled;
    # other entries retain the legacy slash-pattern conversion or remain literal.
    def decode_name_filters value
      return value unless value.is_a?(String)

      split_name_filters(value).map do |entry|
        if entry.match?(/\A\(\?[mix-]*:/)
          Regexp.new(entry)
        else
          tokens = entry.split('/')
          tokens.size > 1 ? %r{^#{tokens.join('[^\\/]*')}$} : entry
        end
      end
    end

    # Splits a filter list only outside regexp groups, classes and quantifiers.
    # @param value [String] comma-, semicolon- or colon-separated source filters
    # @return [Array<String>] nonempty entries with regexp syntax preserved
    # Escaped characters and separators inside balanced brackets stay in the
    # current entry. Inside a character class, only its closing bracket is structural.
    def split_name_filters value
      entries = ['']
      closing = []
      escaped = false
      brackets = { '(' => ')', '[' => ']', '{' => '}' }
      value.each_char do |character|
        entries.last << character
        if escaped
          escaped = false
        elsif character == '\\'
          escaped = true
        elsif closing.last == ']'
          closing.pop if character == ']'
        elsif brackets.key?(character)
          closing << brackets[character]
        elsif character == closing.last
          closing.pop
        elsif closing.empty? && ',;:'.include?(character)
          entries.last.chop!
          entries << ''
        end
      end
      entries.map(&:strip).reject(&:empty?)
    end
    private :decode_name_filters, :split_name_filters

    def shebang= value
       @shebang = !value.nil? && !value.empty? && value || nil
    end

    # custom property
    #
    def chroot
      @chroot ||= install_prefix || '/'
    end

    def current_alias= value
       aliases[current_source_name] = current_alias | (value.is_a?(Array) && value || value.split(/[;:]/)).map {|sub| sub.split(/[,]/) }
    end

    def current_alias
       aliases[current_source_name] || [ current_source_name ].compact
    end

    def aliases
       @aliases ||= {}
    end

    def joins
       @joins ||= {}
    end

    def version_replaces
       @version_replaces ||= {}
    end

    def version_replace= value
       @version_replaces = version_replaces.merge(current_source_name => value.to_s.strip)
    end

    def version_replace
       version_replaces[current_source_name] || version_replaces[nil] || []
    end

    def join= value
       @joins = joins.merge(current_source_name => value.split(/[:;,]/))
    end

    def join
       joins[current_source_name] || joins[nil] || []
    end

    def prefixes
       @prefixes ||= default_prefixes
    end

    def current_prefix= value
       @prefixes = prefixes.merge(current_source_name => value.split(/[:;,]/))
    end

    def current_prefix
       prefixes[current_source_name] || prefixes[nil] || []
    end

    def dep_sources
       @dep_sources ||= default_dep_sources
    end

    def current_dep_source= value
       @dep_sources = dep_sources.merge(current_set => { current_source_name => value.split(/[:;,]/) })
    end

    def current_dep_source
       dep_sources[current_source_name] || dep_sources[nil] || []
    end

    def use_gem_dependencies= value
      @use_gem_dependencies =
      if value.is_a?(String)
        tokens = (value || ENV['RPM_RUBY_USE_GEM_DEPENDENCY_LIST'] || '').split(/[,;:]/)
        tokens.map(&:strip).select {|x| x.size > 0 }.map do |x|
           match = x.match(/^([^\s]+)\s+(.*)/)

           [ match[1], match[2] ]
        end.to_h
      else
        value
      end
    end

    def use_gem_dependencies
       @use_gem_dependencies ||= {}
    end

    def suffixes
       @suffixes ||= default_suffixes
    end

    def affixes
      pre = prefixes.to_a.map() {| (k, v) | [ k, { prefix: v }] }
      suf = suffixes.to_a.map() {| (k, v) | [ k, { suffix: v }] }
      [ pre, suf ].flatten(1).reduce({}) do | res, (k, v) |
         res[k] = (res[k] || {}).merge(v)
         res
      end
    end

    def package= value
       match = affixes.to_a.reverse.reduce(nil) do |res, (name, af)|
          prefix_re = af[:prefix] && af[:prefix].map {|p| "#{p}-" }.join("|") || /\x0/
          suffix_re = af[:suffix] && af[:suffix].map {|p| "-#{p}" }.join("|") || /\x0/
          name_re = name || '.*?'
       
          res || /^(?<prefix>#{prefix_re})?(?<name>#{name_re})(?<suffix>#{suffix_re})?$/.match(value)
       end

       if match
          self.current_source_name = match[:name]
          self.current_package_name = match[:name]
          self.current_set = match[:suffix] && match[:suffix].sub('-', '') || match[:prefix] && 'lib' || 'bin'
       else
          $stderr.puts "No package match found for '#{value}'"
       end
    end

    def current_set= value
       @current_set = !value.nil? && !value.empty? && value || nil
    end

    def current_set
       join.include?(@current_set) && join || @current_set
    end

    def current_source_name= value
       @current_source_name = !value.nil? && !value.empty? && (
          als = aliases.values.find { |a| a.include?(value) }
          aliases.rassoc(als)&.first || value) || nil
    end

    def current_source_name
       @current_source_name
    end

    def current_package_name= value
       @current_package_name = !value.nil? && !value.empty? && value || nil
    end

    def current_package_name
       @current_package_name
    end

    def root= value
       @root = (root || {}).merge(current_source_name => value)
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
    def new_options
       @new_options ||= {
      rootdir: Dir.pwd,
      spec_type: "rpm",
      ignore_names: [],
      regard_names: [],
      aliased_names: [],
      ignore_path_tokens: [],
      regard_path_tokens: [],
      spec_file: nil,
      maintainer_name: nil,
      maintainer_email: nil,
      available_gem_list: {},
      devel_dep_setup: :include,
      use_gem_version_list: {}.to_os,
      log_level: :info,
      warn_io: 'stderr',
      error_io: 'stderr',
      info_io: 'stderr',
      debug_io: 'stderr'
   }.to_os

    end

    def options
      #(class << self ; self ; end).options
      self.class.options
    end

    # #  I N I T I A L I Z E  # #

    # New ConfigTable
    def initialize(values={})
      setup
      initialize_metaconfig
      initialize_defaults
      initialize_environment
      initialize_configfile unless values[:reset]
      initialize_source_parts_environment
#      initialize_gemfile

      values.each{ |k,v| __send__("#{k}=", v) }
      yield(self) if block_given?
    end

    def setup
        io_names = Setup::Log::DEFAULT_IO_NAMES.merge(%i(error warn info debug).map {|k| [k, new_options["#{k}_io"]]}.to_h)
        Setup::Log.setup(new_options.log_level.to_sym, io_names)
    end
    #
    def initialize_metaconfig
      if File.exist?(META_CONFIG_FILE)
        script = File.read(META_CONFIG_FILE)
        (class << self; self; end).class_eval(script)
      end
    end

    # Checks installation filters with optional source-name context.
    # @param file [String] source file or absolute installed target path
    # @param source_name [String, nil] gem name when the file belongs to a selected source
    # @return [Boolean, nil] whether the name/path filters exclude the file
    # If a source name is supplied, name filters match it instead of the path.
    # When name filters make no decision, existing path-token filtering applies.
    def match_ignore? file, source_name: nil
       res = match_ignore_name?(source_name || file)

       res.nil? ? match_ignore_token?(file) : res
    end

    def match_ignore_name? file
       return false unless regard_names.empty? || !regard_names.any? do |t|
          re = t.is_a?(Regexp) && t || %r{^#{t}$}

          file =~ re
       end

       ignore_names.any? do |t|
          re = t.is_a?(Regexp) && t || %r{^#{t}$}

          file =~ re
       end || nil
    end

    def match_ignore_token? file
       return false unless regard_path_tokens.empty? || !regard_path_tokens.any? do |t|
          re = t.is_a?(Regexp) && t || %r{(?:^|/)#{t}(?:$|/)}

          file =~ re
       end

       ignore_path_tokens.any? do |t|
          re = t.is_a?(Regexp) && t || %r{(?:^|/)#{t}(?:$|/)}

          file =~ re
       end || nil
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

    def load
       erb = ERB.new(File.read(CONFIG_FILE))
       txt = erb.result(binding)
       if Gem::Version.new(Psych::VERSION) >= Gem::Version.new("4.0.0")
          YAML.load(txt, aliases: true, permitted_classes: [Gem::Specification, Symbol, Regexp, Pathname])
       else
          YAML.load(txt)
       end
    end

    # Load configuration.
    def initialize_configfile
      if exist?
        dat = load
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
        if dat['mode']
          self.project = dat['project']
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
      @base_libdir ||= subprefix('libexecdir')
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

    def project= value
      @project = value
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
      h['project'] = @project.to_h
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
    def save_config_with project
      @project = project.to_h
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

    def default_dep_sources
      { 
        'lib' => { nil => [ 'auto' ] },
        'bin' => { nil => [ 'auto' ] },
        'doc' => { nil => [ 'auto' ] },
        'devel' => { nil => [ 'auto' ] },
      }
    end

    def default_prefixes
      { nil => [ 'gem' ] }
    end

    def default_suffixes
      { nil => ['doc', 'devel'] }
    end

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

