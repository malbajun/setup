require 'minitest/autorun'
require 'fileutils'
require 'open3'
require 'tmpdir'
require 'setup/base'
require 'setup/command'
require 'setup/dsl'

class DependencyRangesAndExplicitTestsTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def setup
    @project = Dir.mktmpdir('setup-rb-regression-')
    FileUtils.mkdir_p(File.join(@project, 'lib'))
    File.write(File.join(@project, 'lib/range_fixture.rb'), "module RangeFixture; end\n")
    File.write(File.join(@project, 'range_fixture.gemspec'), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = 'range_fixture'
        spec.version = '1.0.0'
        spec.summary = 'Setup regression fixture'
        spec.authors = ['Setup tests']
        spec.files = ['lib/range_fixture.rb']
      end
    RUBY
  end

  def teardown
    FileUtils.remove_entry(@project)
  end

  def configuration
    Dir.chdir(@project) { Setup::Configuration.new }
  end

  def test_repeated_dependency_preserves_both_bounds_in_dsl
    config = configuration
    config.use_gem_dependencies = 'newt >= 1.1.0, newt < 2'
    assert_equal ['>= 1.1.0', '< 2'], config.use_gem_dependencies.fetch('newt')

    session = Setup::Session.new
    session.instance_variable_set(:@configuration, config)
    replacements = session.default_project_options.fetch(:gem_version_replace)
    dsl = Setup::DSL.new(nil, replace_list: replacements)
    dependency = dsl.send(:deps_but, [Gem::Dependency.new('newt', '>= 1.1.0')]).fetch(0)
    requirement = dependency.requirement

    refute requirement.satisfied_by?(Gem::Version.new('1.0.99')), 'must not lower the minimum'
    assert requirement.satisfied_by?(Gem::Version.new('1.1.0'))
    assert requirement.satisfied_by?(Gem::Version.new('1.9.99'))
    refute requirement.satisfied_by?(Gem::Version.new('2'))
    refute requirement.satisfied_by?(Gem::Version.new('2.1'))
  end

  def test_interleaved_constraints_and_all_separators
    config = configuration
    config.use_gem_dependencies = ' newt >= 1.1.0 ; other ~> 3 : newt < 2, newt != 1.5 ; '
    assert_equal ['>= 1.1.0', '< 2', '!= 1.5'], config.use_gem_dependencies.fetch('newt')
    assert_equal '~> 3', config.use_gem_dependencies.fetch('other')
    requirement = Gem::Requirement.new(config.use_gem_dependencies.fetch('newt'))
    refute requirement.satisfied_by?(Gem::Version.new('1.5'))
    assert requirement.satisfied_by?(Gem::Version.new('1.6'))
  end

  def test_single_dependency_keeps_string_compatibility
    config = configuration
    config.use_gem_dependencies = 'newt >= 1.1.0'
    assert_equal({'newt' => '>= 1.1.0'}, config.use_gem_dependencies)
  end

  def test_hash_dependency_input_is_preserved
    config = configuration
    dependencies = {'newt' => ['>= 1.1.0', '< 2'], 'other' => '~> 3'}
    config.use_gem_dependencies = dependencies
    assert_equal dependencies, config.use_gem_dependencies
    config.use_gem_dependencies = ''
    assert_empty config.use_gem_dependencies
  end

  def test_explicit_test_runs_ruby_hook_with_default_configuration
    write_hook
    assert_hook_runs('test')
  end

  def test_explicit_test_overrides_saved_default_skip
    File.write(File.join(@project, 'SetupConfig'), "---\nno_test: true\n")
    write_hook
    assert_hook_runs('test')
  end

  def test_positive_test_option_enables_hook
    write_hook
    assert_hook_runs('test', '--test')
  end

  def test_short_test_option_enables_hook
    write_hook
    assert_hook_runs('test', '-t')
  end

  def test_explicit_no_test_skips_even_a_failing_hook
    write_hook('exit 23')
    assert_hook_skipped('test', '--no-test')
  end

  def test_last_test_option_wins_when_disabling
    write_hook
    assert_hook_skipped('test', '--test', '--no-test')
  end

  def test_last_test_option_wins_when_enabling
    write_hook
    assert_hook_runs('test', '--no-test', '--test')
  end

  def test_failing_ruby_hook_makes_command_fail_and_stops_following_actions
    write_hook('exit 23')
    output, status = run_setup('test', 'install', "--prefix=#{File.join(@project, 'stage')}")
    refute status.success?, output
    assert File.exist?(marker), output
    refute File.exist?(File.join(@project, 'SetupReceipt')), output
    refute File.exist?(File.join(@project, 'stage')), output
  end

  def test_hook_exception_makes_command_fail
    write_hook("raise 'hook regression failure'")
    output, status = run_setup('test', '--test')
    refute status.success?, output
    assert File.exist?(marker), output
    assert_includes output, 'hook regression failure'
  end

  def test_explicit_test_without_hook_succeeds
    output, status = run_setup('test')
    assert status.success?, output
  end

  def test_all_does_not_implicitly_run_hook
    write_hook('exit 23')
    assert_hook_skipped('all', "--prefix=#{File.join(@project, 'stage')}")
  end

  def test_all_with_test_option_runs_hook
    write_hook
    assert_hook_runs('all', '--test', "--prefix=#{File.join(@project, 'stage')}")
  end

  def test_all_with_test_option_propagates_failure
    write_hook('exit 23')
    output, status = run_setup('all', '--test', "--prefix=#{File.join(@project, 'stage')}")
    refute status.success?, output
    assert File.exist?(marker), output
    refute File.exist?(File.join(@project, 'stage')), output
  end

  def test_failing_shell_hook_makes_command_fail
    FileUtils.mkdir_p(File.join(@project, '.setup'))
    hook = File.join(@project, '.setup/test.sh')
    File.write(hook, "#!/bin/sh\necho ran > hook-ran\nexit 23\n")
    File.chmod(0755, hook)
    output, status = run_setup('test')
    refute status.success?, output
    assert File.exist?(marker), output
  end

  %w[config make install].each do |action|
    define_method("test_#{action}_does_not_implicitly_run_hook") do
      write_hook('exit 23')
      assert_hook_skipped(action, "--prefix=#{File.join(@project, 'stage')}")
    end

    define_method("test_#{action}_with_test_option_does_not_add_test_action") do
      write_hook('exit 23')
      assert_hook_skipped(action, '--test', "--prefix=#{File.join(@project, 'stage')}")
    end
  end

  private

  def marker
    File.join(@project, 'hook-ran')
  end

  def write_hook(result = 'exit 0')
    FileUtils.mkdir_p(File.join(@project, '.setup'))
    File.write(File.join(@project, '.setup/test.rb'), "File.write('hook-ran', 'ran')\n#{result}\n")
  end

  def run_setup(*arguments)
    environment = ENV.keys.grep(/\A(?:RUBYSETUP_|RPM_RUBY_|BUNDLE_)/).to_h { |key| [key, nil] }
    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby,
      '-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin/setup-rb'), *arguments,
      chdir: @project)
    [stdout + stderr, status]
  end

  def assert_hook_runs(*arguments)
    output, status = run_setup(*arguments)
    assert status.success?, output
    assert File.exist?(marker), output
  end

  def assert_hook_skipped(*arguments)
    output, status = run_setup(*arguments)
    assert status.success?, output
    refute File.exist?(marker), output
  end
end
