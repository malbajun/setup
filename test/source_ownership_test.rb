require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'setup/session'

class SourceOwnershipTest < Minitest::Test
   def test_root_installs_its_own_files_without_copying_nested_google_api_gem
      Dir.mktmpdir('setup-source-ownership-') do |directory|
         fixture = File.join(__dir__, 'fixtures/google-api-ruby-client-20251103')
         root = File.join(directory, File.basename(fixture))
         FileUtils.cp_r(fixture, root)
         sibling = File.join(root, 'google-apis-core-extra')
         FileUtils.mkdir_p(sibling)
         File.write(File.join(sibling, 'keep.txt'), 'unclaimed application data')
         stage = File.join(directory, 'stage')
         config = Setup::Configuration.new(reset: true, install_prefix: stage)
         project = Setup::Project.new(config, rootdir: root)
         targets = project.targets
         root_target = targets.find { |target| target.source.name == 'google-api-ruby-client' }
         gem_target = targets.find { |target| target.source.name == 'google-apis-core' }
         refute_nil root_target
         refute_nil gem_target
         installer = Setup::Installer.new(project, config, quiet: true, io: StringIO.new)
         Dir.chdir(root) do
            installer.send(:_install, :lib)
            installer.install_data
            installer.install_gemfile
         end
         private_root = File.join(stage, root_target.datadir)
         assert File.file?(File.join(private_root, 'Gemfile'))
         assert File.file?(File.join(private_root, 'google-apis-core-extra/keep.txt'))
         refute File.exist?(File.join(private_root, 'google-apis-core')),
            'the installer must not create a second copy of the nested gem'
         assert File.file?(File.join(stage, gem_target.libdir, 'lib/google/apis/core/version.rb'))
      end
   end
   def test_disabled_nested_sources_are_not_copied_into_root_application_data
      Dir.mktmpdir('setup-disabled-ownership-') do |directory|
         root = File.join(directory, 'google-api-ruby-client-20251103')
         FileUtils.cp_r(File.join(__dir__, 'fixtures/google-api-ruby-client-20251103'), root)
         File.open(File.join(root, 'Gemfile'), 'a') { |file| file.puts('gem "google-apis-core", ">= 1.4.1"') }
         sibling = File.join(root, 'google-apis-core-extra')
         FileUtils.mkdir_p(sibling)
         File.write(File.join(sibling, 'keep.txt'), 'unclaimed application data')
         stage = File.join(directory, 'stage')
         config = Setup::Configuration.new(reset: true, install_prefix: stage)
         config.ignore_names = ['google-apis-core']
         project = Setup::Project.new(config, rootdir: root)
         root_target = project.targets.find { |target| target.source.name == 'google-api-ruby-client' }
         refute_nil root_target
         refute project.valid_sources.any? { |source| source.name == 'google-apis-core' }
         installer = Setup::Installer.new(project, config, quiet: true, io: StringIO.new)
         Dir.chdir(root) { installer.install_data }
         private_root = File.join(stage, root_target.datadir)
         assert File.file?(File.join(private_root, 'Gemfile'))
         assert File.file?(File.join(private_root, 'google-apis-core-extra/keep.txt'))
         refute File.exist?(File.join(private_root, 'google-apis-core')),
            'a disabled source must not reappear in the root application data'
      end
   end

end
