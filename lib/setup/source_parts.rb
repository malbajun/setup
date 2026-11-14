# Names selectable installation parts independently of source discovery.
module Setup::SourceParts
   KINDS = %w[lib doc devel exec app].freeze
   VALID_PARTS = (KINDS + ['all']).freeze

   def self.normalize(value)
      return {} if value.nil?
      entries = value.respond_to?(:each_pair) ? value.each_pair.to_a : value.to_s.split(',').map { |entry| entry.split(':', 2) }
      entries.each_with_object({}) do |(source, parts), result|
         name = source.to_s.strip
         raise ArgumentError, "invalid source part selector: #{source}" unless name.match?(/\A(?:\*|[[:alnum:]_.-]+)\z/) && parts
         selected = parts.is_a?(Array) ? parts.map(&:to_s) : parts.to_s.split('+')
         selected.map!(&:strip)
         raise ArgumentError, "invalid source parts: #{parts}" if selected.empty? || !(selected - VALID_PARTS).empty?
         merged = Array(result[name]) | selected
         result[name] = merged.include?('all') ? ['all'] : KINDS & merged
      end
   end

   def self.matches?(rules, source, part)
      [rules['*'], rules[source.to_s]].compact.any? do |parts|
         parts.include?('all') || parts.include?(part.to_s)
      end
   end
end
