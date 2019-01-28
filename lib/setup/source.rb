require 'setup'

module Setup::Source
   autoload(:Gem, 'setup/source/gem')
   autoload(:Root, 'setup/source/root')

   class << self
      def search dir, options = {}
         self.constants.map do |const|
            self.const_get(const).search(dir, options)
         end.flatten
      end
   end
end
