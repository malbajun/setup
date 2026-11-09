#
# Ruby Extensions
#
require 'bundler'
require 'ostruct'

Encoding.default_external = Encoding::UTF_8

# Is this needed any more?
class << File #:nodoc: all

  unless File.respond_to?(:read)   # Ruby 1.6 and less

    def read(fname, options = {})
      open(fname){ |f| return f.read }
    end

  end

  # for corrupted Window's stat(2)
  def dir?(path)
    directory?((path[-1,1] == '/') ? path : path + '/')
  end

end

unless Errno.const_defined?(:ENOTEMPTY)   # Windows?

  module Errno  #:nodoc:
    class ENOTEMPTY  #:nodoc:
      # We do not raise this exception, implementation is not needed.
    end
  end

end

module Kernel
   alias :__old_system_call :`
   alias :__setup_orig_require :require
   alias :__setup_orig_gem :gem

  def ` cmd
    def lsfiles tokens
      masks = tokens.select do |t|
        t !~ /^-/
      end.map do |x|
        x =~ /\*/ && x.sub('*', '**/*') || File.directory?(x) && "#{x}/**/*" || File.file?(x) && x || '**/*'
      end
      masks << "**/*" if masks.empty?
      list = masks.map {|mask| Dir.glob(mask, File::FNM_DOTMATCH).select { |x| File.file?(x) } }.flatten
      char = tokens.include?('-z') && "\0" || "\n"
      list.join(char)
    end

    tokens = cmd.split(/\s+/)

    res = __old_system_call(cmd)

    if res.empty? && tokens.first == 'git' && tokens.include?('ls-files')
      i = tokens.index('ls-files')
      lsfiles(tokens[i + 1..-1])
    else
      res
    end
  rescue => e
    if tokens.first == 'git'
      if tokens.include?('ls-files')
       # TODO add gem TaskJuggler to test --
        i = tokens.index('--')
        if i
          lsfiles(tokens[i + 1..-1])
        else
          lsfiles(tokens[2..-1])
        end
      elsif tokens.include?('describe')
        if tokens.include?("--tags")
          ObjectSpace.each_object(Setup::Project).first.spec_version
        else
          res
        end
      else
        res
      end
    else
      raise(e)
    end
  end

   MODULES = {
      'olddoc' => 'setup/extcore/olddoc',
      'wrongdoc' => 'setup/extcore/wrongdoc',
      'bones' => 'setup/extcore/bones',
      'levitate' => 'setup/extcore/levitate',
      'echoe' => 'setup/extcore/echoe',
      'jeweler' => 'setup/extcore/jeweler',
      'hoe' => 'setup/extcore/hoe',
      'bundle/setup' => -> { true },
   }

   def config
      @@config ||= ObjectSpace.each_object(Setup::Configuration).first
   rescue NameError
   end

   def gem(gem_name, *requirements) # :doc
      if req_in = config && config.use_gem_dependencies[gem_name]
         requirements = [Gem::Requirement.new(req_in)]
      end

      __setup_orig_gem(gem_name, *requirements)
   rescue Gem::MissingSpecError => e
      !MODULES[gem_name.to_s] && raise(e) || false
   end

   # Loads dependencies through metadata adapters or the real task libraries.
   # @param mod [String] library name or path accepted by Ruby's require
   # @return [Boolean] whether Ruby loaded a new feature
   # Rake execution bypasses adapter replacements. Other calls use a mapped
   # adapter when available and fall back to the real library if it fails.
   def require mod
      return __setup_orig_require(mod) if defined?(Setup::Rake) && Setup::Rake.running_tasks?

      if MODULES[mod]
         if MODULES[mod].is_a?(Proc)
            MODULES[mod][]
         else
            begin
               __setup_orig_require(MODULES[mod])
            rescue => e1
               __setup_orig_require(mod)
            end
         end
      else
         __setup_orig_require(mod)
      end
   end

   def yaml_load text
      if Gem::Version.new(Psych::VERSION) >= Gem::Version.new("4.0.0")
         YAML.load(text, aliases: true, permitted_classes:
            [Gem::Specification,
             Gem::Version,
             Gem::Dependency,
             Gem::Requirement,
             Symbol,
             OpenStruct,
             Time,
             Date])
      else
         YAML.load(text)
      end
   end
end

module Bundler
   class Runtime
#      alias :__setup :setup

#      def setup(*groups)
#         /(bundler\/setup.rb|Gemfile|Rakefile):/ !~ caller[0] && super || self
#      end
   end

   class << self
      def read_file(file)
         SharedHelpers.filesystem_access(file, :read) do
            begin
               File.open(file, "r:UTF-8", &:read)
            rescue Errno::ENOENT
               ""
            end
         end
      end
   end
end

class Array
   # actjoin(array) => [<pre_match1>, <pre_match2>, <pre_match3>, <post_match>]; array = [match1, match2, match3]
   #
   def actjoin array
      self.map.with_index { |x, i| [ x, array[i] ].compact }.flatten.join
   end
end

class Pathname
   def === value
      if value.is_a?(String)
         self.to_s === value
      else
         super
      end
   end

   def == value
      if value.is_a?(String)
         self.to_s == value
      else
         super
      end
   end
end

class String
   # actsplit(string, re) => [<pre_match1>, <pre_match2>, <pre_match3>, <post_match>], [match1, match2, match3]
   #
   def actsplit re
      string = self
      res = []

      until string.empty? do
         if m = re.match(string)
            res << [ string[ 0...m.begin(0) ], m[0] ]
            string = string[ m.end(0)..-1 ]

            if string.empty?
               res << [ string, nil ]
            end
         else
            res << [ string, nil ]
            string = ''
         end
      end

      res.transpose.map { |x| x.compact }
   end

   PLURAL_R = {
      /([xcs])$/ => '\1es',
      /us$/ => 'i',
      /$/ => 's'
   }

   SINGLE_R = {
      /([xcs])es$/ => '\1',
      /i$/ => 'us',
      /s$/ => ''
   }

   def make_plural
      PLURAL_R.reduce(nil) do |res, (re, char)|
         res || self.dup.sub!(re, char)
      end.to_s
   end

   def make_singular
      SINGLE_R.reduce(nil) do |res, (re, char)|
         res || self.dup.sub!(re, char)
      end.to_s
   end

   def constantize
      self.split('::').reduce(Object) do |c, token|
        token.empty? && c || c.const_get(token)
      end
   end
end

class Symbol
   def make_plural
      to_s.make_plural.to_sym
   end

   def make_singular
      to_s.make_singular.to_sym
   end
end

class OpenStruct
   def to_hash
      to_h
   end
end

class Hash
   def deep_merge other, options_in = {}
      return self if other.nil? or other.blank?

      options = { mode: :append }.merge(options_in)

      other_hash = other.is_a?(Hash) && other || { nil => other }
      common_keys = self.keys & other_hash.keys
      base_hash = (other_hash.keys - common_keys).reduce({}) do |res, key|
         res[key] = other_hash[key]
         res
      end

      self.reduce(base_hash) do |res, (key, value)|
         new =
         if common_keys.include?(key)
            case value
            when Hash, OpenStruct
               value.deep_merge(other_hash[key])
            when Array
               value.concat([ other_hash[key] ].compact.flatten(1))
            when NilClass
               other_hash[key]
            else
               value_out =
                  if options[:mode] == :append
                     [other_hash[key], value].compact.flatten(1)
                  elsif options[:mode] == :prepend
                     [value, other_hash[key]].compact.flatten(1)
                  else
                     value
                  end

               if value_out.is_a?(Array) && options[:dedup]
                  value_out.uniq
               else
                  value_out
               end
            end
         else
            value
         end

         res[key] = new
         res
      end
   end
end

class Object
   def self.const_get c, inherit = true
      super
   rescue Exception => e
      begin
        require c.to_s.downcase
      rescue Exception => e
      end

      super
   end

   def blank?
      case self
      when NilClass, FalseClass
         true
      when TrueClass
         false
      when Hash, Array
         !self.any?
      else
         self.to_s == ""
      end
   end

   def to_os
      def to_os hash: false, array: false
         self.to_h.reduce(::OpenStruct.new) do |res, (x, y_in)|
            res[x.to_s] =
               if hash && y_in.is_a?(Hash) || array && y_in.is_a?(Array)
                  y_in.to_os(hash: hash, array: array)
               else
                  y_in
               end

            res
         end
      end
   end
end

class Gem::Requirement
   MERGE_RELAS = { #:nodoc:
      "="  =>  :first,
      "!=" =>  :dup,
      ">"  =>  :max,
      "<"  =>  :min,
      ">=" =>  :max,
      "<=" =>  :min,
      "~>" =>  lambda do |a|
         ranges = a.map { |v| [v, v.bump] }.transpose
         ranges[0]&.max...ranges[1]&.min
      end
   }.freeze

   OR_RELAS = { #:nodoc:
      [ "=", ">=", nil ] => ->(l, r) { [[">=", [r, l].min]] },
      [ "=", "<=", -1 ] => ->(l, r) { [["<=", r]] },
      [ "=", "<=", 0 ] => ->(l, r) { [["<=", r]] },
      [ "=", ">", 0 ] => ->(l, r) { [[">=", r]] },
      [ "=", ">", 1 ] => ->(l, r) { [[">", r]] },
      [ "=", "<", -1 ] => ->(l, r) { [["<", r]] },
      [ "=", "<", 0 ] => ->(l, r) { [["<=", r]] },
      [ "=", "=", 0 ] => ->(l, r) { [["=", l]] },
      [ "=", "~>", nil ] => ->(l, r) { [[">=", [r, l].min], ["<", r.bump]] },
      [ "!=", "=", -1 ] => ->(l, r) { [["=", r], ["!=", l]] },
      [ "!=", "=", 0 ] => ->(l, r) { [] },
      [ "!=", "=", 1 ] => ->(l, r) { [["=", r], ["!=", l]] },
      [ "!=", "!=", 0 ] => ->(l, r) { [["!=", l]] },
      [ "!=", ">", -1 ] => ->(l, r) { [[">", r]] },
      [ "!=", ">", 0 ] => ->(l, r) { [[">", r]] },
      [ "!=", ">", 1 ] => ->(l, r) { [[">", r], ["!=", l]] },
      [ "!=", "<", -1 ] => ->(l, r) { [["<", r], ["!=", l]] },
      [ "!=", "<", 0 ] => ->(l, r) { [["<", r]] },
      [ "!=", "<", 1 ] => ->(l, r) { [["<", r]] },
      [ "!=", ">=", -1 ] => ->(l, r) { [[">=", r]] },
      [ "!=", ">=", 0 ] => ->(l, r) { [[">", r]] },
      [ "!=", ">=", 1 ] => ->(l, r) { [[">=", r], ["!=", l]] },
      [ "!=", "<=", -1 ] => ->(l, r) { [["<=", r], ["!=", l]] },
      [ "!=", "<=", 0 ] => ->(l, r) { [["<", r]] },
      [ "!=", "<=", 1 ] => ->(̀r, l) { [["<=", r]] },
      [ "!=", "~>", -1 ] => ->(l, r) { [[">=", r], ["<", r.bump], ["!=", l]] },
      [ "!=", "~>", 0 ] => ->(l, r) { [[">", r], ["<", r.bump]] },
      [ "!=", "~>", 1 ] => ->(l, r) { [[">=", r], ["<", r.bump], ["!=", l]] },
      [ ">", "=", 0 ] => ->(l, r) { [[">=", l]] },
      [ ">", "=", 1 ] => ->(l, r) { [[">", l]] },
      [ ">", "!=", 0 ] => ->(l, r) { [[">", l]] },
      [ ">", "!=", 1 ] => ->(l, r) { [[">", l]] },
      [ ">", ">", nil ] => ->(l, r) { [[">", [r, l].min]] },
      [ ">", "<", 0 ] => ->(l, r) { [] },
      [ ">", "<", 1 ] => ->(l, r) { [] },
      [ ">", ">=", -1 ] => ->(l, r) { [[">", l]] },
      [ ">", ">=", 0 ] => ->(l, r) { [[">=", r]] },
      [ ">", ">=", 1 ] => ->(l, r) { [[">=", r]] },
      [ ">", "<=", 0 ] => ->(l, r) { [] },
      [ ">", "<=", 1 ] => ->(l, r) { [] },
      [ ">", "~>", -1 ] => ->(l, r) { [[">", l], ["<", r.bump]] },
      [ ">", "~>", 0 ] => ->(l, r) { [[">=", r], ["<", r.bump]] },
      [ ">", "~>", 1 ] => ->(l, r) { [[">=", r], ["<", r.bump]] },
      [ "<", "=", 0 ] => ->(l, r) { [["<=", l]] },
      [ "<", "=", 1 ] => ->(l, r) { [["<", l]] },
      [ "<", "!=", -1 ] => ->(l, r) { [["<", l]] },
      [ "<", "!=", 0 ] => ->(l, r) { [["<", l]] },
      [ "<", ">", -1 ] => ->(l, r) { [] },
      [ "<", ">", 0 ] => ->(l, r) { [] },
      [ "<", ">", 1 ] => ->(l, r) { [[">", r], ["<", l]] },
      [ "<", "<", nil ] => ->(l, r) { [["<", [r, l].max]] },
      [ "<", ">=", -1 ] => ->(l, r) { [] },
      [ "<", ">=", 0 ] => ->(l, r) { [] },
      [ "<", ">=", 1 ] => ->(l, r) { [[">=", r], ["<", l]] },
      [ "<", "~>", nil ] => ->(l, r) { [[">=", r], ["<", [l, r.bump].max]] },
      [ ">=", "=", 0 ] => ->(l, r) { [[">=", l]] },
      [ ">=", "=", -1 ] => ->(l, r) { [[">=", l], ["=", r]] },
      [ ">=", "!=", 0 ] => ->(l, r) { [[">", l]] },
      [ ">=", "!=", 1 ] => ->(l, r) { [[">=", l]] },
      [ ">=", ">", -1 ] => ->(l, r) { [[">=", l]] },
      [ ">=", ">", 0 ] => ->(l, r) { [[">=", l]] },
      [ ">=", ">", 1 ] => ->(l, r) { [[">", r]] },
      [ ">=", "<", 0 ] => ->(l, r) { [] },
      [ ">=", "<", 1 ] => ->(l, r) { [] },
      [ ">=", ">=", nil ] => ->(l, r) { [[">=", [r, l].min]] },
      [ ">=", "<=", 0 ] => ->(l, r) { [["=", l]] },
      [ ">=", "<=", 1 ] => ->(l, r) { [] },
      [ ">=", "~>", nil ] => ->(l, r) { [[">=", [r, l].min], ["<", r.bump]] },
      [ "<=", "=", 0 ] => ->(l, r) { [["<=", l]] },
      [ "<=", "=", 1 ] => ->(l, r) { [["<=", l]] },
      [ "<=", "!=", -1 ] => ->(l, r) { [["<", l]] },
      [ "<=", "!=", 0 ] => ->(l, r) { [["<", l]] },
      [ "<=", ">", -1 ] => ->(l, r) { [] },
      [ "<=", ">", 0 ] => ->(l, r) { [] },
      [ "<=", ">", 1 ] => ->(l, r) { [[">", r], ["<=", l]] },
      [ "<=", "<", -1 ] => ->(l, r) { [["<=", l]] },
      [ "<=", "<", 0 ] => ->(l, r) { [["<=", l]] },
      [ "<=", "<", 1 ] => ->(l, r) { [["<", r]] },
      [ "<=", ">=", -1 ] => ->(l, r) { [] },
      [ "<=", ">=", 0 ] => ->(l, r) { [["=", l]] },
      [ "<=", ">=", 1 ] => ->(l, r) { [[">=", r], ["<=", l]] },
      [ "<=", "~>", ->(l, r) { r.bump > l } ] => ->(l, r) { [[">=", r], ["<", r.bump]] },
      [ "<=", "~>", ->(l, r) { r.bump <= l } ] => ->(l, r) { [[">=", r], ["<=", l]] },
      [ "~>", "=", nil ] => ->(l, r) { [[">=", [l, r].min], ["<", l.bump]] },
      [ "~>", "!=", -1 ] => ->(l, r) { [[">=", l], ["<", l.bump], ["!=", r]] },
      [ "~>", "!=", 0 ] => ->(l, r) { [[">", l], ["<", l.bump]] },
      [ "~>", "!=", 1 ] => ->(l, r) { [[">=", l], ["<", l.bump], ["!=", r]] },
      [ "~>", ">", -1 ] => ->(l, r) { [[">=", l], ["<", l.bump]] },
      [ "~>", ">", 0 ] => ->(l, r) { [[">=", l], ["<", l.bump]] },
      [ "~>", ">", 1 ] => ->(l, r) { [[">", r], ["<", l.bump]]},
      [ "~>", "<", nil ] => ->(l, r) { [[">=", l], ["<", [r, l.bump].max]] },
      [ "~>", ">=", nil ] => ->(l, r) { [[">=", [l, r].min], ["<", l.bump]] },
      [ "~>", "<=", ->(l, r) { l.bump > r } ] => ->(l, r) { [[">=", l], ["<", l.bump]] },
      [ "~>", "<=", ->(l, r) { l.bump <= r } ] => ->(l, r) { [[">=", l], ["<=", r]] },
      [ "~>", "~>", nil ] => ->(l, r) { [[">=", [r, l].min], ["<", [r.bump, l.bump].max]] }
   }.freeze

   def | other_requirement
      self.class.expand_requirements(self.requirements | other_requirement.requirements)
   end

   def expand
      self.class.expand_requirements(self.requirements)
   end

   def self.expand_requirements requirements
      reqs_in = []
      res = requirements.dup

      #binding.pry
      while reqs_in != res do
         reqs_in = res
         reqs = reqs_in.dup
         res = []

         #binding.pry
         while !reqs.empty? do
            op1, ver1 = reqs.shift
            op2, ver2 = reqs.shift || [op1, ver1]

            prc =
               Gem::Requirement::OR_RELAS.find do |((left, right, comp), _)|
                  match = op1 == left && op2 == right &&
                     case comp
                     when NilClass
                        true
                     when Integer
                        comp == (ver1 <=> ver2)
                     when Proc
                        comp[ver1, ver2]
                     end
               end

            #binding.pry
            res =
               if prc
                  res.concat(prc.last[ver1, ver2])
               elsif reqs.empty?
                  res.concat([[op1, ver1], [op2, ver2]])
               else
                  #binding.pry
                  reqs.unshift([op2, ver2])
                  res.concat([[op1, ver1]])
               end
         end
      end

      #binding.pry
      Gem::Requirement.new(res.map {|x|x.join(" ")})
   end

   def merge other_requirement
      reqs_tmp = self.requirements | other_requirement.requirements

      relas =
         Gem::Requirement::MERGE_RELAS.map do |(op, prc)|
            selected = reqs_tmp.map { |(rel, version)| rel == op && version || nil }.compact

            prc.is_a?(Proc) && prc[selected] || selected.send(prc)
         end

      reqs =
         if relas[0]
            [ relas[0] ]
         else
            e = [ relas[3], relas[5], relas[6].begin ].compact.max
            b = [ relas[2], relas[4], relas[6].end ].compact.min

            bounds =
               [ b && Gem::Requirement.new(">#{b != relas[2] && "=" || ""} #{b}") || nil,
                 e && Gem::Requirement.new("<#{e != relas[3] && "=" || ""} #{e}") || nil ].compact

            nes = relas[1].select {|ver| bounds.all? {|b| b.satisfied_by?(ver) }}

            bounds | nes
         end

      Gem::Requirement.new(reqs)
   end
end

class Dir
   class << self
      alias :__system_brackets :[]

      def dir_cache
         @@dir_cache ||= {}
      end

      def [] *args, base: nil, sort: true
         dir_cache[[Dir.pwd, args.first]] ||= __system_brackets(*args, base: base)
      end
   end
end

# Forcely replace method/class
require 'rubygems/dependency_installer.rb'
module Gem
   class Dependency
      class InvalidDependencyNameError < StandardError; end

      alias :orig_merge :merge

      def merge dep_in
         raise InvalidDependencyNameError if self.name != dep_in.name

         options = {
            "type" => :runtime,
            "group" => (self.groups || []) | (dep_in.groups || []),
         }
         if self.respond_to?(:platforms) && dep_in.respond_to?(:platforms)
            options["platforms"] = self.platforms & dep_in.platforms
         end

         Bundler::Dependency.new(self.name, orig_merge(dep_in).requirement.expand.merge(dep_in.requirement), options)
      rescue
        binding.pry
      end
   end

   class DependencyInstaller
      class << self
         def deps
            @deps ||= []
         end

         def store dep
            path = caller[1].scan(/^(.*):(\d+)(?::.*`(.*)')?\Z/).first.first

            deps << [path, dep]
         end

         def clean
            @deps = []
         end
      end

      def install dep
         self.class.store(dep)
      end
   end
end
