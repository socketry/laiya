# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"
require "sus/fixtures/async"
require "laiya"

describe "Laiya with Ollama's OpenAI-compatible API" do
	include Sus::Fixtures::Async::SchedulerContext
	
	it "discovers a local model and proxies a Chat Completions request" do
		provider = Laiya::Provider::OpenAI.new(
			endpoint: ENV.fetch("OLLAMA_ENDPOINT"),
			api_key: nil,
		)
		configuration = Laiya::Configuration.build do |builder|
			builder.provider :openai, provider, models: :discover
			builder.default_provider :openai
		end
		application = Laiya::Web::Application.new(configuration: configuration)
		model = ENV.fetch("OLLAMA_MODEL")
		
		models_response = application.call(Protocol::HTTP::Request["GET", "/v1/models"])
		expect(models_response.status).to be == 200
		models = JSON.parse(models_response.read).fetch("data")
		expect(models.any?{|entry| entry["id"] == model}).to be == true
		
		request = Protocol::HTTP::Request[
			"POST",
			"/v1/chat/completions",
			{"content-type" => "application/json"},
			[JSON.dump(
				model: model,
				messages: [{role: "user", content: "What is 2 + 2? Reply with only the number."}],
				stream: false,
				max_tokens: 64,
			)],
		]
		response = application.call(request)
		expect(response.status).to be == 200
		payload = JSON.parse(response.read)
		content = payload.dig("choices", 0, "message", "content")
		expect(content).to be_a(String)
		expect(content.empty?).to be == false
	ensure
		models_response&.close
		response&.close
		application&.close
	end
end
