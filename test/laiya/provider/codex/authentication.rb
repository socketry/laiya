# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"
require "base64"
require "tmpdir"
require "sus/fixtures/async/reactor_context"
require "laiya/provider/codex"

describe Laiya::Provider::Codex::Authentication do
	include Sus::Fixtures::Async::ReactorContext
	
	def before
		super
		
		@codex_home = Dir.mktmpdir("laiya-codex-auth-")
		File.write(
			File.join(@codex_home, "auth.json"),
			JSON.dump(
				auth_mode: "chatgpt",
				tokens: {
					access_token: "not-a-real-token",
					refresh_token: "not-a-real-refresh-token",
					account_id: "account-for-test",
					id_token: {chatgpt_account_id: "account-for-test"},
				},
				last_refresh: Time.now.utc.iso8601,
			),
		)
		@authentication = subject.new(codex_home: @codex_home)
	end
	
	def after(error = nil)
		@authentication&.close
		FileUtils.remove_entry(@codex_home) if @codex_home && File.exist?(@codex_home)
		
		super
	end
	
	it "loads the ChatGPT account credentials without exposing their values" do
		credentials = @authentication.credentials
		
		expect(credentials[:access_token]).to be == "not-a-real-token"
		expect(credentials[:account_id]).to be == "account-for-test"
	end
	
	it "rejects API-key auth files" do
		File.write(File.join(@codex_home, "auth.json"), JSON.dump(auth_mode: "apikey"))
		
		expect{@authentication.credentials}.to raise_exception(Laiya::Provider::Codex::Authentication::Error)
	end
	
	it "reports missing, malformed, and incomplete auth files" do
		File.delete(File.join(@codex_home, "auth.json"))
		expect{@authentication.credentials}.to raise_exception(subject::Error)
		
		File.write(File.join(@codex_home, "auth.json"), "not json")
		expect{@authentication.credentials}.to raise_exception(subject::Error)
		
		File.write(
			File.join(@codex_home, "auth.json"),
			JSON.dump(auth_mode: "chatgpt", tokens: {access_token: "access-only"}),
		)
		expect{@authentication.credentials}.to raise_exception(subject::Error)
	end
	
	it "reads account and residency claims from JWT payloads" do
		encode = lambda do |claims|
			"header.#{Base64.urlsafe_encode64(JSON.dump(claims), padding: false)}.signature"
		end
		access_token = encode.call("exp" => Time.now.to_i + 600, "chatgpt_compute_residency" => "eu")
		id_token = encode.call("chatgpt_account_id" => "jwt-account")
		File.write(
			File.join(@codex_home, "auth.json"),
			JSON.dump(
				auth_mode: "chatgpt",
				tokens: {access_token: access_token, refresh_token: "refresh", id_token: id_token},
				last_refresh: (Time.now - 8 * 24 * 60 * 60).utc.iso8601,
			),
		)
		
		credentials = @authentication.credentials
		
		expect(credentials[:account_id]).to be == "jwt-account"
		expect(credentials[:residency]).to be == "eu"
	end
	
	it "rejects invalid JWT claims when no account ID is available" do
		File.write(
			File.join(@codex_home, "auth.json"),
			JSON.dump(
				auth_mode: "chatgpt",
				tokens: {access_token: "invalid-access-token", refresh_token: "refresh", id_token: "header.%%%.signature"},
				last_refresh: Time.now.utc.iso8601,
			),
		)
		
		expect{@authentication.credentials}.to raise_exception(subject::Error)
	end
	
	it "refreshes stale tokens and persists the rotated credentials" do
		File.write(
			File.join(@codex_home, "auth.json"),
			JSON.dump(
				auth_mode: "chatgpt",
				tokens: {access_token: "old-access", refresh_token: "old-refresh", account_id: "account-for-test"},
				last_refresh: (Time.now - 8 * 24 * 60 * 60).utc.iso8601,
			),
		)
		client = Class.new do
			attr :requests
			
			def initialize
				@requests = []
			end
			
			def call(request)
				@requests << {path: request.path, body: request.read}
				Protocol::HTTP::Response[200, {}, [JSON.dump(access_token: "new-access", refresh_token: "new-refresh")]]
			end
		end.new
		authentication = subject.new(codex_home: @codex_home, client: client)
		
		credentials = authentication.credentials
		stored = JSON.parse(File.read(File.join(@codex_home, "auth.json")))
		
		expect(credentials[:access_token]).to be == "new-access"
		expect(stored.dig("tokens", "refresh_token")).to be == "new-refresh"
		expect(client.requests.first[:path]).to be == "/oauth/token"
	ensure
		authentication&.close
	end
	
	it "rejects failed and malformed credential refresh responses" do
		stale_auth = {
			auth_mode: "chatgpt",
			tokens: {access_token: "old-access", refresh_token: "old-refresh", account_id: "account-for-test"},
			last_refresh: (Time.now - 8 * 24 * 60 * 60).utc.iso8601,
		}
		
		[Protocol::HTTP::Response[500], Protocol::HTTP::Response[200, {}, ["not json"]]].each do |response|
			File.write(File.join(@codex_home, "auth.json"), JSON.dump(stale_auth))
			client = Class.new do
				def initialize(response)
					@response = response
				end
				
				def call(_request)
					@response
				end
			end.new(response)
			authentication = subject.new(codex_home: @codex_home, client: client)
			
			expect{authentication.credentials}.to raise_exception(subject::Error)
		end
	end
end
