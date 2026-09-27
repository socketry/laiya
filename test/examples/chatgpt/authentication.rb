# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require_relative "../../../examples/chatgpt/authentication"

describe Examples::ChatGPT::Authentication do
	let(:middleware) {subject.new(Protocol::HTTP::Middleware::HelloWorld, token: "test-key")}
	
	with "#call" do
		it "rejects requests without the configured bearer key" do
			response = middleware.call(Protocol::HTTP::Request["GET", "/v1/models"])
			
			expect(response.status).to be == 401
			expect(response.headers["www-authenticate"]).to be(:include?, "Bearer")
		end
		
		it "forwards requests with the configured bearer key" do
			request = Protocol::HTTP::Request[
				"GET",
				"/v1/models",
				{"authorization" => "Bearer test-key"},
			]
			
			response = middleware.call(request)
			
			expect(response.status).to be == 200
			expect(response.read).to be == "Hello World!"
		end
	end
end
