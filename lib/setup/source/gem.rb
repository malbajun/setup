require 'bundler/dependency'
require 'tempfile'
require 'date'

require 'setup/source/base'
require 'setup/loader'
require 'setup/loader/yaml'
require 'setup/loader/pom'
require 'setup/loader/rookbook'
require 'setup/loader/cmake'
require 'setup/loader/mast'
require 'setup/loader/git-version-gen'

class Setup::Source::Gem < Setup::Source::Base
   extend ::Setup::Loader
   extend ::Setup::Loader::Yaml
   extend ::Setup::Loader::Pom
   extend ::Setup::Loader::Mast
   extend ::Setup::Loader::Rookbook
   extend ::Setup::Loader::Cmake
   extend ::Setup::Loader::GitVersionGen

   TYPE = 'Gem::Specification'
   BIN_IGNORES = %w(test)
   OPTION_KEYS = %i(source_file source_names gemspec spec version replace_list aliases alias_names)

   EXE_DIRS = ->(s) { s.spec.bindir || s.exedir || nil }
   EXT_DIRS = ->(s) do
      s.spec.extensions.map do |file|
         File.dirname(file)
      end.uniq
   end
   LIB_DIRS = ->(s) { s.require_pure_paths }
   DOCSRC_DIRS = ->(s) { s.require_pure_paths }

   INC_FILTER  = ->(s, f, dir) { s.spec.files.include?(File.join(dir, f)) }

   # Document packaged libraries and explicitly declared root Ruby guides only.
   DOCSRC_FILTER = ->(source, file, directory) do
      directory == '.' ? source.spec.extra_rdoc_files.include?(file) :
         source.spec.files.include?(File.join(directory, file))
   end

   OPTIONS_IN = {
      spec: true,
   }

   LOADERS = {
      /\/pom.xml$/ => :pom,
      /\/(cmake|CMakeLists.txt)$/ => :cmake,
      /\/Rookbook.props$/ => :rookbook,
      /\/GIT-VERSION-GEN$/ => :git_version_gen,
      /\/MANIFEST$/ => :manifest,
      /\/(#{Rake::Application::DEFAULT_RAKEFILES.join("|")})$/i => :app_file,
      /\.gemspec$/i => [:app_file, :yaml],
   }

   class << self
      def spec_for options_in = {}
         spec_in = options_in[:spec]
         spec = spec_in.is_a?(String) && Setup.load(spec_in) || spec_in
         version =
            if options_in[:version_replaces] && options_in[:version_replaces][spec.name]
               options_in[:version_replaces][spec.name]
            elsif options_in[:gem_version_replace] && !options_in[:gem_version_replace].empty?
               prever = options_in[:gem_version_replace].find {|(n,v)| n == spec.name }&.last
               /([=><]+\s*)?(?<version>.*)/ =~ prever
               version
            end

         if version
            spec.version = Gem::Version.new(version)
         end

         spec.require_paths = options_in[:srclibdirs] if options_in[:srclibdirs]

         spec
      end

      def name_for options_in = {}
         spec_for(options_in).name
      end

      def search dir, options_in = {}
         files = Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).select {|f| File.file?(f) }.map do |f|
            LOADERS.reduce(nil) { |res, (re, _method_name)| res || re =~ f && [re, f] || nil }
         end.compact.sort do |x,y|
            c = LOADERS.keys.index(x.first) <=> LOADERS.keys.index(y.first)

            c == 0 && x.last <=> y.last || c
         end

         debug("Found source file list: " + files.map {|(_, x)| x }.join("\n\t"))

         specs = files.reduce({}) do |res, (re, f)|
            load_result =
               [LOADERS[re]].flatten.reduce(nil) do |res, method_name|
                  next res if res

                  result = send(method_name, f)

                  result && result.objects.any? && [result, method_name]
               end

            if load_result
               gemspecs = load_result.first.objects.reject do |s|
                  s.loaded_from && s.loaded_from !~ /#{dir}/
               end.each {|x| x.loaded_from = f }.compact
               debug("load messages:\n\t" + load_result.first.log.join("\n\t")) if !load_result.first.log.blank?
               debug("Load errors:\n\t" + load_result.errlog.join("\n\t")) if !load_result.first.errlog.blank?

               res.merge({ f => { gemspecs: gemspecs, loader: load_result.last }})
            else
               res
            end
         end.map do |(f, data)|
            data[:gemspecs].map do |gemspec|
               self.new(source_options(options_in.merge(spec: gemspec, source_file: f, loader: data[:loader])))
            end
         end.flatten.compact
      end
   end

   def gemfile
      @gemfile ||= Setup::Source::Gemfile.new(
         source_file: gemfile_name && File.join(root, gemfile_name) || dsl.fake_gemfile_path,
         gem_version_replace: options[:gem_version_replace],
         gem_skip_list: [], # dsl.deps.map(&:name),
         gem_append_list: [ self.dep ])
   end

   def gemfile_name
      source_names.find {|x| x =~ /gemfile/i }
   end

   def dep
      Bundler::Dependency.new(name, Gem::Requirement.new(["= #{version}"]), options: { type: :runtime })
   end

   def fullname
      [ name, version ].compact.join('-')
   end

   def original_spec
      return @original_spec if @original_spec.is_a?(Gem::Specification)

      @original_spec =
         if @original_spec.is_a?(String)
            Setup.load(@original_spec)
         else
            self.class.spec_for(options)
         end
   end

   def spec
      if aliases.any?
         @spec ||= aliases.reduce(original_spec) { |spec, als|
            spec.merge(als.original_spec) }
      else
         original_spec
      end
   end

   def name
      spec && spec.name
   end

   def version
      version = spec&.version&.to_s || ""
      parts = version.split(".")

      (parts[0..2] + (parts[3..-1]&.map {|x| x.to_i <= 1024 && x || nil}&.compact || [])).join(".")
   end

   def gemspec_path
      if !@gemspec_file && @gemspec_file ||= Tempfile.create('gemspec.')
         @gemspec_file.puts(dsl.to_ruby)
         @gemspec_file.close
      end

      @gemspec_path ||= @gemspec_file.path
   end

   def gemfile_path
      if gemfile.dsl.valid?
         if !@gemfile_file && @gemfile_file ||= Tempfile.create('Gemfile.')
            @gemfile_file.puts(gemfile.dsl.to_gemfile)
            @gemfile_file.close
         end

         @gemfile_path ||= @gemfile_file.path
      end
   end

   # +alltree+ all the files tree for gem
   def alltree
      @alltree ||=
         begin
            all_in =
               super { {
                  '.' =>
                     spec.files |
                     default_files |
                     spec.extra_rdoc_files |
                     spec.executables |
                     Dir.glob(spec.bindir)
               } }

            tree_except_for(alltree, *%w(state))
         end
   end

   # +datatree+ data tree for gem is thr all files except included into the group trees:
   # ext lib exe conf test man sup log state
   def datatree
      @datatree ||=
         begin
            tree_except_for(alltree, *%w(ext lib exe conf test man sup log))
         end
   end

   def tree_except_for hash, *trees
      trees.reduce(hash) do |h, tree|
         treelist_in =
            send("#{tree}tree").map do |(root,files)|
               files.map { |file| File.expand_path(File.join(root, file)) }
            end.flatten

         h.to_a.reduce({}) do |hh, (root, files)|
            nlist = files.reduce([]) { |nl, file| treelist_in.include?(File.expand_path(File.join(root, file))) ? nl : nl | [file] }
            hh.merge(root => nlist)
         end
      end
   end

   def allfiles
      @allfiles = (
         spec.require_paths.map {|x| File.absolute_path?(x) && x || File.join(x, '**', '*') }.map {|x| Dir[x] }.flatten |
         spec.executables.map {|x| Dir[File.join(spec.bindir, x)] }.flatten |
         spec.files | default_files
      )
   end

   def allfiles_for list_in
      list_in.map do |(key, list)|
         [key, list & allfiles.map {|x| /^#{key}\/(?<rest>.*)/.match(x)&.[](:rest) }.compact ]
      end.to_h
   end


   def libdirs
      @libdirs ||=
         begin
            libs = spec.require_paths.select {|x| File.directory?(File.join(root, x)) }

            libs.empty? && super || libs
         end
   end

   def libtree
      @libtree ||= tree_except_for(super, *%w(ext exe conf test man sup log state))
   end

   def exttree
      @exttree ||= super.merge(spec.extensions.reduce({}) do |res, ext|
         res[File.dirname(ext)] ||= []

         res[File.dirname(ext)] |= [File.basename(ext), 'gem.build_complete']

         res
      end)
   end

   def testtree
      @testtree ||= allfiles_for(super)
   end

   def exetree
      @exetree ||=
         super { Dir.chdir(root) do
            exedirs.map { |dir| [ dir, Dir.chdir(File.join(root, dir)) { Dir.glob("{#{spec.executables.join(',')}}") } ] }.to_h
         end }
   end

   def docsrctree
      @docsrctree ||= super { { '.' => spec.extra_rdoc_files } }
   end

   # custom

   def extroot_for file
      extroots.find { |extroot| extroot == file[0...extroot.size] }
   end

   # Queries

   # +valid?+ returns state of validity of the gem: true or false
   # Returns true when name of the gem is set.
   #
   def valid?
      !name.nil? &&
         spec.version &&
         (platform == 'ruby' || platform.cpu == RbConfig::CONFIG["target_cpu"]) &&
         spec.name !~ /\u0000/
   end

   def platform
      spec.platform
   end

   def compilable?
      extfiles.any?
   end

   def files kind = nil, &block
      kind ? super : spec.files | default_files
   end

   def to_h
      # TODO !ruby/array:Files strangely appeared during building the securecompare gem, what leads to exceptions on load
      super.merge(spec: spec.to_yaml.gsub(/!ruby\/array:Files/, ""))
   end

   def required_ruby_version
      spec&.required_ruby_version || super
   end

   def required_rubygems_version
      spec&.required_rubygems_version || super
   end

   def deps groups = nil
      spec&.dependencies&.select { |dep| !groups || [ groups ].flatten.include?(dep.type) }
   end

   def require_pure_paths
      @require_pure_paths ||= (
         paths = spec.require_paths.select { |path| path !~ /^\// }
         paths.any? && paths || ['lib'])
   end

   def rakes
      return @rakes unless @rakes.blank?

      files = Dir[File.join(root, "{#{Rake::Application::DEFAULT_RAKEFILES.join(",")}}")]
      @rakes = files.map {|file| Setup::Rake.new(file) }
   end

   def gemspec
      @gemspec ||= options[:gemspec]
   end

   protected

   def detect_root
      if spec
         files = Dir['**/**/**']
         (!spec.files.any? || (spec.files - files).any?) && super || Dir.pwd
      else
         super
      end
   end

   def extroots
      @extroots ||= extfiles.map { |extfile| File.dirname(extfile) }
   end

   def exedir
      @exedir ||= if_exist('exe')
   end

   def initialize options_in = {}
      super
   end
end
