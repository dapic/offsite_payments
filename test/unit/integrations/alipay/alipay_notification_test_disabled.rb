require 'test_helper'

class AlipayNotificationTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    @alipay = Alipay::Notification.new(http_raw_data, :credential2 => "test", version: 7)
  end

  def test_accessors
    assert @alipay.complete?
    assert_equal "000", @alipay.status
    assert_equal "4262", @alipay.transaction_id
    assert_equal "1353061158", @alipay.item_id
    assert_equal "1.23", @alipay.gross
    assert_equal "DKK", @alipay.currency
    assert_equal Time.parse("2012-11-16 10:19:36+00:00"), @alipay.received_at
  end

  def test_compositions
    assert_equal Money.new(123, 'DKK'), @alipay.amount
  end

  def test_acknowledgement
    assert @alipay.acknowledge
  end

  def test_failed_acknnowledgement
    @alipay = Alipay::Notification.new(http_raw_data, :credential2 => "badmd5string")
    assert !@alipay.acknowledge
  end

  def test_alipay_attributes
    assert_equal "1", @alipay.state
    assert_equal "authorize", @alipay.msgtype
  end

  def test_generate_md5string
    assert_equal "authorize1353061158123DKK2012-11-16T10:19:36+00:001000OK000OKMerchant #1merchant1@pil.dk4262dankortXXXXXXXXXXXX999910test",
                 @alipay.generate_md5string
  end

  def test_generate_md5check
    assert_equal "7caa0df7d17085206af135ed70d22cc9", @alipay.generate_md5check
  end

  def test_respond_to_acknowledge
    assert @alipay.respond_to?(:acknowledge)
  end

  private
  def http_raw_data
    <<-END_POST

END_POST
  end
end
