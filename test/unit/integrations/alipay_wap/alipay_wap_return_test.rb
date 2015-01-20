require 'test_helper'
require 'pp'
require 'cgi'
class AlipayWapReturnTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    @alipay = AlipayWap::Return.new(http_raw_data.chomp, ignore_signature_check: true)
  end

  def test_parsed_data
    assert @alipay.success?
    assert_equal 'success', @alipay.request_fields['result']
    assert_equal '1320742949342', @alipay.request_fields['out_trade_no']
    assert_equal '2011110823389231', @alipay.request_fields['trade_no']
    assert_equal '201008309e298cf01c58146274208eda1e4cdf2b', @alipay.request_fields['request_token']
    assert_equal '49a330fee069465c64e561a25bf31c78', @alipay.request_fields['sign']
    assert_nil @alipay.request_fields['sec_id']
  end

  def test_attributes
    assert_equal '201008309e298cf01c58146274208eda1e4cdf2b', @alipay.request_token

  end

  def test_respond_to_acknowledge
    assert @alipay.respond_to?(:acknowledge)
  end

  private
  def http_raw_data
    <<-END_POST
out_trade_no=1320742949342&request_token=201008309e298cf01c58146274208eda1e4cdf2b&result=success&trade_no=2011110823389231&sign=49a330fee069465c64e561a25bf31c78
    END_POST
  end
end
