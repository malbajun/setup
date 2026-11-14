require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'setup'
require 'setup/configuration'
require 'setup/installer'
require 'setup/documentor'

class SourcePartsTest < Minitest::Test
   def with_project(ignored, regarded = '')
      Dir.mktmpdir('setup-source-parts-') do |directory|
         root = File.join(directory, 'source')
         files = {
            'lib/part_probe.rb' => 'class PartProbe; end',
            'lib/rubygems_plugin.rb' => '# plugin',
            'bin/part-probe' => "#!/usr/bin/env ruby\nputs 'probe'",
            'README.md' => '# Probe',
            'ext/probe/probe.h' => '/* header */',
            'test/probe_test.rb' => '# tests',
            'Gemfile' => 'source "https://rubygems.org"',
            'ri/PartProbe.ri' => 'generated RI'
         }
         files.each do |name, text|
            path = File.join(root, name)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, text + "\n")
         end
         spec = Gem::Specification.new do |gem|
            gem.name = 'part-probe'
            gem.version = '1.0'
            gem.summary = 'Source part selection'
            gem.files = files.keys
            gem.executables = ['part-probe']
         end
         path = File.join(root, 'part-probe.gemspec')
         File.write(path, spec.to_ruby)
         source = Setup::Source::Gem.new(source_file: path, spec: spec)
         prefix = File.join(directory, 'stage')
         config = Setup::Configuration.new(reset: true, ignore_source_parts: ignored, regard_source_parts: regarded)
         config.install_prefix = prefix
         config.shebang = 'env'
         target = Setup::Target::Gem.new(source: source, home: '/usr/lib/ruby/gemie',
            options: {chroot: prefix, 'bindir' => '/usr/bin'})
         project = Struct.new(:rootdir, :targets, :valid_sources).new(root, [target], [source])
         yield Setup::Installer.new(project, config, quiet: true, io: StringIO.new), source, target, config, project
      end
   end

   def staged(target, path)
      File.join(target.chroot, path)
   end

   def test_doc_exclusion_keeps_library_spec_and_executable
      with_project('part-probe:doc') do |installer, source, target|
         installer.install
         assert File.file?(staged(target, File.join(target.libdir, 'lib/part_probe.rb')))
         assert File.file?(staged(target, File.join(target.specdir, 'part-probe-1.0.gemspec')))
         assert File.symlink?(staged(target, '/usr/bin/part-probe'))
         refute File.exist?(staged(target, File.join(target.ridir, 'PartProbe.ri')))
         assert_equal [source], installer.targets.map(&:source)
      end
   end

   def test_omitted_library_keeps_private_and_public_executables_and_headers
      with_project('part-probe:lib+doc') do |installer, _source, target|
         installer.install
         refute File.exist?(staged(target, File.join(target.libdir, 'lib')))
         refute File.exist?(staged(target, File.join(target.libdir, 'README.md')))
         refute File.exist?(staged(target, File.join(target.libdir, 'test')))
         refute File.exist?(staged(target, File.join(target.libdir, 'Gemfile')))
         refute File.exist?(staged(target, File.join(target.specdir, 'part-probe-1.0.gemspec')))
         refute File.exist?(staged(target, File.join(target.plugindir, 'part-probe_plugin.rb')))
         assert File.file?(File.realpath(staged(target, '/usr/bin/part-probe')))
         assert File.file?(staged(target, File.join(target.incdir, 'probe/probe.h')))
         assert File.symlink?(staged(target, File.join(target.datadir, 'ext')))
      end
   end

   def test_regard_overrides_wildcard_and_exec_exclusion_omits_both_copies
      with_project('*:all', 'part-probe:lib') do |installer, _source, target|
         installer.install
         assert File.file?(staged(target, File.join(target.libdir, 'lib/part_probe.rb')))
         refute File.exist?(staged(target, target.exedir))
         refute File.symlink?(staged(target, '/usr/bin/part-probe'))
         refute File.exist?(staged(target, target.ridir))
         refute File.exist?(staged(target, target.incdir))
      end
   end

   def test_documentor_skips_excluded_source
      with_project('*:doc') do |_installer, _source, _target, config, project|
         documentor = Setup::Documentor.new(project, config, quiet: true)
         documentor.define_singleton_method(:documentate) { |_files| flunk 'excluded documentation was compiled' }
         documentor.exec_ri
      end
   end

   def test_rpm_environment_overrides_saved_policy_and_explicit_values_override_environment
      Dir.mktmpdir('setup-parts-config-') do |root|
         Dir.chdir(root) do
            File.write('SetupConfig', {'ignore_source_parts' => {'part-probe' => ['doc']}}.to_yaml)
            key = 'RPM_RUBY_IGNORE_SOURCE_PART_LIST'
            old = ENV[key]
            begin
               ENV[key] = 'part-probe:lib'
               assert_equal({'part-probe' => ['lib']}, Setup::Configuration.new.ignore_source_parts)
               assert_equal({}, Setup::Configuration.new(ignore_source_parts: '').ignore_source_parts)
               ENV[key] = ''
               assert_equal({}, Setup::Configuration.new.ignore_source_parts)
            ensure
               old.nil? ? ENV.delete(key) : ENV[key] = old
            end
         end
      end
   end

   def test_rejects_unknown_parts_and_malformed_selectors
      %w[part-probe part-probe:wat part-probe: part-probe:* ../part-probe:doc].each do |selector|
         assert_raises(ArgumentError) { Setup::Configuration.new(reset: true, ignore_source_parts: selector) }
      end
   end
end
