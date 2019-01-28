require 'setup/base'

module Setup

  #
  class Compiler < Base

    #
    #
    def configure
      extdirs.each do |dir|
        Dir.chdir(dir) do
          if !FileUtils.uptodate?('Makefile', ['extconf.rb'])
            puts "[#{dir}]$ ruby extconf.rb -- --use-system-libraries --enable-debug-build"
            ruby("extconf.rb", '--', '--use-system-libraries', '--enable-debug-build')
          end
        end
      end
    end

    #
    def compile
      extdirs.each do |dir|
        Dir.chdir(dir) do
          puts "[#{dir}]$ make #{config.makeprog}"
          make
          FileUtils.touch('gem.build_complete')
        end
      end
    end

    #
    def clean
      extdirs.each do |dir|
        Dir.chdir(dir) do
          make('clean')
        end
      end
    end

    #
    def distclean
      extdirs.each do |dir|
        Dir.chdir(dir) do
          make('distclean')
        end
      end
    end

    #
    #
    def extdirs
       extfiles.map { |extfile| File.dirname(extfile) }
    end

    #
    #
    def extfiles
       project.sources.map { |source| source.extfiles }.flatten
    end

    #
    #
    def make task = nil
       if File.exist?('Makefile')
          bash(*[config.makeprog, task].compact)
       end
    end

  end

end

