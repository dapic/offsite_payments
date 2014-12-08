require 'test_helper'

class WxpayNotificationTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    Wxpay.credentials = fixtures(:wxpay)
    Wxpay.logger.level = Logger::ERROR
    @notification = Wxpay.notification(notify_request)
  end

  def test_accessors
    assert_equal "CFT", @notification.bank_type
    assert_equal "1009000276201412050006592723", @notification.transaction_id
    assert_equal "R779991646_KPCMPP39", @notification.out_trade_no
    assert_equal 'CNY', @notification.fee_type
    assert_equal Time.parse("20141205150819"), @notification.time_end
    assert_equal Money.new(23, 'CNY'), @notification.cash_fee
    assert_equal Money.new(23, 'CNY'), @notification.total_fee
    assert_equal 'NATIVE', @notification.trade_type
  end

  def test_non_accessor_properties
    assert @notification.comm_success?
    assert @notification.acknowledge
    assert @notification.biz_success?
    assert @notification.success?
    assert_equal Money.new(23, 'CNY'), @notification.total_fee
    assert_equal Money.new(23, 'CNY'), @notification.amount
    assert_equal 'CNY', @notification.currency
  end

  def test_acknowledgement
    assert @notification.acknowledge
  end

  def test_raise_error_when_acknowledge_fails
    cred = fixtures(:wxpay)
    cred[:key] = 'fake_key'
    Wxpay.credentials = cred
    assert_raise_with_message(OffsitePayments::ActionViewHelperError, "Invalid Wxpay HTTP signature")  { @notification.acknowledge }
  end
  
  def test_respond_to_acknowledge
    assert @notification.respond_to?(:acknowledge)
  end
  
  def test_respond_to_api_response
    assert @notification.respond_to?(:api_response)
  end
  
  def test_api_response
    resp = @notification.api_response(:success)
    assert (resp.is_a? Wxpay::ApiResponse::NotificationResponse), "resp is actually #{resp.class.ancestors}"
    assert_equal '<?xml version="1.0"?>
<xml>
  <return_code><![CDATA[SUCCESS]]></return_code>
</xml>
', resp.to_xml
  end
  
  private

  def notify_request
    '
    <xml><appid><![CDATA[wx599b0e05f1873032]]></appid>
    <bank_type><![CDATA[CFT]]></bank_type>
    <cash_fee><![CDATA[23]]></cash_fee>
    <fee_type><![CDATA[CNY]]></fee_type>
    <is_subscribe><![CDATA[Y]]></is_subscribe>
    <mch_id><![CDATA[10011924]]></mch_id>
    <nonce_str><![CDATA[560b6b8e73c3429045b161ed6c8c57dc]]></nonce_str>
    <openid><![CDATA[o2Hzljt7pBjEvfD8JOZdXDToSZSc]]></openid>
    <out_trade_no><![CDATA[R779991646_KPCMPP39]]></out_trade_no>
    <result_code><![CDATA[SUCCESS]]></result_code>
    <return_code><![CDATA[SUCCESS]]></return_code>
    <sign><![CDATA[E6A2C21631C7F1894057FE7C7FE8C2A5]]></sign>
    <time_end><![CDATA[20141205150819]]></time_end>
    <total_fee>23</total_fee>
    <trade_type><![CDATA[NATIVE]]></trade_type>
    <transaction_id><![CDATA[1009000276201412050006592723]]></transaction_id>
    </xml>
    '
  end

end
