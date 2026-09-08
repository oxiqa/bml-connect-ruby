# frozen_string_literal: true

require "spec_helper"

# T013 [US1] — create validation, PAN screening, email shape, and auditing.
RSpec.describe BMLConnect::Customers, "#create" do
  let(:client) { build_client }
  let(:customers) { client.customers }

  def stub_create(status: 201, body: { id: "cus_1", name: "Aisha Ali", email: "aisha@example.mv" })
    stub_request(:post, customers_url(client))
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "local validation (no remote call)" do
    it "rejects a missing name and names the field" do
      expect { customers.create(email: "aisha@example.mv") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:name) }
      expect(a_request(:post, customers_url(client))).not_to have_been_made
    end

    it "rejects a blank name" do
      expect { customers.create(name: "  ", email: "aisha@example.mv") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:name) }
    end

    it "rejects a missing email and names the field" do
      expect { customers.create(name: "Aisha Ali") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:email) }
      expect(a_request(:post, customers_url(client))).not_to have_been_made
    end
  end

  describe "email shape check (lightweight, not strict RFC)" do
    it "rejects an email with no @ or domain" do
      expect { customers.create(name: "Aisha", email: "aisha") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:email) }
      expect(a_request(:post, customers_url(client))).not_to have_been_made
    end

    it "rejects an email with no domain part" do
      expect { customers.create(name: "Aisha", email: "aisha@") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:email) }
    end

    it "applies the same check to billingEmail when supplied" do
      expect { customers.create(name: "Aisha", email: "aisha@example.mv", billingEmail: "nope") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:billing_email).or eq(:billingEmail) }
    end

    it "accepts an ordinary address (no strict-RFC nitpicking)" do
      stub_create
      expect { customers.create(name: "Aisha", email: "aisha.ali+tag@sub.example.mv") }.not_to raise_error
    end
  end

  describe "PAN/CVV screening across every caller-supplied string field" do
    it "rejects a card number pasted into taxId" do
      expect { customers.create(name: "Aisha", email: "aisha@example.mv", taxId: "4111 1111 1111 1111") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:taxId) }
      expect(a_request(:post, customers_url(client))).not_to have_been_made
    end

    it "rejects a card number pasted into the name" do
      expect { customers.create(name: "4111111111111111", email: "aisha@example.mv") }
        .to raise_error(BMLConnect::ValidationError)
    end

    it "rejects an actor reference that looks like a PAN" do
      expect { customers.create({ name: "Aisha", email: "aisha@example.mv" }, actor: "4111111111111111") }
        .to raise_error(BMLConnect::ValidationError) { |e| expect(e.field).to eq(:actor) }
    end
  end

  describe "success path" do
    before { stub_create }

    it "returns a whitelisted Customer with the BML-assigned id" do
      customer = customers.create(name: "Aisha Ali", email: "aisha@example.mv")
      expect(customer).to be_a(BMLConnect::Models::Customer)
      expect(customer.id).to eq("cus_1")
    end

    it "emits a masked audit log line naming the create action and the App ID default" do
      customers.create({ name: "Aisha Ali", email: "aisha@example.mv" }, actor: "ops:jane")
      expect(log_output).to include("create")
      expect(log_output).to include("app-123") # who defaults to configured App ID
      expect(log_output).to include("ops:jane")
    end

    it "never lets a card number reach a log line" do
      # A valid-shaped create whose free-text billing field carries a PAN is
      # rejected before any logging, so no card data can appear in the log.
      expect { customers.create(name: "Aisha", email: "aisha@example.mv", billingAddress1: "4111111111111111") }
        .to raise_error(BMLConnect::ValidationError)
      expect(log_output).not_to include("4111111111111111")
    end
  end
end
