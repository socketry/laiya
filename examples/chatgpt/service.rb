#!/usr/bin/env ruby
# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/http"
require "async/service"
require "async/service/managed/environment"
require "laiya"
require "laiya/environment/application"
require_relative "authentication"

configuration = Async::Service::Configuration.build do
	service "laiya-chatgpt" do
		include Laiya::Environment::Application
		
		configuration do
			Laiya::Configuration.build do |builder|
				codex = Laiya::Provider::Codex.new
				builder.provider :codex, codex, models: :discover
				builder.default_provider :codex
			end
		end
		
		application do
			Examples::ChatGPT::Authentication.new(super(),
				token: ENV.fetch("LAIYA_API_KEY"),
			)
		end
	end
end

Async::Service::Controller.run(configuration)
