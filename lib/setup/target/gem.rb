require 'setup/target'

class Setup::Target::Gem
   attr_reader :gem, :home, :root

   def source
      gem
   end

   # dirs

   def libdir
      File.join(home, 'gems', gem.fullname, gem.require_dir)
   end

   def lbindir
      lbindir = RbConfig::CONFIG['bindir']

      lbindir != bindir && lbindir || nil
   end

   def datadir
      File.join(home, 'gems', gem.fullname)
   end

   def bindir
      File.exist?(exedir) && exedir || File.join(home, 'gems', gem.fullname, 'bin')
   end

   def extdir
      arch = [ ::Gem.platforms.last.cpu, ::Gem.platforms.last.os ].join('-')

      $stderr.puts home, 'extensions', arch, ::Gem.extension_api_version, gem.fullname
      File.join(home, 'extensions', arch, ::Gem.extension_api_version, gem.fullname)
   end

   def ridir
      File.join(home, 'doc', gem.fullname, 'ri')
   end

   def specdir
      File.join(home, 'specifications')
   end

   def mandir
      RbConfig::CONFIG['mandir']
   end

   def includedir
      RbConfig::CONFIG['includedir']
   end

   # files

   def binfiles chroot = '/'
      Dir.glob(File.join(chroot, bindir, '*')).map { |file| /^#{chroot}(?<pure>.*)/.match(file)[:pure] }
   end

   protected

   def exedir
      File.join(home, 'gems', gem.fullname, 'exe')
   end

   def initialize gem: raise, root: nil, home: ENV['GEM_HOME'] || ::Gem.paths.home
      @gem = gem
      @root = root
      @home = home
   end
end
