# Quickstart: Customers Endpoints

**Feature**: `001-customers-endpoints`

## Using the resource

```ruby
require "bml_connect"

client = BMLConnect::Client.new(
  api_key: ENV["BML_MPG_KEY"],
  app_id:  ENV["BML_MPG_APP_ID"],
  mode:    "sandbox"            # or "production"
)

customer = client.customers.create(name: "Aisha Ali", email: "aisha@example.mv")
customer.id                                     # => "…"

client.customers.retrieve(customer.id)
client.customers.update(customer.id, billingCity: "Hulhumale")
client.customers.list.each { |c| puts c.email }
client.customers.archive(customer.id)
```

In Rails, configure once via the initializer pattern the gem already documents:

```ruby
# config/initializers/bml_connect.rb
module BMLConnect
  class Client
    BML_API_KEY = Rails.application.credentials.bml_mpg_key
    BML_APP_ID  = ENV["BML_MPG_APP_ID"]
    BML_MODE    = ENV["BML_MPG_MODE"]
  end
end
```

Then `BMLConnect::Client.new.customers`.

## Error handling

Unlike `client.transactions`, which returns a raw `Faraday::Response`, the customers resource
returns value objects and **raises** on failure (see `research.md` R2):

```ruby
begin
  client.customers.create(name: "Aisha Ali", email: "aisha@example.mv")
rescue BMLConnect::ValidationError => e
  warn "bad input on #{e.field}: #{e.message}"
rescue BMLConnect::AuthenticationError
  warn "check BML_MPG_KEY / BML_MPG_MODE"
rescue BMLConnect::AvailabilityError
  warn "BML unreachable after retries — safe to retry later"
end
```

## Running the tests

```bash
bundle install

bundle exec rspec spec/unit spec/contract      # deterministic; no network
bundle exec rspec                              # adds integration (skips without creds)
bundle exec rubocop
```

The deterministic suite must be fully green before any UAT run. WebMock blocks all real
connections outside the integration directory.

### The conformance test

```bash
bundle exec rspec spec/contract/openapi_conformance_spec.rb
```

This one reads `reference/Connect-API.json` and fails if the resource can emit a path BML does
not publish. **If you are adding an endpoint and this test fails, the endpoint is wrong — not
the test.** Fix the path, or replace the vendored document with a newer BML export and record
the diff in `CHANGELOG.md`.

## Verifying against UAT

The integration suite is opt-in and skips cleanly without credentials:

```bash
export BML_API_KEY=<uat key from the merchant dashboard>
export BML_APP_ID=<uat app id>
export BML_ENV=sandbox

bundle exec rspec spec/integration/customers_uat_spec.rb --format documentation
```

Get credentials from the UAT merchant dashboard at
<https://dashboard.uat.merchants.bankofmaldives.com.mv>.

> **Known blocker.** The key in `msgowl/website`'s development credentials is currently rejected
> by UAT — it returns `{"statusCode":401,"message":"Unauthorized","code":"PP-C-004"}` even on the
> known-working `/public/transactions` path. The key is an unexpired HS256 JWT whose `appId`
> matches the sandbox app id in `.envrc`, so it is the right app but is no longer provisioned.
> A freshly issued UAT key is required before the verification table in
> `contracts/bml-remote.md` can be closed.

### Sanity-checking a credential before running the suite

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: $BML_API_KEY" \
  https://api.uat.merchants.bankofmaldives.com.mv/public/me
```

`200` means the key works. `401` with `PP-C-004` means BML rejected it. A bare
`403 {"message":"Forbidden"}` means the gateway did not match the route at all — that response is
identical for a path that does not exist, so never read it as an auth result.

## Closing the verification table

After a successful UAT run, update the table at the bottom of `contracts/bml-remote.md`,
replacing each `☐ pending credentials` with the observed status code and noting any field BML
returned that the document does not describe. Resolve every `[UNVERIFIED]` marker you were able
to settle.
