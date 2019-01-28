require 'setup/base'
require 'rdoc'

module Setup

  # As of v0.5.1 Setup.rb no longer support the document phase at all. The
  # document phase would generate *ri* documentation for a project, adding in
  # with the rest of ri documentation. After careful consideration, it has
  # become clear that it is better for documentation to be left up to dedicated
  # tools. For example, you could easily document your Ruby install site
  # location yourself with
  #
  #   $ rdoc --ri-site /usr/local/lib/site_ruby
  #
  # Using of course, whichever path is appropriate to your system.
  #
  # This descision also allows setup.rb to be less Ruby-specific, and useful
  # as a more general install tool.
  #
  # @deprecated Setup.rb no longer generates ri documentation, ever.
  #
  class Documentor < Base
    #
    def document
      return if config.no_doc

      exec_ri
      exec_yri
    end

    # Generate ri documentation.
    #
    # @todo Should we run rdoc programmatically instead of shelling out?
    #
    def exec_ri

      project.sources.reject { |s| s.doc_sourcefiles.empty? }.each do |source|
        options = if source.is_a?(Setup::Source::Gem)
          ["--ri"]
        else
          ["--ri-site"]
        end | ['-q', '-o', source.ridir]

        Dir.chdir(source.root) do
          source.doc_sourcefiles.each do |dir|
            if !documentate(options, dir)
              documentate_files options, dir
            end
          end
        end
      end
    end

    def documentate_files options, dir
      Dir.glob("#{dir}/**/*.{rb,h,c}").each do |file|
        next if !File.file?(file)

        documentate(options, file)
      end
    end

    def documentate opts, file
      begin
        ::RDoc::RDoc.new.document(opts.dup << file)

        true
      rescue StandardError => e
        $stderr.puts "ri generation to documentate '#{file}' is failed" unless quiet?
        $stderr.puts "#{e.class}: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
      end
    end

    #
    #
    def dirs
       project.sources.map { |source| source.root }.flatten
    end

    #
    # Generate YARD Ruby Index documention.
    #
    def exec_yri

    end

    # Generate rdocs. Needs project <tt>name</tt>.
    #
    # @deprecated This is not being used. It's here in case we decide
    #   to add the feature back in the future.
    #
    def exec_rdoc
      main = Dir.glob("README{,.*}", File::FNM_CASEFOLD).first

      if File.exist?('.document')
        files = File.read('.document').split("\n")
        files.reject!{ |l| l =~ /^\s*[#]/ || l !~ /\S/ }
        files.collect!{ |f| f.strip }
      else
        files = []
        files << main  if main
        files << 'config' if project.find('config')
        files << 'app' if project.find('app')
        files << 'lib' if File.directory?('lib')
        files << 'ext' if File.directory?('ext')
      end

      checkfiles = (files + files.map{ |f| Dir[File.join(f,'*','**')] }).flatten.uniq
      if FileUtils.uptodate?('doc/rdoc', checkfiles)
        puts "RDocs look current."
        return
      end

      output    = 'doc/rdoc'
      title     = (PACKAGE.capitalize + " API").strip if PACKAGE
      template  = config.doctemplate || 'html'

      opt = []
      opt << "-U"
      opt << "-q" if quiet?
      opt << "--op=#{output}"
      #opt << "--template=#{template}"
      opt << "--title=#{title}"
      opt << "--main=#{main}"     if main
      #opt << "--debug"
      opt << files

      opt = opt.flatten

      cmd = "rdoc " + opt.join(' ')

      if trial?
        puts cmd 
      else
        begin
          ::RDoc::RDoc.new.document(opt)
          io.puts "Ok rdoc." unless quiet?
        rescue Exception
          puts "Fail rdoc."
          puts "Command was: '#{cmd}'"
          puts "Proceeding with install anyway."
        end
      end
    end

  end

end
