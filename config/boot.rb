require 'yaml'
YAML::ENGINE.yamler = 'syck'

require 'rubygems'

# Set up gems listed in the Gemfile.
ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../Gemfile', __FILE__)

require 'bundler/setup' if File.exists?(ENV['BUNDLE_GEMFILE'])

# http://stackoverflow.com/a/6539193/153718
require 'rails/commands/server'
module Rails
  class Server
    alias :default_options_alias :default_options
    def default_options
      default_options_alias.merge!(:Port => 8081)
    end
  end
end