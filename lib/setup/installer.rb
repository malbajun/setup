require 'setup/base'
require 'setup/actor'

module Setup

  # Installer class handles the actual install procedure.
  #
  # NOTE: This new version does not support per-directory hooks.
  #
  class Installer < Base

     def targets
       @targets ||= project.targets.select {|t| project.valid_sources.include?(t.source) }
     end
    #
    def install_prefix
      config.install_prefix
    end
    #attr_accessor :install_prefix

    # Install package.
    def install
      Dir.chdir(rootdir) do
        install_exe
        #_install :dl
        _install :lib
        install_man
        install_ri
        _install :inc
        _install :app
        _install :log
        _install :test
        _install :sup
        _install :conf
        install_data
        install_gemspec
        install_gemfile

        io.puts "* scheme" unless quiet?
        targets.each do |target|
          io.puts "{#{target.source.name}}" unless quiet?
          Setup::Actor.objectize(target).each do |context_in|
            context = context_in.merge("target" => target)

            next if context['$'].respond_to?(:allow) && !context['$'].allow(context)

            context['$'].apply(context)
          end
        end
      end
    end

    # Install binaries (executables).
    def install_exe
      io.puts "* {exe} ->" unless quiet?

      targets.each do |target|
        next if !target.source.exetree.any?

        target.source.exetree.each do |dir, files|
          Dir.chdir(File.join(target.source.root, dir)) do
            io.puts "  % #{target.source.name} < #{dir}" unless quiet?
            novel_install_files(files, target.exedir, options.merge(mode: 0755, shebang: config.shebang))
          end
        end

        if target.lexedir
          Dir.chdir(target.source.root) do
            io.puts "  % #{target.source.name}" unless quiet?
            novel_install_files(target.exefiles, target.lexedir, options.merge(mode: 0755, symlink: true))
          end
        end
      end
    end

    # Install shared data.
    def install_data
      io.puts "* {data} ->" unless quiet?

      targets.each do |target|
        next if !target.source.datatree.any?

        target.source.datatree.each do |dir, files|
          Dir.chdir(File.join(target.source.root, dir)) do
            io.puts "  % #{target.source.name} < #{dir}" unless quiet?

            novel_install_files(files, File.join(target.datadir, dir), options.merge(mode: 0644))
          end
        end
      end
    end

    def chdir dir, &block
       Dir.chdir(dir, &block)
    rescue
       nil
    end

    # Install for kind
    def _install kind
      io.puts "* {#{kind}} ->" unless quiet?

      targets.select { |t| t.source.send("#{kind}tree").any? }.each do |target|
        is_external = !target.send("#{kind}dir").include?(target.datadir)

        target.source.send("#{kind}tree").each do |dir, files|
          target_dir = is_external && target.send("#{kind}dir") || File.join(target.send("#{kind}dir"), dir)

          chdir(File.join(target.source.root, dir)) do
            io.puts "  % #{target.source.name} < #{dir}" unless quiet?

            novel_install_files(files, target_dir, options.merge(mode: 0644))
          end

          if is_external
            #require 'pry'
            #binding.pry
            novel_install_files(target.send("#{kind}dir"),
                                target.datadir,
                                options.merge(mode: 0644,
                                              symlink: true,
                                              as: dir))
          end
        end
      end
    end

    # Install manpages.
    def install_man
      io.puts "* {man} ->" unless quiet?

      targets.each do |target|
        next if !target.source.mantree.any?

        target.source.mantree.each do |dir, files|
          Dir.chdir(File.join(target.source.root, dir)) do
            io.puts "  % #{target.source.name} < #{dir}" unless quiet?

            files.each do |file|
              if file =~ /ronn$/
                begin
                  require 'ronn' #TODO add require embedded if is ronn itself
                rescue LoadError
                  $stderr.puts "[setup.rb] Ronn is unavailable: compilation from ronn will be disabled"
                else
                  opts = {
                    'styles' => %w[man]
                  }
                  doc = Ronn::Document.new(file, opts)
                  output = doc.convert('roff')
                  tmp = Tempfile.create
                  tmp.write(output)
                  tmp.rewind
                  novel_install_files([ tmp.path ], File.join(target.mandir, File.dirname(file)), options.merge(mode: 0644, as: file.gsub('.ronn', '')))
                  tmp.close
                end
              else
                novel_install_files([ file ], target.mandir, options.merge(mode: 0644))
              end
            end
          end
        end
      end
    end

    def install_ri
      io.puts "* {ri} ->" unless quiet?

      targets.each do |target|
        next if !target.source.ritree.any?

        target.source.ritree.each do |dir, files|
          Dir.chdir(File.join(target.source.root, dir)) do
            io.puts "  % #{target.source.name} < #{dir}" unless quiet?

            novel_install_files(files, target.ridir, options.merge(mode: 0644))
          end
        end
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
      io.puts "* {.gemspec} ->" unless quiet?

      targets.each do |target|
        if target.source.is_a?(Setup::Source::Gem)
          io.puts "  %#{target.source.name}" unless quiet?

          novel_install_files([target.source.gemspec_path],
                              target.specdir,
                              options.merge(mode: 0644,
                                            as: "#{target.source.fullname}.gemspec"))
        end
      end
    end

    # Install specification.
    #
    def install_gemfile
      io.puts "* {gemfile} ->" unless quiet?

      targets.each do |target|
        if (target.source.is_a?(Setup::Source::Gemfile) or
            target.source.is_a?(Setup::Source::Gem) and
            target.source.gemfile_path)
          io.puts "  %#{target.source.name}" unless quiet?

          novel_install_files([target.source.gemfile_path],
                              target.datadir,
                              options.merge(mode: 0644, as: "Gemfile"))
        end
      end
    end

    #
    def distclean
      %w(SetupConfig .gemspecs).each { |f| FileUtils.rm_rf(f) }
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
        raise Error, "ruby extention not compiled: 'setup.rb make' first"
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

    # Novel proc to install project files.
    def novel_install_files(source_files_in, dest_dir, options = {})
      source_files = [ source_files_in ].flatten
      chroot = options[:chroot]

      source_files.each do |file|
        name = File.basename(options[:as] || file)
        dir = File.dirname(options[:as] || options[:dir] || file)

        if options[:symlink]
           #require 'pry'; binding.pry
           dest_file_in = File.expand_path(File.join(dest_dir, name))
        else
           dest_file_in = File.expand_path(File.join(dest_dir, dir, name))
        end
        dest_file = File.join(chroot, dest_file_in)

        FileUtils.mkdir_p(File.dirname(dest_file))
        if options[:symlink]
          if !File.exist?(dest_file)
            if File.absolute_path?(file)
              io.puts "    [#{chroot}]#{file} -> [#{chroot}]#{dest_file_in}"
              FileUtils.ln_sr(File.join(chroot, file), dest_file, force: true)
              FileUtils.mkdir_p(File.join(chroot, file)) unless File.exist?(File.join(chroot, file))
            else
              io.puts "    #{file} -> [#{chroot}]#{dest_file_in}"
              FileUtils.ln_sr(file, dest_file, force: true)
              FileUtils.mkdir_p(file) unless File.exist?(file)
            end
          end
        elsif options[:shebang]
          io.puts "    #{file} -> [#{chroot}]#{dest_file_in}"
          install_reshebanged(file, dest_file, shebang: options[:shebang], mode: options[:mode])
        else
          io.puts "    #{file} => [#{chroot}]#{dest_file_in}"
          FileUtils.install(file, dest_file, mode: options[:mode])
        end
      end
    end

    def install_reshebanged file, dest_file, shebang: raise, mode: nil
       content = IO.binread(file)
       lines_in = content.split("\n")

       if shebang && args_in = shebang_args(lines_in.first)
          lines = [ shebang_line(shebang, args_in) ] + lines_in[1..-1]
          File.open(dest_file, "wb") { |f| f.write(lines.join("\n")) }
          FileUtils.chmod(mode, dest_file)
       else
          FileUtils.install(file, dest_file, mode: options[:mode])
       end
    end

      def shebang_line shebang, args_in = []
         "#!" + (case shebang
            when 'auto', 'ruby'
               [ path_to('ruby') ]
            when 'env'
               [ path_to('env'), '-S', 'ruby' ]
            else
               [ shebang ]
            end + args_in).compact.join(" ")
      end

      def path_to shebang
         case shebang
         when 'ruby'
            File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['ruby_install_name'])
         when 'env'
            File.join(RbConfig::CONFIG['bindir'], 'env')
         else
            ''
         end
      end

      def shebang_args line_in
         line = /^#!.*/.match(line_in)&.[](0) || ''

         line.split(/\s+/).reduce(nil) do |res, x|
            res && res << x || x =~ /^-/ && [ x ] || nil
         end || []
      end

    # Install project files.
    def install_files(source_files, dest_dir, options = {})
      source_files.each do |file|
        dest_file = destination(dest_dir, file, options)


#        if dest_file
          FileUtils.mkdir_p(File.dirname(dest_file))
          if options[:symlink]
            io.puts "    кккккккк2 -> #{file} : #{dest_file}"
            FileUtils.ln_sr(file, dest_file, force: true)
          else
            io.puts "'#{file}' -> '#{dest_file}'"
            FileUtils.install(file, dest_file, mode: options[:mode])
          end
#        else
#          $stderr.puts "Invalid destination '#{dest_dir}' for file '#{file}' and options #{options.inspect}"
#        end
      end
    end

    def options
       {
          chroot: Dir.chdir(project.rootdir) { File.expand_path(config.install_prefix) },
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
            io.puts "    кккккккк3 -> #{dest} : #{dfile}"
        FileUtils.ln_sr(dest, dfile)
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

      File.expand_path(File.join(dest, options[:as] || matched && matched[:dest_file] || ''))
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

