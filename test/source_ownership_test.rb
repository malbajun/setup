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
end
