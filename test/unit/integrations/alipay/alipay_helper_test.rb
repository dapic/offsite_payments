require 'test_helper'

class AlipayHelperTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    @helper = Alipay::Helper.new('R300075000', fixtures(:alipay)[:pid], fixtures(:alipay))
      @helper.charset = 'utf-8'
      @helper.total_fee = '1.37'
      @helper.service = 'create_direct_pay_by_user'
      @helper.notify_url = 'http://test.shiguangcaibei.com:3000/alipay_checkout/notify'
      @helper.return_url = 'http://test.shiguangcaibei.com:3000/alipay_checkout/done'
      @helper.payment_type = 1
      @helper.subject = '订单编号:R300075000'
      @helper.body = '["补水面膜"]'
  end

  def test_generate_signed_string
    #assert_equal "f814a8667c925f9b82506c32b522f0a3", @helper.create_sign
    assert_equal '_input_charset=utf-8&body=["补水面膜"]&notify_url=http://test.shiguangcaibei.com:3000/alipay_checkout/notify&out_trade_no=R300075000&partner=2088002627298374&payment_type=1&return_url=http://test.shiguangcaibei.com:3000/alipay_checkout/done&seller_email=areq22@aliyun.com&service=create_direct_pay_by_user&subject=订单编号:R300075000&total_fee=1.37f4y25qc539qakg734vn2jpqq6gmybxoz', @helper.signed_string
  end

  def test_generate_param_sign
    #assert_equal "f814a8667c925f9b82506c32b522f0a3", @helper.create_sign
    assert_equal "c1c21524cb089b4d7ea33f20687873d8", @helper.create_sign
  end

  def test_generate_redirect_url
    #assert_equal 'https://mapi.alipay.com/gateway.do?_input_charset=utf-8&out_trade_no=R300075000&partner=2088611493982911&seller_email=acct-ali%40shiguangcaibei.com&total_fee=122.0&service=create_direct_pay_by_user&notify_url=http%3A%2F%2Ftest.shiguangcaibei.com%3A3000%2Falipay_checkout%2Fnotify&return_url=http%3A%2F%2Ftest.shiguangcaibei.com%3A3000%2Falipay_checkout%2Fdone&payment_type=1&subject=%E8%AE%A2%E5%8D%95%E7%BC%96%E5%8F%B7%3AR300075000&body=%5B%22%E8%A1%A5%E6%B0%B4%E9%9D%A2%E8%86%9C%22%5D&sign=f814a8667c925f9b82506c32b522f0a3&sign_type=MD5', @helper.redirect_url.to_s
    assert_equal 'https://mapi.alipay.com/gateway.do?_input_charset=utf-8&out_trade_no=R300075000&partner=2088002627298374&seller_email=areq22%40aliyun.com&total_fee=1.37&service=create_direct_pay_by_user&notify_url=http%3A%2F%2Ftest.shiguangcaibei.com%3A3000%2Falipay_checkout%2Fnotify&return_url=http%3A%2F%2Ftest.shiguangcaibei.com%3A3000%2Falipay_checkout%2Fdone&payment_type=1&subject=%E8%AE%A2%E5%8D%95%E7%BC%96%E5%8F%B7%3AR300075000&body=%5B%22%E8%A1%A5%E6%B0%B4%E9%9D%A2%E8%86%9C%22%5D&sign=c1c21524cb089b4d7ea33f20687873d8&sign_type=MD5', @helper.redirect_url.to_s
  end

end
