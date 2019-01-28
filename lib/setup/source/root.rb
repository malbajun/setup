class Setup::Source::Root
   attr_reader :root

   class << self
      def search dir, _ = {}
         self.new(root: dir)
      end
   end

   def gemfile
      @gemfile ||= root && (
         file = "#{root}/Gemfile"
         File.exist?(file) && file || nil)
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
      @version ||= (
         /-(?<version>[\d\.]+)$/ =~ fullname
         version)
   end

   def doc_sourcedirs
      %w(app config).select { |file| File.directory?(file) }
   end

   # dirs

   def libdir
      @libdir ||= root
   end

   def bindir
      @bindir ||= File.exist?(exedir) && exedir || File.join(root, 'exe')
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

   # files

   def libfiles
      @libfiles ||= Dir.glob("#{libdir}/**/*.rb").select { |file| File.file?(file) }
   end

   def rifiles
      @rifiles ||= Dir.glob("#{ridir}/**/*.ri").select { |file| File.file?(file) }
   end

   def extfiles
      @extfiles ||= Dir.glob("#{extdir}/**/extconf.rb").select { |file| File.file?(file) }
   end

   def dlfiles
      @dlfiles ||= extroots.map { |extroot| Dir.glob("#{extroot}/**/*.{#{dlext},build_complete}") }.flatten.select { |file| File.file?(file) }
   end

   def binfiles
      @binfiles ||= Dir.glob("#{bindir}/*").select { |file| File.file?(file) }
   end

   def manfiles
      @manfiles ||= Dir.glob("#{mandirs.join(',')}/**/*.{1,2,3,4,5,6,7,8}").select { |file| File.file?(file) }
   end

   def datafiles
      []
   end

   def includefiles
      []
   end

   def doc_sourcefiles
      doc_sourcedirs
   end

   # custom

   def extroot_for file
      extroots.find { |extroot| extroot == file[0...extroot.size] }
   end

   # questionaries

   def valid?
      !gemfile.nil?
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
   def initialize(root: Dir.pwd)
      @root = root
   end
end
