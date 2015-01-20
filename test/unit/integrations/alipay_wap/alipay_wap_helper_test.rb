require 'test_helper'

class AlipayWapHelperTest < Test::Unit::TestCase
  include OffsitePayments::Integrations::AlipayWap

  def setup
    credentials = fixtures(:alipay)
    # changing these so that they match the response sample we got from Alipay docs
    credentials[:pid] = 2088101000137799
    OffsitePayments::Integrations::AlipayWap.credentials = credentials
    @create_direct_req = CreateDirectHelper.new({})
    @create_direct_req.protocol_fields['req_id'] = 1282889689836
  end

  def test_service_url_access
    assert_equal 'http://wappaygw.alipay.com/service/rest.htm', OffsitePayments::Integrations::AlipayWap.service_url
  end

  def test_create_direct_helper_payload
    payload = CreateDirectHelper.new({}).post_payload
    assert_match(/format=xml&partner=2088101000137799&/, payload)
    assert_match /format=xml&partner=2088101000137799&req_data=%3Cdirect_trade_create_req%3E%3Cseller_account_name%3Eareq22%40aliyun.com%3C%2Fseller_account_name%3E%3C%2Fdirect_trade_create_req%3E&req_id=\w{32}&sec_id=MD5&service=alipay.wap.trade.create.direct&sign=\w{32}&v=2.0/, payload
  end

  def test_create_create_direct_helper
    @create_direct_req = CreateDirectHelper.new({})
    assert(@create_direct_req.respond_to?(:process))
    assert(@create_direct_req.respond_to?(:parse_response), 'should have "parse_response" method')
    assert_not_nil(@create_direct_req.protocol_fields['sign'])
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

  def test_parsing_good_response_sgcb
    OffsitePayments::Integrations::AlipayWap.credentials = fixtures(:'alipay-sgcb')
    helper = CreateDirectHelper.new(payload)
    helper.protocol_fields['req_id'] = 'b739e406fb08ddda1fd7265921244f17'
    res = CreateDirectResponse.new(direct_trade_create_res_sgcb, helper)
  rescue StandardError => e
    if e.message.match /No fixture data was found/
      puts " WARN: testing with sgcb credentials skipped because the credentials are not found in fixtures"
    else
      raise e
    end
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

  def direct_trade_create_res_sgcb
    'res_data=%3C%3Fxml+version%3D%221.0%22+encoding%3D%22utf-8%22%3F%3E%3Cdirect_trade_create_res%3E%3Crequest_token%3E20150120130ffba6bdaa70686d35bbb81370eae2%3C%2Frequest_token%3E%3C%2Fdirect_trade_create_res%3E&service=alipay.wap.trade.create.direct&sec_id=MD5&partner=2088611493982911&req_id=b739e406fb08ddda1fd7265921244f17&sign=462221f9d5d197344b4054f4b282545c&v=2.0'
  end

  def payload
    {
        subject: "订单编号:order_id_12345",
        out_trade_no: 'R9991235_A8X9FE',
        total_fee: '1.21',
        seller_account_name: 'acct-ali@shiguangcaibei.com',
        call_back_url: 'http://test.shiguangcaibei.com/payment/alipay_wap/return',
        notify_url: 'http://test.shiguangcaibei.com/payment/alipay_wap/notify',
        out_user: 'user_id_123',
        merchant_url: 'test.shiguangcaibei.com',
        pay_expire: 3600.to_s,
    }
  end
end
