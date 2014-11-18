require 'test_helper'

class TenpayNotificationTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    #@notification = Tenpay::Notification.new(http_raw_data, key: fixtures(:tenpay)[:key])
    request = URI(http_return_request)
    #puts request.query
    @notification = Tenpay::Notification.new(request.query, key: fixtures(:tenpay)[:partner_key])
  end

  def test_accessors
    assert_equal "BL", @notification.bank_type
    assert_equal "1223440201201411170032328302", @notification.transaction_id
    assert_equal "Uvw12OtEhcWJOWrI_h5vddwwlJcJ2HgiLo7E88Rnsvt9FFfaFT3u5xV9ljcC9l_g0ur0ecJY3Ynru9aMFcGAfED4RMq9vxc5", @notification.notify_id
    assert_equal "R710881279_XWE4TKU6", @notification.out_trade_no
    assert_equal 0, @notification.trade_state
    assert_equal 1, @notification.trade_mode
    assert_equal 1, @notification.fee_type
    assert_equal "1223440201", @notification.partner
    assert_equal Time.parse("20141117154007"), @notification.time_end
  end

  def test_non_accessor_properties
    assert @notification.is_payment_complete?
    assert_equal Money.new(275, 'CNY'), @notification.product_fee
    assert_equal Money.new(275, 'CNY'), @notification.total_fee
    assert_equal Money.new(0, 'CNY'), @notification.transport_fee
    assert_equal Money.new(0, 'CNY'), @notification.discount
    assert_equal Money.new(275, 'CNY'), @notification.amount
  end

  def test_acknowledgement
    assert @notification.acknowledge
  end

  def test_raise_error_with_unsupported_sign_type
    @notification = Tenpay::Notification.new(URI(http_return_request.gsub('MD5','DSA')).query, key: fixtures(:tenpay)[:partner_key])
    assert_raise_with_message(OffsitePayments::ActionViewHelperError, /not yet supported/) { @notification.acknowledge}
  end

  def test_raise_error_when_acknowledge_fails
    @notification = Tenpay::Notification.new(URI(http_return_request).query, key: "badmd5string")
    assert_raise_with_message(OffsitePayments::ActionViewHelperError, "Invalid Tenpay HTTP signature")  { @notification.acknowledge }
  end
  
  def test_respond_to_acknowledge
    assert @notification.respond_to?(:acknowledge)
  end
  
  private

  def http_return_request
    'http://test.shiguangcaibei.com/tenpay_checkout/done?bank_type=BL&discount=0&fee_type=1&input_charset=utf-8&notify_id=Uvw12OtEhcWJOWrI_h5vddwwlJcJ2HgiLo7E88Rnsvt9FFfaFT3u5xV9ljcC9l_g0ur0ecJY3Ynru9aMFcGAfED4RMq9vxc5&out_trade_no=R710881279_XWE4TKU6&partner=1223440201&product_fee=275&sign_type=MD5&time_end=20141117154007&total_fee=275&trade_mode=1&trade_state=0&transaction_id=1223440201201411170032328302&transport_fee=0&sign=F9F83A48044D25529D82A3E0AFB0BDA3'
  end

end
