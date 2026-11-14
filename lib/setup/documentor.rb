require 'setup/base'
require 'rdoc'
require 'rdoc/markdown'
require 'rdoc/markdown/literals'

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
    # Generates RI documentation from the selected source file lists.
    # Takes no parameters.
    # @return [Array<Setup::Source::Base>] sources with documentation inputs
    # Gem sources use a gem RI store; other sources use the site RI store.
    # Empty sources are skipped. Each source is documented in one invocation,
    # retaining cross-file references without recursively scanning its directories.
    def exec_ri
      project.valid_sources.reject { |s| s.docsrcfiles.empty? }.each do |source|
        next unless config.source_part_enabled?(source, :doc)
        options = if source.is_a?(Setup::Source::Gem)
          ["--ri"]
        else
          ["--ri-site"]
        end + ['-q', '--force-update', '-o', source.default_ridir]
        @options = RDoc::Options.load_options
        @options.parse(options)

        Dir.chdir(source.root) do
          files = source.docsrctree.flat_map do |dir, entries|
            entries.map { |file| File.join(dir, file) }
          end
          documentate(files)
        end
      end
    end

    # Compiles an explicit list of RI source files with the prepared options.
    # @param files [Array<String>, String] selected files relative to the source root
    # @return [true, nil] true on success, or nil after reporting a compilation error
    # Errors retain the existing diagnostic behavior; quiet mode omits the heading.
    def documentate files
      begin
        rdoc = ::RDoc::RDoc.new
        @options.files = Array(files)
        rdoc.document(@options)

        true
      rescue Exception => e
        $stderr.puts "ri generation to documentate '#{files}' is failed" unless quiet?
        $stderr.puts "#{e.class}: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
      end
    end

    #
    #
    def dirs
       project.valid_sources.map { |source| source.root }.flatten
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


    def distclean
      project.valid_sources.each do |source|
        FileUtils.rm_rf(source.default_ridir)
      end
    end

    alias_method :clean, :distclean

  end
end
