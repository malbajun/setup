require 'setup'

class Setup::Deps
   attr_reader :project

   REQS = {
      'lib' => {
         proc { |target| target.source.compilable? }               => proc { |this| this.deps_ruby_version },
         proc { |target| target.source.valid? }                    => proc { |this, target| this.deps_dyno(target.source, 'lib', :dsl) },
      },
      'bin' => {
         proc { |target| target.public_executables.any? }          => proc { |this, target| this.deps_ruby_exec(target) },
         proc { |target| target.source.exefiles.any? &&
                         target.source.is_a?(Setup::Source::Gem) } => proc { |this, target| this.deps_dyno(target.source, 'bin', :dsl) },
      },
      'doc' => {
         proc { |target| target.source.is_a?(Setup::Source::Gem) } => proc { |this, target| this.deps_dyno(target.source, 'doc') },
      },
      'devel' => {
         proc { |target|
            target.source.is_a?(Setup::Source::Gem) &&
           (target.source.inctree.any? ||
            target.source.dsl.original_deps.any?) }                => proc { |this, target| this.deps_dyno(target.source, 'devel', :dsl) },
      }
   }

   PROVS = {
      'lib' => {
         proc { |target| target.source.is_a?(Setup::Source::Gem) } => proc { |this, target| this.deps_gem_ext(target.source) },
      },
      'bin' => {
         proc { |target| target.public_executables.any? }          => proc { |this, target| this.deps_execs(target) },
      },
   }

   def targets
      if name = project.config.current_package_name
         project.targets.select { |target| target.source.has_name?(name) }
      else
         project.targets
      end
   end

   def target_provs target, sets_in = nil
      sets = sets_in && [ sets_in ].flatten || PROVS.keys

      PROVS.select { |set, _| sets.include?(set) }.map do |set, data|
         provs = data.map do |cond_in, prov_in|
            cond = cond_in.is_a?(Proc) ? cond_in[target] : cond_in
            cond && (prov_in.is_a?(Proc) && prov_in[self, target] || prov_in) || []
         end.flatten

         [ set, provs ]
      end.to_h
   end

   def target_reqs target, sets_in = nil
      sets = sets_in && [ sets_in ].flatten || REQS.keys

      #require 'pry'; binding.pry
      REQS.select { |set, _| sets.include?(set) }.map do |set, data|
         reqs = data.map do |cond_in, req_in|
            cond = cond_in.is_a?(Proc) ? cond_in[target] : cond_in
            cond && (req_in.is_a?(Proc) && req_in[self, target] || req_in) || []
         end.flatten

         [ set, reqs.uniq ]
      end.to_h
   end

   def target_names target, set
      targets.map do |target|
         names_in =
            ([target.source.name] | target.source.alias_names).compact.map do |n|
               [prefix, n.gsub(/[_\-\.]+/, '-')].join("-")
            end.uniq

         names =
            if names_in
               case set
               when 'bin'
                  target.source.exefiles.map {|x|x.gsub(/[_\-\.]+/, '-')}
               when 'lib'
                  names_in
               when 'devel'
                  names_in.map {|n| "#{n}-devel" }
               when 'doc'
                  names_in.map {|n| "#{n}-doc" }
               end
            end
      end.flatten.compact
   end

   def target_req_list
      targets.reduce({}) do |res, target|
         target_reqs(target).reduce(res) do |res, (set, reqs)|
            res.merge(target_names(target, set) => reqs)
         end
      end
   end

   def target_prov_list
      targets.reduce({}) do |res, target|
         target_provs(target).reduce(res) do |res, (set, reqs)|
            res.merge(target_names(target, set) => reqs)
         end
      end
   end

   def prefix
     'gem'
   end

   ## deps
   def deps_gem_dsl source, set = 'lib'
      case set
      when 'bin'
         # TODO remove gemspec deps in favor of gemfile
         # dsl.runtime_deps(:gemfile)
         source.dsl.runtime_deps(:gemspec) | [source.dep]
      when 'devel'
         source.dsl.development_deps(:gemspec) | [source.dep]
      when 'doc'
         [source.dep]
      else
         source.dsl.runtime_deps(:gemspec)
      end
   end

   def render_deps_gem_dsl deps, dsl, set = 'lib'
      list = []

      deps.each do |dep|
         list << (["#{prefix}(#{dep.name})"] | self.class.lower_to_rpm(dep.requirement)).join(" ")
      end

      if /lib|bin/ =~ set
         list |=
            dsl.required_ruby_version.requirements.map do |(cond, ver)|
               self.class.lower_to_rpm(Gem::Requirement.new("#{cond} #{ver}"))
            end.reject {|x| x.blank? }.map do |req|
               [dsl.required_ruby] | req
            end.map {|x| x.join(" ") }
         list << "rubygems #{dsl.required_rubygems_version}"
      end

      list
   end

   def deps_ruby_version
      # TODO enable when fix for new version ruby rebuld
      #"ruby(#{RbConfig::CONFIG['ruby_version']})"
      ""
   end

   def deps_gem source
      ["gem(#{source.name})", source.version].compact.join(' = ')
   end

   def deps_gem_ext source
      %w(gem).map do |kind|
         "#{kind}(#{source.name}) = #{source.version}"
      end
   end

   def deps_dyno source, set, kind = nil
      root = project.config.dep_sources[set]
      name = (root[source.name] || root[nil]).first
      if name == 'auto'
         if kind == :dsl
            deps = deps_gem_dsl(source, set)

            render_deps_gem_dsl(deps, source.dsl, set)
         else
            deps_gem(source)
         end
      else
         project.select_source(name).map do |source|
            deps = deps_gem_dsl(source)

            render_deps_gem_dsl(deps, source.dsl)
         end
      end
   end

   def deps_ruby_exec target
      target.public_executables.map do |file|
         File.join(target.root, file)
      end.map do |file|
         if File.symlink?(file)
            realfile_in = File.readlink(file)
            realfile =
               if File.absolute_path?(realfile_in)
                  realfile_in
               else
                  dir =
                     if File.absolute_path?(file)
                        File.dirname(file)
                     else
                        File.join(target.root, File.dirname(file))
                     end
                  File.join(dir, realfile_in)
               end
            IO.read(realfile, mode: 'rb').split("\n").first
         elsif File.exist?(file)
            IO.read(file, mode: 'rb').split("\n").first
         end
      end.compact.uniq.map do |line|
         if match = /#!\s*(?<exec>\S+)/.match(line)
            match[:exec]
         else
            $stderr.puts "Invalid shebang line '#{line[0..20]}'"
            nil
         end
      end.compact.uniq
   end

   def deps_execs target
      target.public_executables
   end

   # common
   def deps type, set = nil
      $stderr.puts "* #{type} ->"

      method = method("target_#{type}")

      deps = targets.map do |target|
         $stderr.puts "  - [#{target.source.name}]"

         target_deps = method[target, set].each do |set, deps|
            if !deps.empty?
               $stderr.puts "    [#{set}]:"
               deps.each do |dep|
                  $stderr.puts "      #{dep}"
               end
            end
         end

         [ target.source.name, target_deps ]
      end.to_h
   end

   def reqs
      deps 'reqs', project.config.current_set
   end

   def provs
      deps 'provs', project.config.current_set
   end

   class << self
      def lower_to_rpm req
         req.requirements.reduce([]) do |res, r|
            merge(res, debound(r))
         end
      end

      # TODO for requirement
      # +debound+ crop upper limitation bound from the requirement rule
      #
      def debound req
         ver = Gem::Version.new("#{req[1]}".gsub(/x/, '0'))

         case req[0]
         when "~>"
            ['>=', ver.release]
         when ">=", ">", "="
            [req[0], ver.release]
         when "!="
            ['>', ver.release]
         else
            nil
         end
      end

      # TODO for requirement
      # +merge+ enstricts requirement
      # >= 4 & >= 5 => >= 5
      # > 5 ^ > 4 => > 5
      #
      # > 5 & >= 4 => > 5
      # > 4 & >= 4 => > 4
      # > 4 & >= 4.x => >= 4.x
      #
      # >= 4 & > 4 => > 4
      # >= 4 & > 5 => > 5
      # >= 5 & > 4 => >= 5
      #
      MERGE_CONDS = {
         ">=" => {
            code: -1,
         }
      }

      def merge req1, req2
         return req1 if req2.blank?
         return req2 if req1.blank?

         m = [req1[1], req2[1]].max

         if req1[0] == req2[0]
            [req1[0], m]
         elsif req1[0] == ">="
            req1[1] <= req2[1] ? [">", m] : [">=", m]
         elsif req1[0] == ">"
            req1[1] >= req2[1] ? [">", m] : [">=", m]
         elsif %w(= < <=).include?(req1[0])
            # unsupported
            req2
         else
            # unsupported
            req1
         end
      end
   end

   protected

   def initialize project: raise, options: {}
      @project = project
      @options = options
   end
end
require 'setup'
