require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'setup'
require 'setup/documentor'
require 'setup/configuration'

class DocumentationFilesTest < Minitest::Test
   def test_only_declared_libraries_and_explicit_root_guides_are_documented
      Dir.mktmpdir('setup-doc-inputs-') do |directory|
         files = {
            'doc-probe.gemspec' => '',
            'lib/included.rb' => 'class IncludedDocProbe; end',
            'lib/development_only.rb' => 'class ExcludedDocProbe; end',
            'guide.rb' => 'class ExplicitGuideProbe; end'
         }
         files.each do |name, text|
            path = File.join(directory, name)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, text + "\n")
         end
         specification = Gem::Specification.new do |gem|
            gem.name = 'doc-probe'
            gem.version = '1.0'
            gem.summary = 'Documentation input regression'
            gem.files = ['lib/included.rb']
            gem.require_paths = ['lib']
            gem.extra_rdoc_files = ['guide.rb']
         end
         source = Setup::Source::Gem.new(source_file: File.join(directory, 'doc-probe.gemspec'), spec: specification)
         output = File.join(directory, 'ri-output')
         source.define_singleton_method(:default_ridir) { output }
         project = Struct.new(:valid_sources).new([source])
         documentor = Setup::Documentor.new(project, Setup::Configuration.new(reset: true), quiet: true)
         caller_directory = Dir.pwd
         documentor.exec_ri
         assert_equal caller_directory, Dir.pwd
         assert File.file?(File.join(output, 'IncludedDocProbe', 'cdesc-IncludedDocProbe.ri'))
         assert File.file?(File.join(output, 'ExplicitGuideProbe', 'cdesc-ExplicitGuideProbe.ri'))
         refute File.exist?(File.join(output, 'ExcludedDocProbe'))
      end
   end
end
