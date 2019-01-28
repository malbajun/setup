require 'bundler'

require 'setup/gem'

module Setup

  # DSL service for Setup.rb.

  class DSL
    # class TooManyGemspecsError < StandardError; end

    DEFAULT_GROUP_NAME = :development

    #
    attr_reader :gem

    #
    def initialize(gemroot: Dir.pwd, gem: nil)
      @gem = gem || Gem.new(gemroot: gemroot)
      @gemroot = gemroot
    end

    def gemroot
      gem.valid? && gem.gemroot || @gemroot
    end

    def dsl
      @dsl ||= (

        begin
          dsl = Bundler::Dsl.new
          dsl.eval_gemfile(File.join(gemroot, 'Gemfile'))
          dsl
        rescue Bundler::GemNotFound, Bundler::VersionConflict, ::Gem::InvalidSpecificationException => e
          nil
        end)
    end

    def lockfile
      @lockfile ||= (
        gemroot && File.join(gemroot, 'Gemfile.lock') || Tempfile.new('Gemfile.lock').path)
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

    def all_deps
      if gem.valid?
        gem.spec.dependencies
      else
        local_deps_for :all
      end
    end

  end

end
