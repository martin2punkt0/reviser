require 'spec_helper'

describe PaypalGateway do
  it "reads the api credential" do
    PayPal::SDK.configure.client_id.should eql "client_id"
    PayPal::SDK.configure.client_secret.should eql "client_secret"
  end

  describe '#prepare_payment' do
    subject { PaypalGateway.new }
    let(:purchase) { OpenStruct.new({total_amount: 42.20, description: "text"}) }
    let(:local_mock_payment) { double("payment") }
    
    context "when setting payment values" do
      before(:each) do
        subject.payment_factory = ->{ mock_payment }
        subject.return_url = "http://return/"
        subject.cancel_url = "http://cancel/"
        subject.prepare_payment(purchase)
        @it = subject.payment
      end

      it "sets the payment intent is sale" do
        @it.intent.should eql "sale"
      end
      
      it "sets the payment payer method to paypal" do
        @it.payer.payment_method.should eql "paypal"
      end

      it "sets the transactions according to the purchase" do
        @it.transactions[:amount][:total].should eql ("%.2f" % purchase.total_amount)
        @it.transactions[:amount][:currency].should eql "EUR"
        @it.transactions[:description].should eql purchase.description
      end
      
      it "sets the return and cancel url" do
        @it.redirect_urls.return_url.should eql "http://return/"
        @it.redirect_urls.cancel_url.should eql "http://cancel/"
      end

      it 'has default return and cancel url' do
        subject.return_url = nil
        subject.cancel_url = nil
        subject.prepare_payment(purchase)
        @it = subject.payment
        @it.redirect_urls.return_url.should eql "http://127.0.0.1:3000/purchase_processor/execute"
        @it.redirect_urls.cancel_url.should eql "http://127.0.0.1:3000/purchase_processor/destory"
      end
    end

    it "calls create for the payment" do
      local_mock_payment.stub(:create).and_return true
      subject.stub(:build_payment_from_purchase).and_return(local_mock_payment)
      expect(local_mock_payment).to receive(:create).once
      subject.prepare_payment(purchase)
    end

    context "with a successful created payment" do
      before(:each) do
        local_mock_payment.stub(:create).and_return true
        local_mock_payment.stub(:id).and_return "PAY-123456789"
        local_mock_payment.stub(:links).and_return mock_links()
        subject.stub(:build_payment_from_purchase).and_return(local_mock_payment)
      end

      it "stores the payment id" do 
        subject.prepare_payment(purchase)
        subject.payment_id.should eql "PAY-123456789"
      end

      it "stores the approval url" do
        subject.prepare_payment(purchase)
        subject.approval_url.should eql "http://test2"
      end
    end

    context "with a unsuccessful created payment" do
      before(:each) do
        local_mock_payment.stub(:create).and_return false
        local_mock_payment.stub(:error).and_return({ error: "error!" })
        subject.stub(:build_payment_from_purchase).and_return(local_mock_payment)
      end

      it "raises an PaymentError" do
        expect{ subject.prepare_payment(purchase) }.to raise_error PaypalGateway::PaymentError
      end

      it "logs a messages" do
        Rails.logger.should_receive(:error) 
        subject.prepare_payment(purchase) rescue PaypalGateway::PaymentError
      end
    end
  end

  describe '#execute_payment' do
    subject { PaypalGateway.new }
    let(:payment) { double(PaypalGateway::Payment) }
    let(:purchase) { double(Purchase) }
    
    before(:each) do
      payment.stub(:execute).and_return true
      payment.stub(:error).and_return OpenStruct.new
      PaypalGateway::Payment.stub(:find).and_return payment
      purchase.stub(:payment_id).and_return 'a_payment_id'
      purchase.stub(:payer_id).and_return 'a_payer_id'
    end

    it 'executes the payment with the payer_id' do
      expect(payment).to receive(:execute).with('a_payer_id').once
      subject.execute_payment(purchase)
    end

    it 'raises an PaymentError if the execution fails' do
      payment.stub(:execute).and_return false
      expect{subject.execute_payment(purchase)}.to raise_error(PaypalGateway::PaymentError)
    end
  end

  describe '#format_amount' do
    subject { PaypalGateway.new }
    it 'has exactly two digits after a decimal point' do
      subject.format_amount(1).should eql '1.00'
    end
  end

  def mock_payment
    OpenStruct.new( { payer: OpenStruct.new, transactions: OpenStruct.new, redirect_urls: OpenStruct.new, create: true })
  end

  def mock_links
    [OpenStruct.new({ "href"=> "http://test1", "rel"=> "self","method"=> "GET" }),
     OpenStruct.new({ "href"=> "http://test2", "rel"=> "approval_url", "method"=> "REDIRECT" }),
     OpenStruct.new({ "href"=> "http://test3", "rel"=> "execute", "method"=> "POST" })]
  end
end