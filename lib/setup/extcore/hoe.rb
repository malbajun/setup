# Hoe based gemspec detection module
# Sample gems are: hoe, racc, nokogiri, ruby_parser, oedipus_lex
#
class Hoe
   DOC_FILTER = /CHANGELOG|LICENSE|README|\.rb$/i
   PLUGINS = %w{rdoc hoe}
   GROUPS = {
      developer: :development,
      development: :development,
      runtime: :runtime
   }
   DEFAULT_CONFIG = {}

   def initialize name
      @spec ||= ::Gem::Specification.new
      @spec.name = name
   end

   def spec
      @spec
   end

   class << self
      def plugin plugin, *args
         @plugins = plugins | [plugin.to_s]
      end

      def plugins
         @plugins ||= ["hoe"]
      end

      def add_include_dirs *args
         args.each do |lib|
            try_require(lib.split("/").find {|x| x =~ /[a-zA-Z]/ })
         end
      end

      def try_require lib
         require(lib)
      rescue Exception
      end

      def plugin? name
         @plugins.include?(name)
      end

      def perforce_ignore
         []
      end

      def racc_flags
         []
      end

      # definitors
      def developer value, email
         @spec.spec.authors << value
         @spec.spec.email = [@spec.spec.email, email].compact.flatten
      end

      def license value
         @spec.spec.licenses |= [value]
      end

      def require_ruby_version data
         @spec.spec.required_ruby_version = data
      end

      def dependency name, dep, group_in = :runtime
         group = GROUPS[group_in] || :runtime

         @spec.spec.dependencies << Gem::Dependency.new(name, Gem::Requirement.new([dep]), group)
      end

      def extras
         spec_extras.map do |k, v|
            [k, v.is_a?(Proc) ? v[] : v]
         end.to_h
      end

      def spec_extras
         @extras ||= {}
      end

      def spec_extras= value
         @extras = spec_extras.merge(value)
      end

      def extra_rdoc_files
         @extra_rdoc_files ||= []
      end

      def extra_rdoc_files= files
         extra_rdoc_files.concat(files)
      end

      def extra_deps
         @extra_deps ||= []
      end

      def extra_dev_deps
         @extra_dev_deps ||= []
      end

      def clean_globs
         @clean_globs ||= []
      end

      def readme_file= file
         @readme_file = file
      end

      def history_file= file
         @history_file = file
      end

      def history_file
         @history_file ||= Dir['{History,Changelog,HISTORY,CHANGELOG}*'].first
      end

      def readme_file
         @readme_file ||= Dir['{README,Readme,readme}*'].first
      end

      def test_globs= _globs
      end

      def bad_plugins
         []
      end

      def rdoc_locations
         []
      end

      # spec
      def spec name = nil, &block
         main

         return @spec.spec if @spec

         plugin("hoe")

         @spec ||= self.new(name)

         init(name)
         @spec.instance_eval(&block)
         post_init

         @spec
      rescue Exception => e
         $stderr.puts("[#{e.class}]: #{e.message}\n\t#{e.backtrace.join("\n\t")}")

         nil
      end

      def name
         @spec&.spec&.name
      end

      def main
         @main = TOPLEVEL_BINDING.eval('self')
         @main.extend(Main)
         @main.include(Main)
      end

      # autoload hoe modules folder and assign plugins
      def init name
         @spec.spec.files = IO.read('Manifest.txt').split("\n")
         @spec.spec.extra_rdoc_files = @spec.spec.files.select { |f| DOC_FILTER =~ f }
         @spec.spec.executables = @spec.spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
         @spec.spec.bindir = 'bin'

         version =
            if history_file
               IO.read(history_file).split("\n").reduce(nil) { |res, x| res || /(=+|#+) v?(?<version>[^ ]+)/ =~ x && version }
            else
               instance_eval(`grep VERSION . -r|sed s,.*:,,`.strip)
            end
         @spec.spec.version = version

         readme = IO.read(readme_file)
         description = readme.split(/(=+|#+)/).reduce(nil) { |res, x| res || /^ Description:?(?<desc>.*)/im =~ x && desc }&.strip

         @spec.spec.description ||= description
         @spec.spec.summary ||= description.to_s.split(/[.(!]/).first

         /code ::(?<url>.*)|^\* (?<url>http.*)/ =~ readme
         @spec.spec.metadata["source_code_uri"] = url&.strip

         if /home ::(?<url>.*)|^\* (?<url>http.*)/ =~ readme
            @spec.spec.homepage = url.strip
            @spec.spec.metadata["homepage_uri"] = url.strip
            @spec.spec.metadata["source_code_uri"] ||= /github.com|bitbucket.com/ =~ url && url.strip || nil
         end
         dependency("rdoc", ">= 4.0", :development) if @spec.spec.files.grep(/.rdoc$/).any? || /rdoc ::/ =~ readme

         Dir.glob(Dir.pwd + '/lib/hoe/*.rb').each do |x|
            begin
               require_relative(x)
            rescue Exception
               nil
            end
         end
         self.constants.map {|c| self.const_get(c) }.select {|x| x.is_a?(Module) }.each {|x| extend(x) }
         if self.respond_to?("initialize_#{@spec.spec.name}")
            send("initialize_#{@spec.spec.name}")
         end
      end

      def post_init
         extras.each { |key, value| @spec.spec.send("#{key}=", value) }
         @extra_dev_deps&.each do |(name, dep)|
            dependency(name, dep, :development)
         end
         @extra_deps&.each do |(name, dep)|
            dependency(name, dep, :runtime)
         end
         @spec.spec.extra_rdoc_files.concat(extra_rdoc_files)

         @clean_globs&.each {|glob| Dir[glob].each {|file| FileUtils.rm_rf(file) }}

         (@plugins & PLUGINS).each { |name| dependency(name, ">= 0", :development) }
         @plugins.each { |name| try_require(name) }
      end
   end

   module Main
      def method_missing method_name, *args
         if Hoe.respond_to?(method_name)
            Hoe.send(method_name, *args)
         else
            $stderr.puts("[MethodMissing]: #{method_name} with args #{args.inspect} is missing")
         end
      end
   end
end
