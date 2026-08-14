require 'setup/base'
require 'setup/rake_app'
require 'setup/log'

module Setup
   class Compiler < Base
      include Setup::Log

      ARGS = %w(--use-system-libraries --enable-system-libraries --enable-debug-build --disable-static --enable-force-compile --srcdir=.)

      class Extconf
         attr_reader :config, :original_config, :makeconfig, :original_makeconfig, :argv, :extdir, :source

         def initialize extpath, source, *args
            @extfile = extpath
            @extdir = File.dirname(extpath)
            @argv = args
            @original_config = RbConfig::CONFIG.dup
            @original_makeconfig = RbConfig::MAKEFILE_CONFIG.dup
            @source = source

            Dir.chdir(@extdir) do
               RbConfig::MAKEFILE_CONFIG["configure_args"] = args.join(" ")
               require 'mkmf'
               RbConfig::CONFIG["srcdir"] = RbConfig::MAKEFILE_CONFIG["srcdir"] = '.'

               config = RbConfig::MAKEFILE_CONFIG.dup.merge({"CFLAGS" => RbConfig::MAKEFILE_CONFIG["CFLAGS"] + " -fpermissive " +
                  "-Wdeclaration-missing-parameter-type -Wimplicit-function-declaration -Wimplicit-int " +
                  "-Wincompatible-pointer-types -Wint-conversion -Wreturn-mismatch"})

               init_mkmf(config, RbConfig::CONFIG)
            end
         end

         def configure
            Dir.chdir(@extdir) do
               load(File.join('.', File.basename(@extfile)))
            end

            @config = RbConfig::CONFIG.dup
            @makeconfig = RbConfig::MAKEFILE_CONFIG.dup
         rescue Exception => e
            unless e.is_a?(SystemExit) && e.status == 0
               $stderr.puts("[#{e.class}]> #{e.message}\t\n#{e.backtrace.join("\t\n")}")

               raise(e)
            end
         ensure
            RbConfig::CONFIG.replace(@original_config)
            RbConfig::MAKEFILE_CONFIG.replace(@original_makeconfig)
         end
     end

    #
    #
    def configure
      @configurations =
        project.valid_sources.map do |source|
          source.exttree.map do |dir_in, extfiles|
            extfiles.map do |extfile|
              extpath = File.join(source.root, dir_in, extfile)

              if extpath =~ /rakefile(.rb)?$/i
                 Setup::Rake.new(extpath, {source: source})
              elsif extpath !~ /gem.build_complete/i
                 cfg = Extconf.new(extpath, source, *ARGS)
                 cfg.configure
                 cfg
              end
            end
          end
        end.flatten
    end

    def sos source
      @sos ||=
        Dir.glob(File.join(source.root, "{.*,**}", "{.*,**}", "*.so")).reject do |so|
          config.match_ignore?(so)
        end
    end

    def make
      chrpath_path = `which chrpath`.strip

      @configurations.each do |cfg|
        case cfg
        when Setup::Rake
          cfg.run_task('default')

          sos = sos(cfg.options[:source])
          if sos.any?
              # NOTE gem hotwater
              dd = File.join(source.root, ".so.#{source.name}", RbConfig::CONFIG['sitearchdir'])
              FileUtils.mkdir_p(dd)

              sos.each do |file|
                Kernel.puts("so[rake]: #{dd}")
                bash(chrpath_path, '-d', file) if !chrpath_path.empty?

                FileUtils.cp(file, dd)
              end
            end
        when Extconf
          headers = Dir.glob("*/**/*.{h,hpp}")

          Dir.chdir(cfg.extdir) do
            debug "[#{cfg.extdir}]$ make #{config.makeprog}"
            make_task

            # post make
            sos = sos(cfg.source)
            if sos.any?
              sos.each do |file|
                Kernel.puts("so[ext]: #{file}")
                # remove RPATH if any
                bash(chrpath_path, '-d', file) if !chrpath_path.empty?
              end
              FileUtils.mkdir_p(File.join(cfg.source.root, ".so.#{cfg.source.name}", RbConfig::CONFIG['sitearchdir'], target_prefix))
              make_task('install', DESTDIR: File.join(cfg.source.root, ".so.#{cfg.source.name}"))
            end
          end
        end
      end
    end

    #
    def clean
      project.valid_sources.each do |source|
        source.exttree.each do |dir_in, extfiles|
          extfiles.each do |extfile|
            Dir.chdir(File.join(source.root, dir_in, File.dirname(extfile))) do
              make_task('clean')
            end
          end
        end
      end
    end

    #
    def distclean
      project.valid_sources.each do |source|
        source.exttree.each do |dir_in, extfiles|
          extfiles.each do |extfile|
            Dir.chdir(File.join(source.root, dir_in, File.dirname(extfile))) do
              Dir.glob('**/gem.build_complete').each { |file| FileUtils.rm_f(file) }
              make_task('distclean')
            end

            FileUtils.rm_rf(File.join(source.root, ".so.#{source.name}"))
          end
        end
      end
    end

    protected
    #
    #
    def make_task task = nil, env = {}
       if File.exist?('Makefile')
          args = [env, config.makeprog, task].compact
          bash(*args)
       end
    end

    def target_prefix
      target_list =
        IO.read("Makefile").split("\n").select do |l|
          l =~ /target_prefix *=/
        end.first

      target_list ? target_list.split('=')[1..-1].join('=').strip : './'
    end

  end

end

