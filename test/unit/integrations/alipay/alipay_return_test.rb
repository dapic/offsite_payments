require 'test_helper'
require 'pp'
require 'cgi'
class AlipayReturnTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    begin
      @key = fixtures(:'alipay-sgcb')[:key]
      @alipay = Alipay.return(http_query_string_sgcb, key: @key)
    rescue StandardError => e
      raise e unless e.message.match /No fixture data was found/
      @key = fixtures(:alipay)[:key]
      @alipay = Alipay.return(http_query_string, key: @key)
    end
  end

  def test_accessors
    assert @alipay.is_payment_complete?
    assert_equal "trade_status_sync", @alipay.notify_type
    assert_equal "2014111159601788", @alipay.trade_no
    assert_equal "R990240665", @alipay.out_trade_no
    assert_equal true, @alipay.is_success?
    assert_equal "1", @alipay.payment_type
    assert_equal "2088611493982911", @alipay.seller_id
    assert_equal "acct-ali@shiguangcaibei.com", @alipay.seller_email
    assert_equal false, @alipay.is_total_fee_adjust?
    assert_equal "1.43", @alipay.total_fee

    assert_equal "订单编号:R990240665", @alipay.subject
    assert_equal '["KOSE高丝雪肌精洗颜乳"]', @alipay.body
    assert_equal Time.parse("2014-11-11 17:59:28"), @alipay.notify_time
    assert_equal "2088902582208882", @alipay.buyer_id
    assert_equal "18611543280", @alipay.buyer_email
    assert_equal "RqPnCoPT3K9%252Fvwbh3InQ8703uAICbLI7SGaz7f3Qe96t7vC6a1YKnYuOZTls2t9kw%252F6z", @alipay.notify_id
    assert_equal false, @alipay.use_coupon?
  end

  def test_acknowledgement
    assert @alipay.acknowledge
  end

  def test_raise_error_with_unsupported_sign_type
    @alipay = Alipay::Return.new(http_query_string.gsub('MD5','DSA'), key: @key)
    assert_raise_with_message(OffsitePayments::ActionViewHelperError, /not yet supported/) { @alipay.acknowledge}
  end

  def test_raise_error_when_acknowledge_fails
    @alipay = Alipay::Return.new(http_query_string, key: "badmd5string")
    assert_raise_with_message(OffsitePayments::ActionViewHelperError, "Invalid Alipay HTTP signature")  { @alipay.acknowledge }
  end
  
  def test_respond_to_acknowledge
    assert @alipay.respond_to?(:acknowledge)
  end
  
  private

  # This string is MODIFIED from real-life production data from Alipay
  # The only change is a new "sign" field generated with the areq22@aliyun.com key
  def http_query_string
    <<-END_POST
body=%5B%22KOSE%E9%AB%98%E4%B8%9D%E9%9B%AA%E8%82%8C%E7%B2%BE%E6%B4%97%E9%A2%9C%E4%B9%B3%22%5D&buyer_email=18611543280&buyer_id=2088902582208882&exterface=create_direct_pay_by_user&is_success=T&notify_id=RqPnCoPT3K9%252Fvwbh3InQ8703uAICbLI7SGaz7f3Qe96t7vC6a1YKnYuOZTls2t9kw%252F6z&notify_time=2014-11-11+17%3A59%3A28&notify_type=trade_status_sync&out_trade_no=R990240665&payment_type=1&seller_email=acct-ali%40shiguangcaibei.com&seller_id=2088611493982911&subject=%E8%AE%A2%E5%8D%95%E7%BC%96%E5%8F%B7%3AR990240665&total_fee=1.43&trade_no=2014111159601788&trade_status=TRADE_SUCCESS&sign=1c3e7b66a6a7e704f0ad2ed0bc25ee04&sign_type=MD5
    END_POST
  .chomp!
  end

  # This string is real-life production data from Alipay, signed with SGCB key
  def http_query_string_sgcb
    <<-END_POST
body=%5B%22KOSE%E9%AB%98%E4%B8%9D%E9%9B%AA%E8%82%8C%E7%B2%BE%E6%B4%97%E9%A2%9C%E4%B9%B3%22%5D&buyer_email=18611543280&buyer_id=2088902582208882&exterface=create_direct_pay_by_user&is_success=T&notify_id=RqPnCoPT3K9%252Fvwbh3InQ8703uAICbLI7SGaz7f3Qe96t7vC6a1YKnYuOZTls2t9kw%252F6z&notify_time=2014-11-11+17%3A59%3A28&notify_type=trade_status_sync&out_trade_no=R990240665&payment_type=1&seller_email=acct-ali%40shiguangcaibei.com&seller_id=2088611493982911&subject=%E8%AE%A2%E5%8D%95%E7%BC%96%E5%8F%B7%3AR990240665&total_fee=1.43&trade_no=2014111159601788&trade_status=TRADE_SUCCESS&sign=a25c543b8b84166f6c5f556c2f229fb1&sign_type=MD5
    END_POST
  .chomp!
  end
  
end
