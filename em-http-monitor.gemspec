# -*- encoding: utf-8 -*-
require File.expand_path("../lib/em-http-monitor/version", __FILE__)

Gem::Specification.new do |s|
  s.name        = "em-http-monitor"
  s.version     = EM::Http::MonitorFactory::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = []
  s.email       = []
  s.homepage    = "http://rubygems.org/gems/em-http-monitor"
  s.summary     = "Monitor, request recording and playback for em-http-request"
  s.description = "Monitor, request recording and playback for em-http-request"

  s.required_rubygems_version = ">= 1.3.6"
  s.rubyforge_project         = "em-http-monitor"

  s.add_development_dependency "bundler", ">= 1.0.0"

  s.files        = `git ls-files`.split("\n")
  s.executables  = `git ls-files`.split("\n").map{|f| f =~ /^bin\/(.*)/ ? $1 : nil}.compact
  s.require_path = 'lib'
end
