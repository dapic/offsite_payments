require 'test_helper'

class RemoteAlipayWapTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    @credentials = fixtures(:'alipay-sgcb')
    OffsitePayments::Integrations::AlipayWap.credentials = @credentials
  end

  def tear_down
    OffsitePayments.mode = :test
  end

  def test_create_direct
    @create_direct_req = AlipayWap::CreateDirectHelper.new(payload)
    #@create_direct_req.protocol_fields['req_id'] = 1282889689836.to_s

    assert_nothing_raised do
      res = @create_direct_req.process
      assert_not_nil res.request_token
      # puts res
    end
  end

  def payload
    {
      subject:             "订单编号:order_id_12345",
      out_trade_no:        'R9991235_A8X9FE',
      total_fee:           '1.21',
      seller_account_name: @credentials[:seller][:email],
      call_back_url:       'http://test.shiguangcaibei.com/payment/alipay_wap/return',
      notify_url:          'http://test.shiguangcaibei.com/payment/alipay_wap/notify',
      out_user:            'user_id_123',
      merchant_url:        'test.shiguangcaibei.com',
      pay_expire:          3600.to_s,
  }
  end

end
