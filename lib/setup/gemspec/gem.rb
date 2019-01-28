module Setup::Gemspec::Gem
   RE = /\.gemspec$/

   class << self
      def parse file
         spec = nil

         FileUtils.chdir(File.dirname(file)) { spec = Gem::Specification.load(File.basename(file)) }

         spec
      end
   end
end
