#!/usr/bin/env ruby
Dir[File.expand_path('../test/*_test.rb', __dir__)].sort.each do |file|
   require file
end
