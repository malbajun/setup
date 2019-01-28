class Setup::Target::Site
   attr_reader :home

   def libdir
      spec_path(home && File.join(home, 'lib'), RbConfig::CONFIG['rubylibdir'])
   end

   def lbindir
      lbindir = RbConfig::CONFIG['bindir']

      lbindir != bindir && lbindir || nil
   end

   def bindir
      spec_path(home && File.join(home, 'bin'), RbConfig::CONFIG['bindir'])
   end

   def extdir
      spec_path(home && File.join(home, 'lib'), RbConfig::CONFIG['archdir'])
   end

   def ridir
      spec_path(home && File.join(home, 'doc'), RbConfig::CONFIG['ridir'])
   end

   protected

   def spec_path *args
      args.compact.select { |path| File.exist?(path) }.first
   end

   def initialize home: ENV['MY_RUBY_HOME']
      @home = home || RbConfig::CONFIG['rubylibprefix']
   end
end
