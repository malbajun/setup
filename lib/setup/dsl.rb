require 'fileutils'

require 'setup/source'

module Setup

  # DSL service for Setup.rb.

  class DSL
    # class TooManyGemspecsError < StandardError; end

    DEFAULT_GROUP_NAME = :development

    #
    attr_reader :gem

    #
    def initialize(root: Dir.pwd, gem: nil)
      @gem = gem || Setup::Source.search(gemroot).first
      @root = root
    end

    def root
      gem.valid? && gem.root || @root
    end

    def gemfile
       File.join(root, 'Gemfile')
    end

    def dsl
      @dsl ||= (
        begin
          require 'bundler'

          dsl = Bundler::Dsl.new
          dsl.eval_gemfile(gemfile)
          dsl
        rescue LoadError,
               Bundler::GemNotFound,
               Bundler::GemfileNotFound,
               Bundler::VersionConflict,
               Bundler::Dsl::DSLError,
               ::Gem::InvalidSpecificationException => e
          nil
        end)
    end

    def lockfile
      @lockfile ||= (
        root && File.join(root, 'Gemfile.lock') || Tempfile.new('Gemfile.lock').path)
    end

    def definition
      dsl&.to_definition(lockfile, true)
    end

    def local_deps_for *groups_in
      groups = [ *groups_in ].flatten.map { |g| g.to_sym == DEFAULT_GROUP_NAME && [ g, :default ] || g }.flatten

      if groups.include?(:all)
        definition.dependencies
      else
        definition.dependencies.select do |dep|
          (groups.empty? && dep.groups || (dep.groups & groups)).any?
        end
      end.select { |dep| dep.should_include? && !dep.autorequire&.all? }
    end

    def deps
      if gem.valid?
        gem.spec.dependencies.select { |dep| dep.type == :runtime }
      else
        local_deps_for(definition.groups - %i(development test))
      end
    end

    def deps_but replace_list
      deps.map do |dep|
        new_req = replace_list.reduce(nil) do |s, (name, req)|
          s || name == dep.name && req
        end

        new_req && Gem::Dependency.new(dep.name, Gem::Requirement.new([new_req]), :runtime) || dep
      end
    end

    def all_deps
      if gem.valid?
        gem.spec.dependencies
      else
        local_deps_for :all
      end
    end

    def ruby
      type = dsl&.instance_variable_get(:@ruby_version)&.engine || "ruby"
      version = gem.spec.required_ruby_version ||
                Gem::Requirement.new(dsl&.instance_variable_get(:@ruby_version)&.engine_versions) ||
                ">= 0"

      { type: type, version: version }
    end

    def rubygems
      { version: gem.spec.required_rubygems_version || ">= 0" }
    end

  end

end
