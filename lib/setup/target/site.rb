class Setup::Target::Site
   attr_reader :home, :root

   def source
      root
   end

   # dirs

   def libdir
      File.join(RbConfig::CONFIG['sitelibdir'], root.name)
   end

   def lbindir
      nil
   end

   def bindir
      File.join(RbConfig::CONFIG['bindir'], root.name)
   end

   def extdir
      File.join(RbConfig::CONFIG['sitearchdir'], root.name)
   end

   def ridir
      File.join(RbConfig::CONFIG['ridir'], root.name)
   end

   def specdir
      nil
   end

   def mandir
      RbConfig::CONFIG['mandir']
   end

   # files

   def binfiles chroot = '/'
      Dir.glob(File.join(chroot, bindir, '*')).map { |file| /^#{chroot}(?<pure>.*)/.match(file)[:pure] }
   end

   protected

   def initialize root: raise
      @root = root
   end
end
