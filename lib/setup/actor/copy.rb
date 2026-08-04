module Setup::Actor::Copy
   class NoDestinationDirError < StandardError ;end
   class NoSourceDirError < StandardError ;end
   class NoFileError < StandardError ;end

   class << self
      def allow c
         target = c["target"]

         case c["if"]
         when String
            instance_eval(c["if"])
         else
            return true
         end
      end

      def apply context
         target_dir = context['target_dir'] || raise(NoDestinationDirError)
         source_dir = context['source_dir'] || raise(NoSourceDirError)
         file = context['file'] || raise(NoFileError)

         target_file = File.join(context['target_prefix'] || '', target_dir, file)
         source_file = File.join(source_dir, file)
         FileUtils.mkdir_p(File.dirname(target_file))
         FileUtils.cp(source_file, target_file)
         $stdout.puts "  #{source_file} => #{target_file}"
      end
   end
end
