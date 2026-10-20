# frozen_string_literal: true

# Step 1 of the UAT enrolment test, using BML's approved hosted redirect flow.
#
#   ruby script/uat/enrol_create.rb
#
# Creates a customer, then a tokenizing transaction carrying that customer's id,
# and prints the hosted page URL to open in a browser. Completing the payment
# there stores the card against the customer.
#
# Creates real records in BML UAT and takes a real MVR 1.00 in that environment.

require_relative 'env'

AMOUNT_MINOR = Integer(ENV.fetch('BML_TEST_AMOUNT', '100'))
RETURN_URL = ENV.fetch('BML_TEST_RETURN_URL', 'https://blatantly-together-whippet.ngrok-free.app/enrolment/return')

client = UATScript.client

UATScript.heading 'Creating customer'
customer = client.customers.create(
  name: 'Enrolment UAT Test',
  email: "enrolment-uat-#{Time.now.to_i}@example.test"
)
puts "  customer id: #{customer.id}"

UATScript.heading 'Creating tokenizing transaction'
transaction = client.transactions.create_v2(
  amount: AMOUNT_MINOR,
  currency: 'MVR',
  customerId: customer.id,
  localId: "ENROL/#{Time.now.to_i}",
  customerReference: 'Card enrolment',
  redirectUrl: RETURN_URL,
  tokenizationDetails: {
    tokenize: true,
    paymentType: 'UNSCHEDULED'
  }
)
puts "  transaction id: #{transaction.id}"
puts "  state:          #{transaction.state.inspect}"
puts "  amount:         #{AMOUNT_MINOR} minor units (MVR #{'%.2f' % (AMOUNT_MINOR / 100.0)})"
puts "  hosted page:    #{transaction.payment_url}"

UATScript.heading 'Next'
puts <<~NEXT
    1. Open the hosted page above and pay with a test card.
    2. Then run:

       ruby script/uat/enrol_verify.rb #{transaction.id} #{customer.id}
NEXT
