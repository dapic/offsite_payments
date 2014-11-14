require 'test_helper'

class AlipayModuleTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    @helper = Alipay::Helper.new('R231325061', fixtures(:alipay)[:pid], fixtures(:alipay))
      @helper.charset = 'utf-8'
      @helper.total_fee = '327.0'
      @helper.service = 'create_direct_pay_by_user'
      #@helper.notify_url = 'http://test.shiguangcaibei.com:3000/alipay_checkout/notify'
      #@helper.return_url = 'http://test.shiguangcaibei.com:3000/alipay_checkout/done'
      @helper.notify_url = 'http://test.shiguangcaibei.com/alipay_checkout/notify'
      @helper.return_url = 'http://test.shiguangcaibei.com/alipay_checkout/done'
      @helper.payment_type = 1
      @helper.subject = '订单编号:R231325061'
      @helper.body = '["补水面膜"]'
  end

  def test_generate_signed_string
    assert_equal '_input_charset=utf-8&body=["补水面膜"]&notify_url=http://test.shiguangcaibei.com/alipay_checkout/notify&out_trade_no=R231325061&partner=2088002627298374&payment_type=1&return_url=http://test.shiguangcaibei.com/alipay_checkout/done&seller_email=areq22@aliyun.com&service=create_direct_pay_by_user&subject=订单编号:R231325061&total_fee=327.0f4y25qc539qakg734vn2jpqq6gmybxoz', Alipay.signed_string(@helper.form_fields, _key)
    #assert_equal '_input_charset=utf-8&body=["补水面膜"]&notify_url=http://test.shiguangcaibei.com:3000/alipay_checkout/notify&out_trade_no=R300075000&partner=2088002627298374&payment_type=1&return_url=http://test.shiguangcaibei.com:3000/alipay_checkout/done&seller_email=areq22@aliyun.com&service=create_direct_pay_by_user&subject=订单编号:R300075000&total_fee=1.37f4y25qc539qakg734vn2jpqq6gmybxoz', Alipay.signed_string(@helper.form_fields, fixtures(:alipay)[:key])
  end

  def test_generate_param_sign
    @helper.add_field('sign_type', 'MD5')
    assert_equal "24e26a396606aee7719a93a6f4e24e85", Alipay.generate_signature(@helper.form_fields, _key)
  end

  def test_raise_error_when_fields_do_not_contain_sign_type
    assert_raise_with_message(OffsitePayments::ActionViewHelperError, /'sign_type' must be specified/)  { Alipay.generate_signature(@helper.form_fields, _key) }
  end
  
  private 

  def _key
    fixtures(:alipay)[:key]
  end
end
