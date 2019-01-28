#!/usr/bin/env ruby
# Setup.rb v5.1.0
#
# This is a stand-alone bundle of the setup.rb application.
# You can place it in your projects script/ directory, or
# call it 'setup.rb' and place it in your project's
# root directory (just like old times).
#
# NOTE: As of version 5.1.0 this bundled rendition is also
# being used for the bin/setup.rb exe. Rather than the previous:
#
#   require 'setup/command'
#   Setup::Command.run
#
# By doing so, +rvm+ should be able to use it across all rubies
# without issue and without needing to install it for each.
require 'pry'
require 'setup/version'
require 'setup/base'
require 'setup/project'
require 'setup/compiler'
require 'setup/installer'
require 'setup/configuration'
require 'setup/tester'
require 'setup/uninstaller'
require 'setup/command'
require 'setup'
Setup::Command.run
