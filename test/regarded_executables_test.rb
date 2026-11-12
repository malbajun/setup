require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'setup'
require 'setup/installer'
require 'setup/configuration'

class RegardedExecutablesTest < Minitest::Test
   def test_regarded_gem_keeps_its_executable_link_and_relocates
      Dir.mktmpdir('setup-regarded-executable-') do |directory|
         root = File.join(directory, 'google-apis-generator')
         FileUtils.mkdir_p(File.join(root, 'bin'))
         File.write(File.join(root, 'bin/generate-api'), "#!/usr/bin/env ruby\nputs 'generate'\n")
         spec = Gem::Specification.new do |gem|
            gem.name = 'google-apis-generator'
            gem.version = '0.19.3'
            gem.summary = 'Regarded executable regression'
            gem.executables = ['generate-api']
            gem.files = ['bin/generate-api']
         end
         File.write(File.join(root, 'google-apis-generator.gemspec'), '')
         source = Setup::Source::Gem.new(source_file: File.join(root, 'google-apis-generator.gemspec'), spec: spec)
         prefix = File.join(directory, 'stage')
         config = Setup::Configuration.new(reset: true)
         config.install_prefix = prefix
         config.shebang = 'env'
         config.ignore_names = /google-apis-.*/.to_s
         config.regard_names = /\Agoogle-apis-generator\z/.to_s
         target = Setup::Target::Gem.new(source: source, home: '/usr/lib/ruby/gemie',
            options: {chroot: prefix, 'bindir' => '/usr/bin'})
         project = Struct.new(:rootdir, :targets, :valid_sources).new(root, [target], [source])
         output = StringIO.new
         Setup::Installer.new(project, config, quiet: true, io: output).install_exe
         link = File.join(prefix, 'usr/bin/generate-api')
         assert File.symlink?(link), "the explicitly regarded gem must keep its public executable: #{output.string}"
         refute File.readlink(link).start_with?('/')
         assert_includes File.read(File.realpath(link)), "puts 'generate'"
         relocated = File.join(directory, 'relocated')
         FileUtils.mv(prefix, relocated)
         assert File.file?(File.realpath(File.join(relocated, 'usr/bin/generate-api')))
      end
   end
end
