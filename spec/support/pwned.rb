# frozen_string_literal: true

# devise-pwned_password validates new and changed passwords against the
# HaveIBeenPwned range API. Tests must never hit the network (see
# WebMock.disable_net_connect!), so by default we stub the endpoint to report
# "not found" (an empty body). Specs that exercise pwned rejection can override
# this stub locally.
RSpec.configure do |config|
  config.before do
    stub_request(:get, %r{\Ahttps://api\.pwnedpasswords\.com/range/}i)
      .to_return(status: 200, body: "", headers: {})
  end
end
