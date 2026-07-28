module Setup::Actor::Link
   class NoDestinationDirError < StandardError ;end
   class NoSourceDirError < StandardError ;end
   class NoFileError < StandardError ;end

   class << self
      def apply context
         target_dir = context['target_dir'] || raise(NoDestinationDirError)
         source_dir = context['source_dir'] || raise(NoSourceDirError)
         file = context['file'] || raise(NoFileError)

         target_file = File.join(context['target_prefix'] || '', target_dir, file)
         source_file = File.join(source_dir, file)
         FileUtils.mkdir_p(File.dirname(target_file))
         FileUtils.rm_rf(target_file)
         FileUtils.ln_sr(source_file, target_file, force: true)
         $stdout.puts "  #{source_file} -> #{target_file}"
      end
   end
end
