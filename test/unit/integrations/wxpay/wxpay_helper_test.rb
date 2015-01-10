require 'test_helper'
require 'logger'
class WxpayHelperTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    Wxpay.credentials = fixtures(:wxpay)
    Wxpay.logger.level = Logger::ERROR
    @helper = Wxpay::UnifiedOrderHelper.new(fixtures(:'wxpay-sample_data')[:unifiedorder_req])
  end

  def test_wxpay_credentials_not_in_helper_fields
    assert_nil @helper.params['key']
    assert_nil @helper.params['appsecret']
    assert_equal fixtures(:wxpay)[:key], Wxpay.key
    assert_equal fixtures(:wxpay)[:appsecret], Wxpay.appsecret
  end

  def test_credential_fields
    assert_equal fixtures(:wxpay)[:appid], @helper.params['appid']
    assert_equal fixtures(:wxpay)[:mch_id], @helper.params['mch_id']
  end

  def test_setting_nonce_str
    @nonce_str = SecureRandom.hex
    @helper.params['nonce_str'] = @nonce_str 
    assert_equal @nonce_str, @helper.form_fields['nonce_str']
  end

  def test_signed_string_unifiedorder
    @helper.sign
    #assert_equal 'appid=wx599b0e05f1873032&appsecret=1a959cd64a69da949f5519be7d6887ea&body=KOSE高丝雪肌精洗颜乳&mch_id=10011924&nonce_str=63f79862235083c2f010815e1f0546c1&notify_url=http://test.shiguangcaibei.com/payment/wxpay/notify&out_trade_no=R710881279_XWE4TKU6&spbill_create_ip=106.2.199.16&total_fee=275&trade_type=NATIVE&key=1a959cd64a69da949f5519be7d6887ea'.gsub(/&nonce_str=(\w){32}/,"&nonce_str=#{'*'*32}"), Wxpay.signed_string(@helper.form_fields).gsub(/&nonce_str=(\w){32}/,"&nonce_str=#{'*'*32}")
  end

  def test_signing_parameters_unifiedorder
    @helper.params['nonce_str'] = nonce_str
    @helper.sign
    assert_equal '01450D8ED6D80B455C468F18501E2508', @helper.form_fields['sign']
  end

  def test_process_unifiedorder
    #@sample_resp = mock()
    #@sample_resp.stubs(:body).returns(fixtures(:'wxpay-sample_data')[:unifiedorder_resp_success])
    @sample_resp = fixtures(:'wxpay-sample_data')[:unifiedorder_resp_success]
    @helper.expects(:ssl_post).returns(@sample_resp)
    @resp = catch(:done) { @helper.process }
    assert @resp.comm_success?
    assert @resp.biz_success?
    assert_equal 'weixin://wxpay/bizpayurl?sr=tVLUP6i', @resp.pay_url
    assert_equal 'weixin://wxpay/bizpayurl?sr=tVLUP6i', @resp.biz_payload['code_url']
  end

  private
  def nonce_str
    '63f79862235083c2f010815e1f0546c1'
  end
end
