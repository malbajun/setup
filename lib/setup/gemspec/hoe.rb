require 'hoe/setup'

module Setup::Gemspec::Hoe
   RE = /\/Rakefile$/

   class << self
      attr_reader :hoe

      def parse rakefile
         if defined? Hoe
            if !hoe && File.exist?(rakefile)
               load rakefile
            end

            hoe&.spec
         end
      end
   end
end
