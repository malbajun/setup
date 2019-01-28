require 'setup/source'

require 'tempfile'

class Setup::Source::Gem
   BIN_IGNORES = %w(test)

   attr_reader :root, :spec, :mode

   class << self
      def search dir, options = {}
         gemspecs = Setup::Gemspec.constants.map { |const| Setup::Gemspec.const_get(const) }

         specs = Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).map do |f|
            gemspecs.reduce(nil) do |s, gemspec|
               s || gemspec::RE =~ f && (spec = gemspec.parse(f)) && self.new(root: File.dirname(f), spec: spec, mode: options[:mode])
            end
         end.compact

         specs.map { |x| x.name }.uniq.map { |name| specs.find { |spec| spec.name == name } }
      end
   end

   def fullname
      [ name, version ].compact.join('-')
   end

   def name
      spec && spec.name
   end

   def version
      spec && spec.version.to_s
   end

   def gemspec_file
      gemspec_file = Tempfile.new('gem.')
      gemspec_file.puts(spec.to_ruby)
      gemspec_file.rewind
      gemspec_file.path
   end

   # many dirs

   def require_pure_paths
      @require_pure_paths ||= (
         paths = spec.require_paths.select { |path| path !~ /\// }
         paths.any? && paths || ['lib'])
   end

   def doc_sourcedirs
      require_pure_paths
   end

   # single dir

   def require_dir
      require_pure_paths.first
   end

   def libdir
      @libdir ||= File.join(root, require_dir)
   end

   def datadir
      root
   end

   def bindir
      @bindir ||= File.exist?(exedir) && exedir || File.join(root, 'bin')
   end

   def extdir
      @extdir ||= File.join(root, 'ext')
   end

   def ridir
      @ridir ||= File.join(root, ".ri.#{name}")
   end

   def dldir
      extdir
   end

   def mandir
      @mandir ||= mandirs.first
   end

   def mandirs
      @mandirs ||= %w(man Documentation doc).select do |dir|
         File.directory?(File.join(root, dir))
      end
   end

   def includedir
      extdir
   end

   # files

   def libfiles
      @libfiles ||= (
         f = if mode == :lust
           # lust approach
           files_in = spec.files.select {|file| /^(#{require_pure_paths.join('|')})\// =~ file }.map { |file| File.join(root, file) }
           (files_in.any? && files_in || Dir.glob("#{root}/{#{require_pure_paths.join(',')}}/**/*")).select { |file| /\.rb$/ =~ file }
         else
           # strict list based on files
           files_in = spec.files.any? && spec.files.select {|file| /^(#{require_pure_paths.join('|')})\// =~ file }.map { |file| File.join(root, file) }
           (files_in || Dir.glob("#{root}/{#{require_pure_paths.join(',')}}/**/*")).select { |file| /\.rb$/ =~ file }
         end

       f
      )
   end

   def datafiles
      @datafiles ||= (
         f = 
         if mode == :lust
#           # lust approach
           files_in = spec.files.select { |file| /\.rb$/ !~ file && /^(#{non_data_pure_paths.join('|')})\// !~ file }.map { |file| File.join(root, file) }

           (files_in.any? && files_in ||
            (Dir.glob("#{datadir}/**/*").select { |file| !/^#{datadir}\/?(#{non_data_pure_paths.join('|')})\/.*/.match(file) } +
             Dir.glob("#{root}/{#{require_pure_paths.join(',')}}/**/*").select { |file| /\.rb$/ !~ file })).select { |file| File.file?(file) }
      else
           # strict list based on files
           files_in = spec.files.any? && spec.files.select { |file| /\.rb$/ !~ file && /^(#{non_data_pure_paths.join('|')})\// !~ file }.map { |file| File.join(root, file) }
            (files_in ||
            (Dir.glob("#{datadir}/**/*").select { |file| !/^#{datadir}\/?(#{non_data_pure_paths.join('|')})\/.*/.match(file) } +
             Dir.glob("#{root}/{#{require_pure_paths.join(',')}}/**/*").select { |file| /\.rb$/ !~ file })).select { |file| File.file?(file) }

          end
          f
      )
   end

   def rifiles
      @rifiles ||= Dir.glob("#{ridir}/**/*.ri").select { |file| File.file?(file) }
   end

   def extfiles
      @extfiles ||= spec.extensions.select { |file| /extconf\.rb$/ =~ file }.map {|path| File.join(root, path) }
   end

   def dlfiles
      @dlfiles ||= extroots.map { |extroot| Dir.glob("#{extroot}/**/*.{#{dlext},build_complete}") }.flatten.select { |file| File.file?(file) }
   end

   def binfiles
      @binfiles ||= Dir.glob("#{bindir}/*").select { |file| File.file?(file) && !BIN_IGNORES.include?(File.basename(file)) }
   end

   def manfiles
      @manfiles ||= !mandirs.empty? && Dir.glob("#{mandirs.join(',')}/**/*.{1,2,3,4,5,6,7,8}").select { |file| File.file?(file) } || []
   end

   def includefiles
      @includefiles ||= Dir.glob("#{includedir}/**/*.h{,pp}").select { |file| File.file?(file) }
   end

   def doc_sourcefiles
      doc_sourcedirs + spec.extra_rdoc_files
   end

   # custom

   def extroot_for file
      extroots.find { |extroot| extroot == file[0...extroot.size] }
   end

   def non_data_pure_paths
      %w(spec test bin exe feature acceptance docs man Documentation benchmarks ri examples yardoc ext autotest .git tmp vendor sample) + require_pure_paths
   end

   # Queries
   
   # +valid?+ returns state of validity of the gem: true or false
   # Returns true when name of the gem is set.
   # 
   def valid?
      !name.nil?
   end

   def compilable?
      extfiles.any?
   end

   protected

   def extroots
      @extroots ||= extfiles.map { |extfile| File.dirname(extfile) }
   end

   def dlext
      RbConfig::CONFIG['DLEXT']
   end

   def exedir
      @exedir ||= File.join(root, 'exe')
   end

   #
   def initialize root: nil, spec: nil, mode: nil
      @spec = spec
      @root = root || Dir.pwd
      @mode = mode
   end
end
