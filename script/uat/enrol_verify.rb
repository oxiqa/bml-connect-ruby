# frozen_string_literal: true

# Step 2 of the UAT enrolment test. Run after paying on the hosted page.
#
#   ruby script/uat/enrol_verify.rb <transaction_id> <customer_id>
#
# Confirms the transaction, then reports what the gateway holds for the
# customer and what happens when a token is deleted.
#
# Destructive: deletes the token it finds.

require_relative 'env'

transaction_id, customer_id = ARGV
abort 'usage: enrol_verify.rb <transaction_id> <customer_id>' if transaction_id.nil? || customer_id.nil?

client = UATScript.client
findings = {}

def show_tokens(list)
  items = list.respond_to?(:items) ? list.items : list
  if items.nil? || items.empty?
    puts '  (none)'
    return []
  end
  items.each do |t|
    puts "  id=#{t.id.inspect} deleted=#{t.respond_to?(:deleted) ? t.deleted.inspect : 'n/a'} " \
         "card=#{t.respond_to?(:paddedCardNumber) ? t.paddedCardNumber.inspect : 'n/a'} " \
         "agreement=#{t.respond_to?(:tokenAgreementType) ? t.tokenAgreementType.inspect : 'n/a'}"
  end
  items
end

UATScript.heading 'Transaction'
transaction = client.transactions.retrieve(transaction_id)
findings[:state] = transaction.state
puts "  state: #{transaction.state.inspect}"
puts '  NOTE: the card is only stored once this reports a successful payment.'

UATScript.heading 'Tokens for the customer'
tokens = show_tokens(client.tokens.list(customer_id))
findings[:token_stored] = !tokens.empty?

token = tokens.first
if token.nil?
  puts "\nNo token stored — nothing further to test."
else
  findings[:token_id] = token.id
  findings[:agreement_type] = token.respond_to?(:tokenAgreementType) ? token.tokenAgreementType : nil

  UATScript.heading "Deleting token #{token.id}"
  client.tokens.delete(customer_id, token.id)
  puts '  ok'

  UATScript.heading 'Tokens after deletion'
  remaining = show_tokens(client.tokens.list(customer_id))
  still_listed = remaining.any? { |t| t.id == token.id }
  findings[:deleted_token_still_listed] = still_listed
end

UATScript.heading 'Findings'
puts JSON.pretty_generate(findings)
