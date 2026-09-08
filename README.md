# BMLConnect

Ruby gem for the Bank of Maldives Connect API

Use this gem to interact with your Bank of Maldives Connect API:
- 💳 __Transactions__

**Planned** — specified against BML's published contract, not yet implemented. See
[Roadmap](#roadmap):
- 👤 __Customers__
- 🔐 __Stored card tokens__
- 🔁 __Charging a stored card__


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'bml_connect'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install bml_connect

## Usage

First get your API key and App ID from Merchant Portal for [`production`](https://dashboard.merchants.bankofmaldives.com.mv) or [`sandbox`](https://dashboard.uat.merchants.bankofmaldives.com.mv).

For production client:
```ruby
require 'bml_connect`

client = BMLConnect::Client.new(api_key: '<your-api-key>', app_id: '<your-app-id>')
```
For sandbox client:
```ruby
require 'bml_connect`

client = BMLConnect::Client.new(api_key: '<your-api-key>', app_id: '<your-app-id>', mode: 'sandbox')
```
In Ruby on Rails, to configure globally, add an intilializer `bml_connect.rb`:
```ruby
module BMLConnect
  class Client
    BML_API_KEY = ENV['BML_MPG_KEY']
    BML_APP_ID = ENV['BML_MPG_APP_ID']
    BML_MODE = ENV['BML_MPG_MODE']
  end
end
````
```ruby
client = BMLConnect::Client.new
```
### API Operations
To create a new transaction
```ruby
resp = client.transactions.create({
  amount: 10000,
  currency: 'MVR',
  redirectUrl: '<your-redirect-uri>',
  localId: 'local-1',
  customerReference: 'INV-0001'
})
```
To fetch a specified transaction
```ruby
resp = client.transactions.get(id)
```
To transaction list
```ruby
resp = client.transactions.list({ page: 2 })
```
API responses are instances of [`Faraday::Response`](https://github.com/lostisland/faraday/blob/main/lib/faraday/response.rb) class, `json` encoded with symbolized names. 

## Roadmap

Tokenization support is moving into this gem. It was previously being built as a separate
`bml_tokenization` gem, which turned out to have been specified against an assumed API contract
that does not match BML's published one — see [MIGRATION.md](MIGRATION.md) for the full account.

Work is now spec-driven against BML's own OpenAPI document, vendored at
[`reference/Connect-API.json`](reference/Connect-API.json). Where this library and that document
disagree, the document wins.

| Feature | Endpoints | Status |
|---|---|---|
| [`001-customers-endpoints`](specs/001-customers-endpoints/) | `/public-customers` | Specified |
| [`002-stored-card-tokens`](specs/002-stored-card-tokens/) | `/public-customers/{id}/tokens` | Specified |
| [`003-transactions-v2`](specs/003-transactions-v2/) | `/public/v2/transactions` | Specified |
| [`004-token-charge`](specs/004-token-charge/) | `/public-customers/charge` | Specified, release-blocked |

Each feature directory carries a `spec.md`, `plan.md`, `research.md`, `data-model.md`, `tasks.md`
and two contracts — one for the BML HTTP surface, one for the Ruby surface this gem exposes.

### How tokenization actually works

Worth stating up front, because it is not what most payment APIs do: **there is no endpoint that
creates a token.** A stored card comes into existence as a side effect of a transaction that
carries `tokenizationDetails`, completed by the cardholder on BML's hosted page. Later charges
are a two-step flow — create a transaction, then charge it against the stored token.

```
create customer  ─►  create transaction with tokenizationDetails  ─►  cardholder pays
                                                                          │
                     charge stored token  ◄──  token now listed  ◄────────┘
```

### Backward compatibility

The transactions methods documented above are **not changing**. `create`, `get` and `list` keep
their current endpoints, signatures and `Faraday::Response` return type. New capabilities arrive
under new method names.

`transactions.create` will be marked **deprecated** in favour of a `create_v2` targeting BML's
documented `/public/v2/transactions`, but it will continue to work — it is live and carries
production traffic today.

## Contributing to the specs

This repository uses [Spec Kit](https://github.com/github/spec-kit). The active feature is
tracked in `.specify/feature.json`:

```bash
./speckit-feature            # show the active feature and the status of each
./speckit-feature 002        # switch the active feature
```

The project constitution is at [`.specify/memory/constitution.md`](.specify/memory/constitution.md).
Two rules matter most for anyone adding a remote call:

1. **A stubbed test is not evidence that an endpoint exists.** Every path must be traceable to
   `reference/Connect-API.json`, and stub URLs must derive from the client's base URL rather than
   being hardcoded.
2. **Anything not in the published document is marked `[UNVERIFIED]`** and must be confirmed
   against UAT before it is relied on.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/oxiqa/bml-connect-ruby. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/oxiqa/bml-connect-ruby/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the BMLConnect project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/oxiqa/bml-connect-ruby/blob/main/CODE_OF_CONDUCT.md).
