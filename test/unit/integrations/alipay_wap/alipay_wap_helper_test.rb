require 'test_helper'

class AlipayWapHelperTest < Test::Unit::TestCase
  include OffsitePayments::Integrations::AlipayWap

  def setup
    credentials = fixtures(:alipay)
    # changing these so that they match the response sample we got from Alipay docs
    credentials[:pid] = 2088101000137799
    OffsitePayments::Integrations::AlipayWap.credentials = credentials
    @create_direct_req = CreateDirectHelper.new({})
    @create_direct_req.form_fields['req_id'] = 1282889689836
  end

  def test_service_url_access
    assert_equal 'http://wappaygw.alipay.com/service/rest.htm', OffsitePayments::Integrations::AlipayWap.service_url 
  end

  def test_create_create_direct_helper
    @create_direct_req = CreateDirectHelper.new({})
    assert(@create_direct_req.respond_to?(:process))
    assert(@create_direct_req.respond_to?(:parse_response), 'should have "parse_response" method')
  end

  def test_parsing_good_response
    res = CreateDirectResponse.new(direct_trade_create_res, @create_direct_req, true)
    assert_equal '20100830e8085e3e0868a466b822350ede5886e8', res.request_token
  end

  def test_parsing_err_response
    res = CreateDirectResponse.new(direct_trade_create_res_err, @create_direct_req)
    assert_equal '0005', res.error['sub_code']
    assert_equal '合作伙伴没有开通接口访问权限', res.error['detail']
  end

  def test_parsing_invalid_response
    assert_raise_with_message(RuntimeError, /Invalid response format/) { CreateDirectResponse.new(direct_trade_create_res_invalid, @create_direct_req) }
  end

  def direct_trade_create_res
    'partner=2088101000137799&req_id=1282889689836&res_data=<?xml version="1.0" encoding="utf-8"?><direct_trade_create_res><request_token>20100830e8085e3e0868a466b822350ede5886e8</request_token></direct_trade_create_res>&sec_id=MD5&service=alipay.wap.trade.create.direct&v=2.0&sign=72a64fb63f0b54f96b10cefb69319e8a'
  end

  def direct_trade_create_res_err
    'partner=2088101000137799&req_id=1282889689836&res_error=<?xml version="1.0" encoding="utf-8"?><err><code>0005</code><sub_code>0005</sub_code><msg>partner illegal</msg><detail>合作伙伴没有开通接口访问权限 </detail></err>&sec_id=0001&service=alipay.wap.trade.create.direct&v=2.0'
  end

  def direct_trade_create_res_invalid
    'partner=2088101000137799&req_id=1282889689836&res_err=<?xml version="1.0" encoding="utf-8"?><err><code>0005</code><sub_code>0005</sub_code><msg>partner illegal</msg><detail>合作伙伴没有开通接口访问权限 </detail></err>&sec_id=0001&service=alipay.wap.trade.create.direct&v=2.0'
  end

end
