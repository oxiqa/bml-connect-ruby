# BMLConnect

Ruby gem for the Bank of Maldives Connect API

Use this gem to interact with your Bank of Maldives Connect API:
- 💳 __Transactions__


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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/oxiqa/bml-connect-ruby. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/oxiqa/bml-connect-ruby/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the BMLConnect project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/oxiqa/bml-connect-ruby/blob/main/CODE_OF_CONDUCT.md).
