require 'yaml'

module Setup::Actor
   class << self
      def actors
         @actors ||= Setup::Actor.constants.map do |x|
            [ "#{x}".downcase, Setup::Actor.const_get(x) ]
         end.to_h
      end

      def scheme
         @scheme ||= YAML.load(IO.read(File.join(File.dirname(__FILE__), "scheme.erb.yaml")))
      end

      def config
         @config ||= ObjectSpace.each_object(Setup::Configuration).first
      end

      def procline file
         scheme.map.with_index do |rule, index|
            match = rule['match']

            if !match || /#{match}$/ =~ file
               rule['proc'].map do |data|
                  # TODO cache it by match or index
                  context_in = ERB.new(data['context'].to_yaml)
                  c = yield(data['actor'], context_in)
                  c.merge('$' => actors[data['actor']], "source_file" => file)
               end
            end
         end.compact
      end

      def objectizes
         @objectizes ||= {}
      end

      def objectize target
         objectizes[target] ||=
            target.source.trees do |kind, h|
               h.map do |dir, files|
                  files.map do |file|
                     next if config.match_ignore?(file)

                     procline(file) do |actor, context_in|
                        YAML.load(context_in.result(binding))
                     end
                  end
               end
            end.flatten.compact
      end
   end
end

require 'setup/actor/link'
require 'setup/actor/touch'
require 'setup/actor/copy'
require 'setup/actor/gen'
