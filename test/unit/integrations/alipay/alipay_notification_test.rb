require 'test_helper'

class AlipayNotificationTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    @credential = fixtures(:'alipay-sgcb')
    @alipay = Alipay::Notification.new(http_raw_data, key: @credential[:key])
  end

  def test_accessors
    assert @alipay.complete?
    assert_equal "trade_status_sync", @alipay.notify_type
    assert_equal "2014111159601788", @alipay.trade_no
    assert_equal "R990240665", @alipay.out_trade_no
    assert_equal "0.00", @alipay.discount
    assert_equal "1", @alipay.payment_type
    assert_equal "1", @alipay.quantity
    assert_equal "2088611493982911", @alipay.seller_id
    assert_equal "acct-ali@shiguangcaibei.com", @alipay.seller_email
    assert_equal false, @alipay.is_total_fee_adjust?
    assert_equal "1.43", @alipay.total_fee
    assert_equal "1.43", @alipay.price

    assert_equal "订单编号:R990240665", @alipay.subject
    assert_equal "[\"KOSE高丝雪肌精洗颜乳\"]", @alipay.body
    assert_equal Time.parse("2014-11-11 17:58:50"), @alipay.gmt_create
    assert_equal Time.parse("2014-11-11 17:59:23"), @alipay.gmt_payment
    assert_equal Time.parse("2014-11-11 17:59:23"), @alipay.notify_time
    assert_equal "2088902582208882", @alipay.buyer_id
    assert_equal "18611543280", @alipay.buyer_email
    assert_equal "1d583bc9cf21ed879bcd428fd53ed5e16w", @alipay.notify_id
    assert_equal false, @alipay.use_coupon?
    assert_equal "1.43", @alipay.gross
  end

  def test_acknowledgement
    assert @alipay.acknowledge
  end

  def test_raise_error_with_unsupported_sign_type
    @alipay = Alipay::Notification.new(http_raw_data.gsub('MD5','DSA'), key: fixtures(:alipay)[:key])
    assert_raise_with_message(OffsitePayments::ActionViewHelperError, /not yet supported/) { @alipay.acknowledge}
  end

  def test_compositions
    #puts @alipay.inspect
    assert_equal Money.new(143, 'CNY'), @alipay.amount
  end

  def test_raise_error_when_acknowledge_fails
    @alipay = Alipay::Notification.new(http_raw_data, key: "badmd5string")
    assert_raise_with_message(OffsitePayments::ActionViewHelperError, "Invalid Alipay HTTP signature")  { @alipay.acknowledge }
  end
  
  def test_respond_to_acknowledge
    assert @alipay.respond_to?(:acknowledge)
  end
  
  private
  def http_raw_data
    <<-END_POST
discount=0.00&payment_type=1&subject=%E8%AE%A2%E5%8D%95%E7%BC%96%E5%8F%B7%3AR990240665&trade_no=2014111159601788&buyer_email=18611543280&gmt_create=2014-11-11+17%3A58%3A50&notify_type=trade_status_sync&quantity=1&out_trade_no=R990240665&seller_id=2088611493982911&notify_time=2014-11-11+17%3A59%3A23&body=%5B%22KOSE%E9%AB%98%E4%B8%9D%E9%9B%AA%E8%82%8C%E7%B2%BE%E6%B4%97%E9%A2%9C%E4%B9%B3%22%5D&trade_status=TRADE_SUCCESS&is_total_fee_adjust=N&total_fee=1.43&gmt_payment=2014-11-11+17%3A59%3A23&seller_email=acct-ali%40shiguangcaibei.com&price=1.43&buyer_id=2088902582208882&notify_id=1d583bc9cf21ed879bcd428fd53ed5e16w&use_coupon=N&sign_type=MD5&sign=0962daa33f5390600d9ebd053ef07506
END_POST
  end
end
