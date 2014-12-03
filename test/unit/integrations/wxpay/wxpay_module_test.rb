require 'test_helper'
require 'logger'
class WxpayModuleTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    Wxpay.logger = nil
  end

  def test_has_default_implicit_logger
    assert_not_nil Wxpay.logger
  end

  def test_default_logger_is_created_with_default_log_level
    assert_equal Wxpay.logger.level, Logger.new(STDOUT).level
  end
  
  def test_logger_could_be_explicitly_set
    @logger = Logger.new(STDOUT)
    Wxpay.logger = @logger
    Wxpay.logger.level = Logger::DEBUG
    assert_equal Wxpay.logger.object_id, @logger.object_id
    assert_equal Wxpay.logger.level, @logger.level
  end

  def test_key_and_appsecret_in_credentials_removed_from_hash
    Wxpay.credentials = fixtures(:wxpay)
    assert_nil Wxpay.credentials[:key]
    assert_nil Wxpay.credentials[:appsecret]
    assert_equal fixtures(:wxpay)[:key], Wxpay.key
    assert_equal fixtures(:wxpay)[:appsecret], Wxpay.appsecret
  end

  def test_wxpay_credentials_not_in_helper_fields
    @helper = Wxpay::UnifiedOrderHelper.new(fixtures(:'wxpay-sample_data')[:unifiedorder_req])
    assert_nil @helper.params['key']
    assert_nil @helper.params['appsecret']
  end

end
