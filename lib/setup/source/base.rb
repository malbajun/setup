require 'setup/source'
require 'setup/log'

class Setup::Source::Base
   extend ::Setup::Log

   OPTION_KEYS = %i(source_file source_names replace_list aliases alias_names loader)
   DEFAULT_FILES = %i(readme contrib history changelog license copying code_of_conduct)

   DL_DIRS     = ->(s) { ".so.#{s.name}#{RbConfig::CONFIG['sitearchdir']}" }
   RI_DIRS     = ->(s) { [ s.default_ridir, 'ri' ] }
   INC_DIRS    = %w(ext)
   EXT_DIRS    = %w(ext)
   LIB_DIRS    = %w(lib)
   APP_DIRS    = %w(app webpack script public)
   EXE_DIRS    = %w(bin exe)
   CONF_DIRS   = %w(etc config conf)
   TEST_DIRS   = %w(tests test spec features acceptance autotest)
   MAN_DIRS    = %w(doc docs Documentation man docs-source)
   SUP_DIRS    = %w(util yardoc benchmarks examples .git vendor sample)
   LOG_DIRS    = %w(log)
   DATA_DIRS   = %w(.)
   ALL_DIRS    = %w(.)
   STATE_DIRS  = %w(tmp ext)
   DOCSRC_DIRS = ->(s) { s.libdirs | s.appdirs | s.exedirs | s.confdirs }

   DL_RE       = ->(_) { /\.(#{RbConfig::CONFIG['DLEXT']}|build_complete)$/ }
   RI_RE       = /\.ri$/
   INC_RE      = /\.(h|hpp)$/
   MAN_RE      = /\.[1-8](.ronn)?$/
   EXT_RE      = /\b(.*\.rb|rakefile(\.rb)?)$/i
   DATA_RE     = ->(s) do
         dirs = s.extdirs | s.libdirs | s.appdirs | s.exedirs |
            s.confdirs | s.testdirs | s.mandirs | s.supdirs |
            s.ridirs | s.dldirs | s.incdirs | s.logdirs

         dirs.empty? && /.*/ || /^(?!#{dirs.join('\b|').gsub('.', '\\\\.')}\b)/
      end
   DOCSRC_RE = /\.rb$/

   GROUPS = constants.select { |c| c =~ /_DIRS/ }.map { |c| c.to_s.sub('_DIRS', '').downcase }

   OPTIONS_IN = {
      aliases: ->(o, name) { o.is_a?(Hash) && [ o[nil], o[name], o.values.map {|x|x.flatten}.select {|x|x.include?(name)}.map {|x|x.first}.flatten ].flatten.compact.uniq || o },
      alias_names: ->(o, name) do
        (o.is_a?(Hash) ? [
          o[nil]&.select {|g| g.grep(name).size > 0 },
          o[name],
          o.values.map {|x|x.flatten}.select {|x|x.include?(name)}.map {|x|x.first}.flatten
        ].flatten.compact.uniq : (o.is_a?(Array) ? o : [o])) | [name&.gsub(/[_.]+/, '-')].compact
      end,
      version_replaces: true,
      gem_version_replace: true,
      source_file: ->(file, _name) { file.is_a?(String) && File.file?(file) && file || nil },
      loader: true,
      gemspec: true,
      source_names: true,
      name: true,
      version: true,
      srcridirses: :name_or_default,
      srcincdirses: :name_or_default,
      srcextdirses: :name_or_default,
      srclibdirses: :name_or_default,
      srcappdirses: :name_or_default,
      srcexedirses: :name_or_default,
      srcconfdirses: :name_or_default,
      srctestdirses: :name_or_default,
      srcmandirses: :name_or_default,
      srcsupdirses: :name_or_default,
      srcdatadirses: :name_or_default,
      srcdocsrcdirses: :name_or_default,
      srclogdirses: :name_or_default,
      srcstatedirses: :name_or_default,
      srcridirs: true,
      srcincdirs: true,
      srcextdirs: true,
      srclibdirs: true,
      srcappdirs: true,
      srcexedirs: true,
      srcconfdirs: true,
      srctestdirs: true,
      srcmandirs: true,
      srcsupdirs: true,
      srcdatadirs: true,
      srcdocsrcdirs: true,
      srclogdirs: true,
      srcstatedirs: true,
   }

   attr_reader :options, :source_file, :loader
   attr_writer :replace_list, :source_names

   class << self
      def opts
         @opts ||= ancestors.reverse.map do |a|
            a.constants.include?(:OPTIONS_IN) &&
            a.const_get(:OPTIONS_IN).to_a ||
            nil
         end.compact.flatten(1).to_h
      end

      def name_for options_in
         fullname = (options_in[:root] || "").split('/').last
         /^(?<name>.*)-([\d\.]+)$/ =~ fullname
         name || fullname
      end

      def source_options options_in = {}
         name = name_for(options_in)

         opts.map do |oname_in, rule|
            value_in = options_in[oname_in]

            oname, value = case rule
               when true
                  [oname_in, value_in]
               when Proc
                  [oname_in, rule[value_in, name] ]
               when Symbol
                  method(rule)[value_in, oname_in, name]
               else
                  nil
               end

            value && [ oname, value ] || nil
         end.compact.to_h
      end

      def name_or_default value_in, oname, name
         value = value_in && (value_in[name] || value_in[nil]) || nil

         value && [ oname.make_singular, value ] || nil
      end
   end

   def fullname
      @fullname ||= root.split('/').last
   end

   def name
      @name ||= (
         /^(?<name>.*)-([\d\.]+)$/ =~ fullname
         name || fullname)
   end

   def version
      @version ||=
         root.split("/").reverse.reduce(nil) do |v, token|
            return v if v

            /-(?<version>[\d\.]+)$/ =~ token

            version
         end
   end

   # ruby platform is default for non-gem sources
   def platform
      'ruby'
   end

   def root
      @root ||= detect_root
   end

   def default_files
      Dir.chdir(File.join(root)) { Dir.glob('*') }.select { |f| /#{DEFAULT_FILES.join("|")}/i =~ f }
   rescue Errno::ENOENT
      []
   end

   def source_names
      @source_names ||= options[:source_names] || source_file && [File.basename(source_file)] || []
   end

   def dsl
      @dsl ||= options[:dsl] ||
         Setup::DSL.new(source_file,
            spec: spec,
            replace_list: replace_list,
            skip_list: (options[:gem_skip_list] || []) | [name],
            append_list: options[:gem_append_list])
   end

   def all_dependencies
      compilables # NOTE required to collect build deps

      dsl.all_dependencies
   end

   def replace_list
      @gem_version_replace ||= options[:gem_version_replace] || {}
   end

   def alias_names
      @alias_names ||= options[:alias_names] || []
   end

   # dirs
   #
   GROUPS.each do |kind|
      func = <<-DEF
         def #{kind}dirs &block
            @#{kind}dirs ||= dirs(:#{kind}, options[:src#{kind}dirs], &block)
         end
      DEF

      eval(func)
   end

   # files
   #
   GROUPS.each do |kind|
      func = <<-DEF
         def #{kind}files &block
            @#{kind}files ||= files(:#{kind}, &block)
         end
      DEF

      eval(func)
   end

   # tree
   #
   GROUPS.each do |kind|
      func = <<-DEF
         def #{kind}tree &block
            @#{kind}tree ||= tree(:#{kind}, &block)
         end
      DEF

      eval(func)
   end

   # questionaries

   def valid?
      false
   end

   def compilable?
      extfiles.any?
   end

   def to_h
      options.merge(type: type, source_names: source_names)
   end

   def type
      self.class.to_s.split('::').last.downcase
   end

   def required_ruby
      dsl.required_ruby
   end

   def required_ruby_version
      dsl.required_ruby_version
   end

   def required_rubygems_version
      dsl.required_rubygems_version
   end

   def definition
      dsl.definition
   end

   def deps groups_in = nil
      dsl.deps_for(groups_in)
   end

   def has_name? name
      self.name == name || alias_names.include?(name)
   end

   def if_file file
      File.file?(File.join(root, file)) && file || nil
   end

   def if_exist file
      File.exist?(File.join(root, file)) && file || nil
   end

   def if_dir dir
      File.directory?(File.join(root, dir)) && dir || nil
   end

   def default_ridir
      ".ri.#{name}"
   end

   def trees &block
      GROUPS.map do |set|
         yield(set, send("#{set}tree"))
      end
   end

   def compilables
      # TODO make compilables from ext
      extfiles
   end

   def provide
      Bundler::Dependency.new(name, "= #{version || "0"}", "group" => [:default])
   end

   def dependencies *types
      all_dependencies.select {|dep| types.empty? || types.include?(dep.type) }
   end

   def + other
      self.replace_list = replace_list.merge(other.replace_list)
      self.source_names = source_names | other.source_names
      self.dsl.merge_in(other.dsl)

      self
   end

   def aliases
      @aliases ||= []
   end

   def alias_to *sources
      @aliases = aliases | sources.flatten
   end

   protected

   def exedir
      @exedir ||= if_exist('exe')
   end

   def dirs kind, dirs_in = nil, &block
      dirlist_am = [
         dirs_in,
         options[:"src#{kind}dirs"],
         self.class.const_get("#{kind.upcase}_DIRS")
      ].compact.first

      [ dirlist_am ].flatten.map do |dir_am|
         file = dir_am.is_a?(Proc) ? dir_am[self] : dir_am
      end.flatten.compact.select { |file| if_dir(file) }
   end

   def list_in_dir dir
      Dir.chdir(File.join(root, dir)) { Dir.glob('**/**/*') }
   rescue Errno::ENOENT
      []
   end

   def chdir dir, &block
      Dir.chdir(File.join(root, dir), &block)
   rescue Errno::ENOENT
      []
   end

   def tree kind, &block
      re_in = self.class.const_get("#{kind.upcase}_RE") rescue nil
      prc = self.class.const_get("#{kind.upcase}_FILTER") rescue nil
      re = re_in.is_a?(Proc) && re_in[self] || re_in || /.*/

      tree_in = send("#{kind}dirs").map { |dir| [ dir, list_in_dir(dir) ]}.to_h

      if block_given?
         # TODO deep_merge
         tree_in = tree_in.merge(yield)
      end

      tree_in.map do |dir, files_in|
         files = chdir(dir) do
            files_in.select do |file|
               re =~ file && File.file?(file) && (!prc || prc[self, file, dir])
            end
         end

         # require 'pry';binding.pry if kind == :exe

         [ dir, files ]
      end.to_h
   end

   def detect_root
      source_file && File.dirname(source_file) || Dir.pwd
   end

   def files kind, &block
      send("#{kind}tree", &block).map { |(_, values)| values }.flatten
   end

   def initialize options_in = {}
      parse(options_in)

      @options = { replace_list: {} }.merge(options_in)

      @loader ||= self.class.to_s.split('::').last.downcase.to_sym
   end

   def parse options_in
      self.class.source_options(options_in).each do |option, value|
         instance_variable_set(:"@#{option}", value)
      end
   end
end
