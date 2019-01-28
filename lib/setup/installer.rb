require 'setup/base'

module Setup

  # Installer class handles the actual install procedure.
  #
  # NOTE: This new version does not support per-directory hooks.
  #
  class Installer < Base

      # Returns an install target
      def targets
         @targets ||= (
            case config.type
            when 'auto'
               if project.has_gem?
                  gem_targets
               else
                  site_targets
               end
            when 'gem'
               gem_targets
            when 'site'
               site_targets
            when 'ruby'
            end.compact)
      end

      def gem_targets
         project.sources.map do |source|
            if source.is_a?(Setup::Source::Gem)
              Setup::Target::Gem.new(gem: source, gemfile: project.root_source)
            end
         end
      end

      def site_targets
         project.sources.map do |source|
            if source.is_a?(Setup::Source::Root)
              Setup::Target::Site.new(root: project.root_source)
            end
         end
      end

    #
    def install_prefix
      config.install_prefix
    end
    #attr_accessor :install_prefix

    # Install package.
    def install
      Dir.chdir(rootdir) do
        install_bin
        install_ext
        install_lib
        install_data
        install_man
        install_ri
#        install_etc
        install_gemspec
#        prune_install_record
      end
    end

    # Install binaries (executables).
    def install_bin
      io.puts "* bin ->" unless quiet?

      targets.each do |target|
        next if !target.source.binfiles.any?

        io.puts "  - [#{target.source.name}] => #{target.bindir}" unless quiet?

        install_files(target.source.binfiles, target.bindir, options.merge(mode: 0755, source_dir: target.source.bindir))

        if target.lbindir
          install_files(target.binfiles(options[:chroot]), target.lbindir, options.merge(mode: 0755, symlink: true, source_dir: target.bindir))
        end
      end
    end

    # Install shared extension libraries.
    def install_ext
      io.puts "* ext ->" unless quiet?

      targets.each do |target|
        next if !target.source.dlfiles.any?

        io.puts "  - [#{target.source.name}] => #{target.extdir}" unless quiet?

        target.source.dlfiles.each do |file|
          install_files([file], target.extdir, options.merge(mode: 0555, source_dir: target.source.extroot_for(file)))
        end
      end
    end

    # Install library files.
    def install_lib
      io.puts "* lib ->" unless quiet?

      targets.each do |target|
        next if !target.source.libfiles.any?

        io.puts "  - [#{target.source.name}] => #{target.libdir}" unless quiet?

        install_files(target.source.libfiles, target.libdir, options.merge(source_dir: target.source.libdir))
      end
    end

    # Install shared data.
    def install_data
      io.puts "* data ->" unless quiet?

      targets.each do |target|
        next if !target.source.datafiles.any?

        io.puts "  - [#{target.source.name}] => #{target.datadir}" unless quiet?

        install_files(target.source.datafiles, target.datadir, options.merge(source_dir: target.source.datadir))
      end
    end

    # Install configuration.
    def install_etc
      return unless directory?('etc')
      report_transfer('etc', config.sysconfdir)
      files = files('etc')
      install_files('etc', files, config.sysconfdir, 0644)
    end

    # Install manpages.
    def install_man
      io.puts "* man ->" unless quiet?

      targets.each do |target|
        next if !target.source.manfiles.any?

        io.puts "  - [#{target.source.name}] => #{target.mandir}" unless quiet?

        install_files(target.source.manfiles, target.mandir, options.merge(mode: 0644, source_dir: target.source.mandir))
      end
    end

    def install_ri
      io.puts "* ri ->" unless quiet?

      targets.each do |target|
        next if !target.source.rifiles.any?

        io.puts "  - [#{target.source.name}] => #{target.ridir}" unless quiet?

        install_files(target.source.rifiles, target.ridir, options.merge(mode: 0644, source_dir: target.source.ridir))
      end
    end

    # Install documentation.
    #
    # TODO: The use of the project name in the doc directory
    # should be set during the config phase. Define a seperate
    # config method for it.
    def install_doc
      return unless config.doc?

      folders = {
        'dir' => File.join(config.docdir, "#{project.name}"),
        'ri'  => config.ridir,
      }

      filters = {
        'gem' => /(created.rid|~$)/,
      }

      filter = filters[config.type] || /(cdesc-Object.ri|cache.ri|created.rid|~$)/

      folders.keys.select {|dir| File.directory?(dir) }.each do |dir|
        report_transfer(dir, folders[dir])
        # io.puts "* doc -> #{dir}" unless quiet?
        files = filter_out(files(dir), filter)
        install_files(dir, files, folders[dir], 0644)
      end
    end

    # Install specification.
    #
    def install_gemspec
      io.puts "* .gemspec ->" unless quiet?

      targets.each do |target|
        if target.source.is_a?(Setup::Source::Gem)
          io.puts "  - [#{target.source.name}] => #{target.specdir}" unless quiet?

          install_files([target.source.gemspec_file], target.specdir, options.merge(mode: 0644, source_dir: target.source.root, as: "#{target.source.fullname}.gemspec"))
        end
      end
    end

  private

    def paths
       if project.is_gem?
         project.gems.map { |gem| gem.gemroot }
       else
         [ Dir.pwd ]
       end
    end

    # Display the file transfer taking place.
    def report_transfer(source, directory)
      unless quiet?
        if install_prefix
          out = File.join(install_prefix, directory)
        else
          out = directory
        end
        io.puts "* #{source} -> #{out}"
      end
    end

    # Confirm a +path+ is a directory and exists.
#    def directory?(path)
#      project.is_gem? || File.directory?(path)
#    end

    # Confirm a gemspec exists.
#    def gemspec?
#      !project.gems.map { |gem| gem.spec }.compact.any?
#    end

    # Get a list of project files given a project subdirectory.
    def files(dir)
      paths.each do |root|
        Dir[File.join(root, dir, '**', '*')]
          .select{ |f| File.file?(f) }
          .map{ |f| f.sub("#{dir}/", '') }
      end.flatten
    end

    # Extract dynamic link libraries from all ext files.
    def select_dllext(files)
      ents = files.select { |file| File.extname(file) =~ dllext }

      if ents.empty? && !files.empty?
        raise Error, "ruby extention not compiled: 'setup.rb compile' first"
      end

      ents
    end

    # Filtering out the files list according the specified regexp
    def filter_out files, re
      files.reject {|f| f =~ re }
    end

    # Dynamic link library extension for this system.
    def dllext
      # from Configuration::RBCONFIG['DLEXT']
      dlext = [ config.dlext, 'build_complete' ]

      /\.(#{dlext.join('|')})/
    end

    # Install project files.
    def install_files(source_files, dest_dir, options = {})
      source_files.each do |file|
        dest_file = destination(dest_dir, file, options)

        FileUtils.mkdir_p(File.dirname(dest_file))
        if options[:symlink]
          FileUtils.ln_s(file, dest_file, force: true)
        else
          FileUtils.install(file, dest_file, mode: options[:mode])
        end
      end
    end

    def options
       {
          chroot: config.install_prefix,
          mode: 0644
       }
    end

    # Install a project file.
    def install_file(dir, from, dest, mode, prefix=nil, options = {})
      mkdir_p(File.dirname(dest))
  
      if trace? or trial?
        #to = prefix ? File.join(prefix, dir, from) : File.join(dir, from)
        io.puts "install #{dir}/#{from} #{dest}"
      end

      return if trial?

      str = binread(File.join(dir, from))

      if diff?(str, dest)
        trace_off {
          rm_f(dest) if File.exist?(dest)
        }
        File.open(dest, 'wb'){ |f| f.write(str) }
        File.chmod(mode, dest)
      end

      if link_to = options.delete(:link_to)
        dfile = destination(link_to, from)
        FileUtils.rm_f(dfile)
        FileUtils.mkdir_p(File.dirname(dfile))
        FileUtils.ln_s(dest, dfile)
      end

      record_installation(dest) # record file as installed
    end

    # Install a directory.
    #--
    # TODO: Surely this can be simplified.
    #++
    def mkdir_p(dirname) #, prefix=nil)
      #dirname = destination(dirname)
      #dirname = File.join(prefix, File.expand_path(dirname)) if prefix
      return if File.directory?(dirname)

      io.puts "mkdir -p #{dirname}" if trace? or trial?

      return if trial?

      # Does not check '/', it's too abnormal.
      dirs = File.expand_path(dirname).split(%r<(?=/)>)
      if /\A[a-z]:\z/i =~ dirs[0]
        disk = dirs.shift
        dirs[0] = disk + dirs[0]
      end
      dirs.each_index do |idx|
        path = dirs[0..idx].join('')
        unless File.dir?(path)
          Dir.mkdir(path)
        end
        record_installation(path)  # record directories made
      end
    end

    # Record that a file or directory was installed in the
    # install record file.
    def record_installation(path)
      File.open(install_record, 'a') do |f|
        f.puts(path)
      end
      #io.puts "installed #{path}" if trace?
    end

    # Remove duplicates from the install record.
    def prune_install_record
      entries = File.read(install_record).split("\n")
      entries.uniq!
      File.open(install_record, 'w') do |f|
        f << entries.join("\n")
        f << "\n"
      end
    end

    # Get the install record file name, and ensure it's location
    # is prepared (ie. make it's directory).
    def install_record
      @install_record ||= (
        file = INSTALL_RECORD
        dir  = File.dirname(file)
        unless File.directory?(dir)
          FileUtils.mkdir_p(dir)
        end
        file
      )
    end

    #realdest = prefix ? File.join(prefix, File.expand_path(dest)) : dest
    #realdest = File.join(realdest, from) #if File.dir?(realdest) #File.basename(from)) if File.dir?(realdest)

    # Determine actual destination including install_prefix.
    def destination(dir, file, options = {})
      dest = File.join(options[:chroot] || '', File.expand_path(dir))
      matched = /^#{options[:source_dir]}\/?(?<dest_file>.*)/.match(file)
      File.expand_path(File.join(dest, options[:as] || matched[:dest_file]))
    end

    # Is a current project file different from a previously
    # installed file?
    def diff?(new_content, path)
      return true unless File.exist?(path)
      new_content != binread(path)
    end

    # Binary read.
    def binread(fname)
      File.open(fname, 'rb') do |f|
        return f.read
      end
    end

    # TODO: The shebang updating needs some work.
    #
    # I beleive that on unix-based systems <tt>#!/usr/bin/env ruby</tt>
    # is the appropriate shebang.

    #
    def install_shebang(files, dir)
      files.each do |file|
        path = File.join(dir, File.basename(file))
        update_shebang_line(path)
      end
    end

    #
    def update_shebang_line(path)
      return if trial?
      return if config.shebang == 'never'
      old = Shebang.load(path)
      if old
        if old.args.size > 1
          $stderr.puts "warning: #{path}"
          $stderr.puts "Shebang line has too many args."
          $stderr.puts "It is not portable and your program may not work."
        end
        new = new_shebang(old)
        return if new.to_s == old.to_s
      else
        return unless config.shebang == 'all'
        new = Shebang.new(config.rubypath)
      end
      $stderr.puts "updating shebang: #{File.basename(path)}" if trace?
      open_atomic_writer(path) do |output|
        File.open(path, 'rb') do |f|
          f.gets if old   # discard
          output.puts new.to_s
          output.print f.read
        end
      end
    end

    #
    def new_shebang(old)
      if /\Aruby/ =~ File.basename(old.cmd)
        Shebang.new(config.rubypath, old.args)
      elsif File.basename(old.cmd) == 'env' and old.args.first == 'ruby'
        Shebang.new(config.rubypath, old.args[1..-1])
      else
        return old unless config.shebang == 'all'
        Shebang.new(config.rubypath)
      end
    end

    #
    def open_atomic_writer(path, &block)
      tmpfile = File.basename(path) + '.tmp'
      begin
        File.open(tmpfile, 'wb', &block)
        File.rename tmpfile, File.basename(path)
      ensure
        File.unlink tmpfile if File.exist?(tmpfile)
      end
    end

    #
    def distclean
      %w(SetupConfig .gemspecs).each { |f| FileUtils.rm_rf(f) }
    end


    def bindirs
      config.bindir
    end

    #
    class Shebang
      def Shebang.load(path)
        line = nil
        File.open(path) {|f|
          line = f.gets
        }
        return nil unless /\A#!/ =~ line
        parse(line)
      end

      def Shebang.parse(line)
        cmd, *args = *line.strip.sub(/\A\#!/, '').split(' ')
        new(cmd, args)
      end

      def initialize(cmd, args = [])
        @cmd = cmd
        @args = args
      end

      attr_reader :cmd
      attr_reader :args

      def to_s
        "#! #{@cmd}" + (@args.empty? ? '' : " #{@args.join(' ')}")
      end
    end

  end

end

