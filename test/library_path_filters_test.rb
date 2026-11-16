require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'open3'
require 'setup'
require 'setup/configuration'
require 'setup/installer'

class LibraryPathFiltersTest < Minitest::Test
   def test_selected_library_keeps_a_namespace_named_doc_with_documentation_disabled
      Dir.mktmpdir('setup-library-path-') do |directory|
         root = File.join(directory, 'source')
         files = {
            'lib/namespace_probe.rb' => "require 'namespace_probe/doc/handler'\n",
            'lib/namespace_probe/doc/handler.rb' => "NAMESPACE_DOC_HANDLER = true\n"
         }
         files.each do |name, body|
            path = File.join(root, name)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, body)
         end
         spec = Gem::Specification.new do |gem|
            gem.name = 'namespace-probe'
            gem.version = '1.0'
            gem.summary = 'Packaged library namespace'
            gem.files = files.keys
         end
         path = File.join(root, 'namespace-probe.gemspec')
         File.write(path, spec.to_ruby)
         source = Setup::Source::Gem.new(source_file: path, spec: spec)
         prefix = File.join(directory, 'stage')
         config = Setup::Configuration.new(reset: true)
         config.with_parts = ''
         config.install_prefix = prefix
         config.ignore_path_tokens = ['doc']
         target = Setup::Target::Gem.new(source: source, home: '/usr/lib/ruby/gemie', options: {chroot: prefix})
         project = Struct.new(:rootdir, :targets, :valid_sources).new(root, [target], [source])
         output = StringIO.new
         Setup::Installer.new(project, config, quiet: true, io: output)._install(:lib)
         library = File.join(prefix, target.libdir, 'lib')
         assert File.file?(File.join(library, 'namespace_probe/doc/handler.rb')), output.string
         text, status = Open3.capture2e(RbConfig.ruby, '-I', library, '-rnamespace_probe', '-e', 'abort unless NAMESPACE_DOC_HANDLER')
         assert status.success?, text
      end
   end
end
