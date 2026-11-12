require 'minitest/autorun'
require 'setup'
require 'setup/configuration'
require 'setup/project'

class NameFiltersTest < Minitest::Test
   def configuration
      Setup::Configuration.new(reset: true)
   end

   def test_generated_patterns_keep_flags_delimiters_and_anchors
      patterns = [/\Agoogle-apis-.+\z/, /\Agoogle-apis-(?:core|generator|discovery_v1)\z/i,
         /\A[a-z,;:]{1,3}(?:x:y)?\z/]
      config = configuration
      config.ignore_names = patterns.map(&:to_s).join(',')
      config.regard_names = patterns.map(&:to_s).join(',')
      samples = ['google-apis-core', 'GOOGLE-APIS-CORE', 'google-apis-storage',
         'prefix-google-apis-core', 'a,b', 'abcx:y', 'abcd', 'abcx:y:suffix']
      samples.each do |name|
         expected = patterns.map { |pattern| pattern.match?(name) }
         assert_equal expected, config.ignore_names.map { |pattern| pattern === name }
         assert_equal expected, config.regard_names.map { |pattern| pattern === name }
      end
      assert config.ignore_names.first.match?('google-apis-core')
      assert config.regard_names[1].match?('GOOGLE-APIS-CORE')
      refute config.regard_names[1].match?('google-apis-storage')
   end

   def test_legacy_names_separators_slash_patterns_and_array_input
      config = configuration
      config.ignore_names = 'first, second;third:foo/bar'
      assert_equal %w(first second third), config.ignore_names.first(3)
      assert config.ignore_names.last.match?('foo-any-bar')
      refute config.ignore_names.last.match?('prefix-foo-any-bar')
      filters = ['literal', /regexp/]
      config.regard_names = filters
      assert_same filters, config.regard_names
      config.ignore_names = nil
      assert_empty config.ignore_names
   end

   def test_regard_exception_controls_actual_source_selection
      config = configuration
      config.ignore_names = /google-apis-.*/.to_s
      config.regard_names = /\Agoogle-apis-(?:core|generator|discovery_v1)\z/.to_s
      project = Setup::Project.new(config)
      source = Struct.new(:name, :platform, :version, :source_file)
      refute project.is_disabled?(source.new('google-apis-core', Gem::Platform::RUBY, '1.4.1', '/project/core.gemspec'))
      assert project.is_disabled?(source.new('google-apis-storage_v1', Gem::Platform::RUBY, '1.0', '/project/storage.gemspec'))
   end
end
