# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async"
require "async/http"
require "base64"
require "fileutils"
require "json"
require "tempfile"
require "time"
require "uri"

module Laiya
	module Provider
		class Codex < Interface
			# Loads and refreshes the local Codex CLI ChatGPT credentials.
			class Authentication
				CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
				ISSUER = "https://auth.openai.com"
				DEFAULT_CODEX_HOME = File.expand_path("~/.codex")
				REFRESH_AFTER = 7 * 24 * 60 * 60
				EXPIRY_SAFETY_MARGIN = 5 * 60
				
				# Raised when Codex credentials are missing, invalid, or cannot be refreshed.
				class Error < StandardError
				end
				
				# Initialize credential loading for a Codex home directory.
				# @option :codex_home [String] The directory containing `auth.json`.
				# @option :client [Interface(:call) | Nil] An optional OAuth HTTP client.
				# @option :endpoint [String | Async::HTTP::Endpoint] The OAuth issuer endpoint.
				def initialize(codex_home: ENV.fetch("CODEX_HOME", DEFAULT_CODEX_HOME), client: nil, endpoint: ISSUER)
					@codex_home = codex_home
					@auth_path = File.join(codex_home, "auth.json")
					@endpoint = Async::HTTP::Endpoint[endpoint]
					@client = client || Async::HTTP::Client.new(@endpoint)
					@owns_client = client.nil?
					@semaphore = Async::Semaphore.new(1)
				end
				
				# Load valid credentials and refresh them when requested or stale.
				# @option :refresh [Boolean] Force a credential refresh.
				# @returns [Hash] The access token, account ID, and optional residency.
				# @raises [Laiya::Provider::Codex::Authentication::Error] If the credentials cannot be used.
				def credentials(refresh: false)
					@semaphore.acquire do
						with_auth_lock do
							document = read_auth
							validate_auth(document)
							tokens = document.fetch("tokens")
							
							if refresh || stale?(tokens, document)
								document = refresh_auth(document)
								tokens = document.fetch("tokens")
							end
							
							account = account_id(tokens)
							raise Error, "Codex ChatGPT account ID is missing" unless account
							
							{
								access_token: tokens.fetch("access_token"),
								account_id: account,
								residency: residency(tokens.fetch("access_token")),
							}
						end
					end
				end
				
				# Close the OAuth client when this object created it.
				def close
					@client.close if @owns_client
				end
				
				private
				
				def with_auth_lock
					FileUtils.mkdir_p(@codex_home, mode: 0o700)
					File.open("#{@auth_path}.laiya.lock", File::RDWR|File::CREAT, 0o600) do |lock|
						lock.flock(File::LOCK_EX)
						return yield
					ensure
						lock.flock(File::LOCK_UN)
					end
				end
				
				def read_auth
					JSON.parse(File.read(@auth_path))
				rescue Errno::ENOENT
					raise Error, "Codex auth.json is missing; log in with `codex login` and use file credential storage"
				rescue JSON::ParserError
					raise Error, "Codex auth.json could not be parsed"
				end
				
				def validate_auth(document)
					unless document["auth_mode"] == "chatgpt" && document["tokens"].is_a?(Hash)
						raise Error, "Codex auth.json does not contain a ChatGPT login"
					end
					
					unless document.dig("tokens", "access_token") && document.dig("tokens", "refresh_token")
						raise Error, "Codex ChatGPT credentials are incomplete"
					end
				end
				
				def stale?(tokens, document)
					if expires_at = jwt_claims(tokens["access_token"])&.fetch("exp", nil)
						return expires_at.to_i <= Time.now.to_i + EXPIRY_SAFETY_MARGIN
					end
					
					last_refresh = Time.parse(document["last_refresh"]) rescue nil
					return true unless last_refresh
					
					Time.now - last_refresh >= REFRESH_AFTER
				end
				
				def refresh_auth(document)
					tokens = document.fetch("tokens")
					form = URI.encode_www_form({
						grant_type: "refresh_token",
						refresh_token: tokens.fetch("refresh_token"),
						client_id: CLIENT_ID,
					})
					headers = {"content-type" => "application/x-www-form-urlencoded", "accept" => "application/json"}
					request = Protocol::HTTP::Request["POST", "/oauth/token", headers, [form]]
					
					response = @client.call(request)
					unless response.status == 200
						status = response.status
						response.close
						raise Error, "Codex credential refresh failed with HTTP #{status}"
					end
					
					begin
						refreshed = JSON.parse(response.read)
					ensure
						response.close
					end
					tokens["access_token"] = refreshed.fetch("access_token")
					tokens["refresh_token"] = refreshed["refresh_token"] || tokens.fetch("refresh_token")
					document["last_refresh"] = Time.now.utc.iso8601
					save_auth(document)
					
					return document
				rescue JSON::ParserError, KeyError
					raise Error, "Codex credential refresh returned an invalid response"
				end
				
				def save_auth(document)
					Tempfile.create("auth.json", @codex_home) do |file|
						file.chmod(0o600)
						file.write(JSON.pretty_generate(document))
						file.flush
						file.fsync
						File.rename(file.path, @auth_path)
					end
				end
				
				def account_id(tokens)
					return tokens["account_id"] if tokens["account_id"]
					
					claims = jwt_claims(tokens["id_token"])
					claims&.fetch("chatgpt_account_id", nil) || claims&.dig("https://api.openai.com/auth", "chatgpt_account_id")
				end
				
				def residency(access_token)
					claims = jwt_claims(access_token)
					value = claims&.fetch("chatgpt_compute_residency", nil) || claims&.dig("https://api.openai.com/auth", "chatgpt_compute_residency")
					value unless value.nil? || value == "no_constraint"
				end
				
				def jwt_claims(token)
					return unless token.is_a?(String)
					
					payload = token.split(".")[1]
					return unless payload
					
					JSON.parse(Base64.urlsafe_decode64(payload))
				rescue ArgumentError, JSON::ParserError
					nil
				end
			end
		end
	end
end
