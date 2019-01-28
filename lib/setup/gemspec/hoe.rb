begin
  require 'hoe'
rescue LoadError
end

module Setup::Gemspec::Hoe
   RE = /\/Rakefile$/

   class << self
      def parse rakefile
         if defined? Hoe
            if !defined?(HOE) && File.exist?(rakefile)
               load rakefile
            end

            if defined?(HOE)
                HOE.spec
            end
         end
      end
   end
end
