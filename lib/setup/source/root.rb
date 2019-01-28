class Setup::Source::Root
   attr_reader :root

   class << self
      def search dir, _ = {}
         if File.exist?("#{dir}/Gemfile")
            self.new(root: dir)
         end
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
      @ridir ||= File.join(root, 'ri')
   end

   def dldir
      extdir
   end

   def mandir
      @mandir ||= %w(man Documentation).reduce(nil) do |r, dir|
         r || File.directory?(File.join(root, dir)) && dir || nil
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
      @manfiles ||= mandir && Dir.glob("#{mandir}/*.{1,2,3,4,5,6,7,8}").select { |file| File.file?(file) } || []
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
