require 'test_helper'
require 'logger'
class WxpayHelperTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    Wxpay.credentials = fixtures(:wxpay)
    Wxpay.logger = Logger.new(STDOUT)
    Wxpay.logger.level == Logger::ERROR
  end

  def test_unified_order_response_success
    @response = mock()
    @response.stubs(:body).returns(unified_order_response_success) 
    @resp = Wxpay::ApiResponse.parse_response(:unifiedorder, @response)
    assert @resp.comm_success?
    assert @resp.biz_success?
    assert_equal 'weixin://wxpay/bizpayurl?sr=tVLUP6i', @resp.pay_url
    assert_equal 'weixin://wxpay/bizpayurl?sr=tVLUP6i', @resp.code_url
  end

  def test_unified_order_response_failure1
    @response = mock()
    @response.stubs(:body).returns(unified_order_response_failure1) 
    @resp = Wxpay::ApiResponse.parse_response(:unifiedorder, @response)
    assert_false @resp.comm_success?
  end

  def test_unified_order_response_orderpaid
    @response = mock()
    @response.stubs(:body).returns(unified_order_response_orderpaid) 
    @resp = Wxpay::ApiResponse.parse_response(:unifiedorder, @response)
    assert @resp.comm_success?
    assert_false @resp.biz_success?
    assert_equal '该订单已支付', @resp.biz_failure_desc
    assert_equal 'ORDERPAID', @resp.biz_failure_code
  end

  private

  def unified_order_response_failure1
    '<xml>
     <return_code><![CDATA[FAIL]]></return_code>
     <return_msg><![CDATA[missing parameter]]></return_msg>
     </xml>'
  end

  def unified_order_response_success
    '<xml><return_code><![CDATA[SUCCESS]]></return_code>
    <return_msg><![CDATA[OK]]></return_msg>
    <appid><![CDATA[wx599b0e05f1873032]]></appid>
    <mch_id><![CDATA[10011924]]></mch_id>
    <nonce_str><![CDATA[gHnTo0kDg56P0Y6T]]></nonce_str>
    <sign><![CDATA[0CC413034094AB3A5F926CA4644550FF]]></sign>
    <result_code><![CDATA[SUCCESS]]></result_code>
    <prepay_id><![CDATA[wx20141125175855641523fd940589543551]]></prepay_id>
    <trade_type><![CDATA[NATIVE]]></trade_type>
    <code_url><![CDATA[weixin://wxpay/bizpayurl?sr=tVLUP6i]]></code_url>
    </xml>'
  end

  def unified_order_response_orderpaid
    '<xml><return_code><![CDATA[SUCCESS]]></return_code>
    <return_msg><![CDATA[OK]]></return_msg>
    <appid><![CDATA[wx599b0e05f1873032]]></appid>
    <mch_id><![CDATA[10011924]]></mch_id>
    <nonce_str><![CDATA[b7WLYKWYwAoojxha]]></nonce_str>
    <sign><![CDATA[C741CB67983D7D057CA31EA55C3293EE]]></sign>
    <result_code><![CDATA[FAIL]]></result_code>
    <err_code><![CDATA[ORDERPAID]]></err_code>
    <err_code_des><![CDATA[该订单已支付]]></err_code_des>
    </xml>'
  end
end
