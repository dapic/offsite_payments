require 'test_helper'

class TenpayHelperTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    @helper = Tenpay::Helper.new('R710881279_XWE4TKU6', fixtures(:tenpay)[:partner], key: fixtures(:tenpay)[:partner_key])
      @helper.charset = 'utf-8'
      @helper.total_fee = '275'
      @helper.notify_url = 'http://test.shiguangcaibei.com/tenpay_checkout/notify'
      @helper.return_url = 'http://test.shiguangcaibei.com/tenpay_checkout/done'
      @helper.remote_ip = '106.2.199.16'
      @helper.body = 'KOSE高丝雪肌精洗颜乳'
      @helper.sign_type = 'MD5'
    @helper.sign
  end

  def test_signed_string
    assert_equal 'bank_type=DEFAULT&body=KOSE高丝雪肌精洗颜乳&fee_type=1&input_charset=utf-8&notify_url=http://test.shiguangcaibei.com/tenpay_checkout/notify&out_trade_no=R710881279_XWE4TKU6&partner=1223440201&return_url=http://test.shiguangcaibei.com/tenpay_checkout/done&sign_type=MD5&spbill_create_ip=106.2.199.16&total_fee=275&key=1f4eb43196789e61710761ba4f08bee7', Tenpay.signed_string(@helper.form_fields, fixtures(:tenpay)[:partner_key])
  end

  def test_signing_parameters
    #@helper.sign
    assert_equal 'MD5', @helper.form_fields['sign_type']
    assert_equal 'BCCC63541164CA8C52205FA374B2E5A8', @helper.form_fields['sign']
  end

  def test_generate_redirect_url
    #@helper.sign
    assembled_url = URI.parse(OffsitePayments::Integrations::Tenpay.service_url)
    assembled_url.query = ( Rack::Utils.parse_nested_query(assembled_url.query).merge(@helper.form_fields) ).sort.collect{|s|s[0]+"="+CGI.escape(s[1])}.join('&')
    actual_url=URI.parse('https://gw.tenpay.com/gateway/pay.htm?bank_type=DEFAULT&body=KOSE%E9%AB%98%E4%B8%9D%E9%9B%AA%E8%82%8C%E7%B2%BE%E6%B4%97%E9%A2%9C%E4%B9%B3&fee_type=1&input_charset=utf-8&notify_url=http%3A%2F%2Ftest.shiguangcaibei.com%2Ftenpay_checkout%2Fnotify&out_trade_no=R710881279_XWE4TKU6&partner=1223440201&return_url=http%3A%2F%2Ftest.shiguangcaibei.com%2Ftenpay_checkout%2Fdone&sign=BCCC63541164CA8C52205FA374B2E5A8&sign_type=MD5&spbill_create_ip=106.2.199.16&total_fee=275')
    assert_equal assembled_url.query, actual_url.query
    assert_equal actual_url, assembled_url
    #assert_equal 'https://gw.tenpay.com/gateway/pay.htm?bank_type=DEFAULT&body=KOSE%E9%AB%98%E4%B8%9D%E9%9B%AA%E8%82%8C%E7%B2%BE%E6%B4%97%E9%A2%9C%E4%B9%B3&fee_type=1&input_charset=utf-8&notify_url=http%3A%2F%2Ftest.shiguangcaibei.com%2Ftenpay_checkout%2Fnotify&out_trade_no=R710881279_XWE4TKU6&partner=1223440201&return_url=http%3A%2F%2Ftest.shiguangcaibei.com%2Ftenpay_checkout%2Fdone&sign=8a84b9a6d4353cbe887eb2f8cfd16343&sign_type=MD5&spbill_create_ip=106.2.199.16&total_fee=275', url.to_s
  end

end
