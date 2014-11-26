require 'test_helper'

class AlipayHelperTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    @helper = Alipay::Helper.new('R231325061', fixtures(:alipay)[:pid], fixtures(:alipay))
      @helper.charset = 'utf-8'
      @helper.total_fee = '327.0'
      @helper.service = 'create_direct_pay_by_user'
      @helper.notify_url = 'http://test.shiguangcaibei.com/alipay_checkout/notify'
      @helper.return_url = 'http://test.shiguangcaibei.com/alipay_checkout/done'
      @helper.payment_type = 1
      @helper.subject = '订单编号:R231325061'
      @helper.body = '["补水面膜"]'
  end

  def test_signing_parameters
    @helper.sign
    assert_equal 'MD5', @helper.form_fields['sign_type']
    assert_equal '24e26a396606aee7719a93a6f4e24e85', @helper.form_fields['sign']
  end

  def test_generate_redirect_url
    assert_equal 'https://mapi.alipay.com/gateway.do?_input_charset=utf-8&body=%5B%22%E8%A1%A5%E6%B0%B4%E9%9D%A2%E8%86%9C%22%5D&notify_url=http%3A%2F%2Ftest.shiguangcaibei.com%2Falipay_checkout%2Fnotify&out_trade_no=R231325061&partner=2088002627298374&payment_type=1&return_url=http%3A%2F%2Ftest.shiguangcaibei.com%2Falipay_checkout%2Fdone&seller_email=areq22%40aliyun.com&service=create_direct_pay_by_user&sign=24e26a396606aee7719a93a6f4e24e85&sign_type=MD5&subject=%E8%AE%A2%E5%8D%95%E7%BC%96%E5%8F%B7%3AR231325061&total_fee=327.0', @helper.redirect_url.to_s
  end
end
