require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'setup'
require 'setup/configuration'
require 'setup/installer'
require 'setup/documentor'
require 'setup/tester'
require 'setup/command'

class SourcePartsTest < Minitest::Test
   def with_project(disabled)
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
         config = Setup::Configuration.new(reset: true)
         config.with_parts = (Setup::Configuration::OPTIONAL_PARTS - disabled.split(',')).join(',')
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
      with_project('doc') do |installer, source, target|
         installer.install
         assert File.file?(staged(target, File.join(target.libdir, 'lib/part_probe.rb')))
         assert File.file?(staged(target, File.join(target.specdir, 'part-probe-1.0.gemspec')))
         assert File.symlink?(staged(target, '/usr/bin/part-probe'))
         refute File.exist?(staged(target, File.join(target.ridir, 'PartProbe.ri')))
         assert_equal [source], installer.targets.map(&:source)
      end
   end

   def test_optional_part_switches_keep_library_and_omit_private_and_public_copies
      with_project('doc,devel,exec') do |installer, _source, target|
         installer.install
         assert File.file?(staged(target, File.join(target.libdir, 'lib/part_probe.rb')))
         refute File.exist?(staged(target, target.exedir))
         refute File.symlink?(staged(target, '/usr/bin/part-probe'))
         refute File.exist?(staged(target, target.ridir))
         refute File.exist?(staged(target, target.incdir))
      end
   end

   def test_documentor_skips_excluded_source
      with_project('doc') do |_installer, _source, _target, config, project|
         documentor = Setup::Documentor.new(project, config, quiet: true)
         documentor.define_singleton_method(:documentate) { |_files| flunk 'excluded documentation was compiled' }
         documentor.exec_ri
      end
   end

   def test_explicit_part_selection_and_no_doc_remain_effective
      with_project('doc') do |_installer, source, _target, config|
         refute config.no_doc
         refute config.source_part_enabled?(source, :doc)
         config.with_parts = 'doc,devel,exec,check'
         assert config.source_part_enabled?(source, :doc)
         config.no_doc = true
         refute config.source_part_enabled?(source, :doc)
      end
   end

   def test_disabled_check_skips_existing_setup_test_script
      with_project('check') do |_installer, _source, _target, config, project|
         FileUtils.mkdir_p(File.join(project.rootdir, '.setup'))
         File.write(File.join(project.rootdir, '.setup/test.rb'), "raise 'must not run'\n")
         config.no_test = false
         tester = Setup::Tester.new(project, config, quiet: true)
         Dir.chdir(project.rootdir) do
            refute tester.testable?
            assert tester.test
            config.with_parts = 'doc,devel,exec,check'
            assert tester.testable?
         end
      end
   end

   def test_cli_part_list_persists_and_an_explicit_value_replaces_it
      with_project('') do |_installer, source, _target, config, project|
         command = Setup::Command.new
         command.instance_variable_set(:@configuration, config)
         parser = OptionParser.new
         command.optparse_config(parser, {})
         parser.parse!(['--with-parts=exec,check'])
         refute config.source_part_enabled?(source, :doc)
         assert config.source_part_enabled?(source, :exec)
         Dir.chdir(project.rootdir) do
            project.define_singleton_method(:to_h) { {} }
            config.save_config_with(project)
            restored = Setup::Configuration.new
            assert_equal ['exec', 'check'], restored.with_parts
            assert restored.source_part_enabled?(source, :lib)
            assert restored.source_part_enabled?(source, :app)
            restored.with_parts = ''
            refute restored.source_part_enabled?(source, :exec)
            restored.with_parts = nil
            assert restored.source_part_enabled?(source, :doc)
         end
      end
   end

   def test_invalid_optional_parts_are_rejected
      config = Setup::Configuration.new(reset: true)
      assert_raises(Setup::Error) { config.with_parts = 'binary' }
   end

   def test_generated_plugins_use_each_installers_own_staging_root
      with_project('doc') do |first, _source, first_target, first_config|
         first.install
         first_plugin = File.join(first_config.install_prefix, first_target.plugindir, 'part-probe_plugin.rb')
         assert File.file?(first_plugin)
         with_project('doc') do |second, _other_source, second_target, second_config|
            second.install
            second_plugin = File.join(second_config.install_prefix, second_target.plugindir, 'part-probe_plugin.rb')
            assert File.file?(second_plugin), 'a second installer must use its own staging root'
            assert File.file?(first_plugin)
         end
      end
   end

end
