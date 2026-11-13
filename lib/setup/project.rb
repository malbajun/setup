require 'bundler/shared_helpers'
require 'bundler/runtime'

require 'setup'
require 'setup/log'

module Setup

  # The Project class encapsulates information about the project/package
  # setup is handling.
  #
  # Setup.rb can use information about your project to provide additional
  # features.
  #
  # To inform Setup.rb of the project's name, version and load path
  # you can create a file in you project's root directory called `.index`.
  # This is a YAML file with minimum entries of:
  #
  #     ---
  #     name: foo
  #     version: 1.0.0
  #     paths:
  #       load: [lib]
  #
  # See [Indexer](http://github.com/rubyworks/indexer) for more information about
  # this file and how to easily maintain it.
  #
  # If a `.index` file is not found Setup.rb will look for `.setup/name`,
  # `.setup/version` and `.setup/loadpath` files for this information.
  #
  # As of v5.1.0, Setup.rb no longer recognizes the VERSION file
  #
  class Project
    include Setup::Log

       STATES = {
          invalid: ->(_, source, _, _) { !source.valid? },
          disabled: ->(prj, source, _, _) { prj.is_disabled?(source) },
          obsoleted: ->(_, _, dup, obsoleted) { !dup && obsoleted },
          duplicated: ->(_, _, dup, _) { dup },
       }

       TYPE_CHARS = {
          fake: '·',
          gem: '*',
          gemfile: '&',
          rakefile: '^',
       }

       STATUS_CHARS = {
          invalid: 'X',
          disabled: '-',
          obsoleted: '\\',
          duplicated: '=',
          regarded: 'R',
          valid: 'V',
       }

       DEFAULT_IGNORE_PATH_TOKES =
         %w(templates example examples sample samples spec test features
            fixtures doc docs contrib demo acceptance conformance myapp website benchmarks benchmark
            gemfiles misc steep)

   PLATFORMS = {
      ruby: true,
      jruby: false,
      mingw: false,
   }
       VERSIONS = {
          /nonrelease/ => false 
       }


       attr_reader :config, :version_replaces

    #
    def initialize config, options = {}
      # pre-init require
      $:.unshift(Dir.pwd)

      self.stat_sources = options.delete(:sources_hash)
      @rootdir  = options.delete(:rootdir)
      @config   = config
      @options  = options

      @name     = root_source&.name
      @version  = root_source&.version
      @loadpath = ['lib']

        show_tree if Setup::Log.ios[:info]

        if file = find('.setup/name')
          @name = File.read(file).strip
        end
        if file = find('.setup/version')
          @version = File.read(file).strip
        end
        if file = find('.setup/loadpath')
          @loadpath = File.read(file).strip
        end

        # post create hook
        autoalias
        runtime
    end

    def show_tree
       info("Source list are the following:")
       stat_source_tree.each do |(path_in, stated_sources)|
          stated_sources.each do |(source, status)|
             path = File.join(source.root, File.basename(source.source_file)) if source.source_file
             stat = [STATUS_CHARS[status], TYPE_CHARS[source.type.to_sym]].join(" ")
             namever = [source.name, source.version, source.platform.to_s].compact.join(":")
             info_in = "#{stat}#{namever} [#{path}]"

             info(info_in)
          end
       end
    end

    # The name of the package, used to install docs in system doc/ruby-{name}/ location.
    attr :name

    # Current version number of project.
    attr :version

    #
    attr :loadpath

    alias load_path loadpath

    def runtime
       @runtime ||= root_source && Bundler.instance_variable_set(:@setup, Bundler::Runtime.new(rootdir, root_source.dsl.definition))
    end

    # Locate project root.
    def rootdir
      @rootdir ||= Dir.pwd
    end

    def to_h
       {
          sources_hash: stat_sources.map {|(x, y)| [x.to_h, y] },
          options: options,
          rootdir: rootdir
       }
    end

    def spec_version
       config.gem_version_replace.first.last
    end

   def pre_sources
      @pre_sources ||=
         Setup::Source.search(rootdir, options).group_by do |x|
            [x.name, x.version].compact.join(":")
         end
   end

   # returns all the sources with their statuses, and sorted by a its rootdir value
   #
   def stat_sources &block
      return @stat_sources if @stat_sources

      @stat_sources = proceed_sources(&block)

      show_tree

      @stat_sources
   end

   def proceed_sources &block
      pre = 
         pre_sources.reduce([[],[],[]]) do |(r, used_in, deps_in), (_full_name, v)|
            sorten =
               v.sort do |x,y|
                  c0 = ::Setup::Source.loaders.index(x.loader) <=> ::Setup::Source.loaders.index(y.loader)
                  c1 = c0 == 0 && x.name <=> y.name || c0
                  c2 = c1 == 0 && y.version <=> x.version || c1
                  c3 = c2 == 0 && y.platform.to_s <=> x.platform.to_s || c2
                  c4 = c3 == 0 && y.source_names.grep(/gemspec/).count <=> x.source_names.grep(/gemspec/).count

                  c2 == 0 && c3 == 0 && c4 == 0 && x.root.size <=> y.root.size || c4 != 0 && c4 || c3 != 0 && c3 || c2
               end.reduce([[], 0]) do |(res, index, base), source|
                  dup = used_in.include?(source.name) && base && base.platform.to_s == source.platform.to_s && base.version == source.version && base.class == source.class
                  dup_index = dup ? index + 1 : index
                  obs = used_in.include?(source.name) && !dup
                  if source.valid? && !is_disabled?(source)
                     base = source
                     used_in = used_in | [source.name]
                  end

                  [res | [[source, source_status(source, dup, obs)]], dup_index, base]
               end.first

            deps = deps_in | sorten.map {|source, status| status == :valid ? source.dependencies : [] }.flatten

            sorten[1..-1].each { |x| sorten.first.first.alias_to(x.first) }

            [r|[sorten], used_in, deps]
         end

      pre.first.flatten(1).map do |(source, status)|
            if status == :disabled &&
               pre[2].any? do |dep|
                  dep.name == source.name && source.is_a?(Setup::Source::Gem) &&
                  dep.requirement.satisfied_by?(source.provide.requirement.requirements.last.last)
               end
               [source, :regarded]
            else
               [source, status]
            end
         end.sort_by {|(x, _)| x.root.size }.each do |(source, status)|
            block[source, status] if block_given?
         end
   end

      # returns source tree, and sorted, and then grouped by a its rootdir value
      #
      def stat_source_tree
         @stat_source_tree ||=
            stat_sources.group_by {|(x, _)| x.root }.map do |(path, sources)|
               [File.join('.', path[rootdir.size..-1] || ''), sources]
            end.to_h
      end

      # returns status for the source for the project
      #
      def source_status source, dup, obs
         %i(valid duplicated obsoleted disabled invalid).reduce() do |res, status|
            STATES[status][self, source, dup, obs] && status || res
         end
      end

    # Sets a source list from config
    #
    def stat_sources= value
       @stat_sources = value&.map do |(source_in, source_status)|
          source_in[:alias_names] = source_in[:alias_names] | (config&.aliases || [])
          source =
             case source_in.delete(:type)
             when 'rakefile'
                new_source(Setup::Source::Rakefile, source_in)
             when 'gemfile'
                new_source(Setup::Source::Gemfile, source_in)
             when 'gem'
                new_source(Setup::Source::Gem, source_in)
             end

          source ? [source, source_status] : nil
       end&.compact
    end

    # returns the valid sources for the project
    #
    def valid_sources
       @valid_sources ||= begin
          sources = stat_sources.map {|(source, status)| %i(valid regarded).include?(status) ? source : nil }.compact
          main = sources.find { |source| source.root == rootdir }
          sources |= [default_fake_source] unless main && main.valid?
          roots = sources.map(&:root)
          sources.each { |source| source.source_roots = roots }
          sources
       end
    end

   def default_fake_source
      Source::Fake.new(source_file: File.join(rootdir, ".fake"))
   end

    # options for the object
    #
    def new_source type, object_options_in
       # TODO enable back options_for
       type.new(type.source_options(object_options_in))
    end

    # options for the object
    #
#    def options_for type, object_options_in
#       option_keys = type.const_get(:OPTION_KEYS) || []
#       options_in = config.to_h.map { |(key, value)| [ key.to_sym, value ] }.to_h.merge(object_options_in)
#       option_keys.map { |key| [ key, options_in[ key ]] }.to_h
#    end

       # Returns a root source
       #
       def root_source
          @root_source ||= valid_sources.find { |source| rootdir == source.root }
       end

      def has_gem?
         stat_sources.any? {|(source, _)| source.is_a?(Setup::Source::Gem) }
      end

   def ignored_path_tokens
      @ignored_path_tokens ||= (config.ignore_path_tokens || []) | DEFAULT_IGNORE_PATH_TOKES
   end

   def regarded_path_tokens
      @regarded_path_tokens ||= (config.regard_path_tokens || [])
   end

   def is_platform_allowed? platform
      case platform
      when Gem::Platform
         PLATFORMS.any? {|(name, valid)| platform === name ? valid : nil }
      when String
         !!PLATFORMS[platform.to_sym]
      when NilClass
         true
      else
         false
      end
   end

   def is_version_allowed? version
      if /^[0-9\.]+(\.(?<post>[a-z]*|))?$/ =~ version
         !post || VERSIONS.reduce(true) {|res, (re, v)| res && (re =~ post ? v : false) }
      end
   end

   def is_disabled? source
      !is_platform_allowed?(source.platform) || !is_version_allowed?(source.version) ||
         regarded_path_tokens.map do |t|
            t.is_a?(Regexp) && %r{/[^/]*#{t}[^/]*/} || %r{/#{t}/}
         end.all? do |t|
            t !~ source.source_file
         end &&
         ignored_path_tokens.map do |t|
            t.is_a?(Regexp) && %r{/[^/]*#{t}[^/]*/} || %r{/#{t}/}
         end.any? do |t|
            t =~ source.source_file
         end ||
         config.regard_names.all? { |i| !i.match?(source.name) } &&
         config.ignore_names.any? { |i| i === source.name }
   end

      def compilable?
         stat_sources.any? { |(source, _)| source.compilable? }
      end

    #
    def yardopts
      Dir.glob(File.join(rootdir, '.yardopts')).first
    end

    #
    def document
      Dir.glob(File.join(rootdir, '.document')).first
    end

    # Find a file relative to project's root directory.
    def find(glob, flags=0)
      case flags
      when :casefold
        flags = File::FNM_CASEFOLD
      else
        flags = flags.to_i
      end
      Dir.glob(File.join(rootdir, glob), flags).first
    end

    def chroot
       File.expand_path(config.install_prefix)
    end

    def options
       @options.merge(chroot: chroot)
    end

    def autoalias
       source_names = valid_sources.map(&:name)

       valid_sources.each do |source|
          config.current_source_name = source.name

          name = source.name.gsub(/[_\-\.]+/, '-')
          if name != source.name
             config.current_alias = name
          end

          # autoaliasing binaries to the source name but when no other source name matches to a binfile
          config.current_alias = source.exefiles - (source.exefiles & source_names)
       end

       # turn current source name to common
       config.current_source_name = nil
    end

      def select_source name
         ObjectSpace.each_object(Setup::Source::Base).select { |x| x.name == name }
      end

   # +targets+ returns an install target list for the sources
   #
   # space.targets #=> [ <#Setup::Target::Gem...>, ... ]
   #
   # TODO move to target actor
      def targets
         @targets ||= (
            valid_sources.map do |source|
               case source
               when Setup::Source::Gem
                  Setup::Target::Gem.new(source: source, options: options.merge(config.to_h))
               when Setup::Source::Gemfile
                  Setup::Target::Site.new(source: source, options: options.merge(config.to_h))
               when Setup::Source::Rakefile, Setup::Source::Fake, Setup::Source::Base
                  Setup::Target::Site.new(source: source, options: options.merge(config.to_h))
               end
            end)
      end
  end
end
