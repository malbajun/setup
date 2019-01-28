begin
   require 'hoe'

   Hoe.plugin :setup

   module Hoe::Setup
      def initialize_setup # optional
         Setup::Gemspec::Hoe.instance_variable_set(:@hoe, self)
      end
   end
rescue LoadError
end
