require 'test_helper'

class AlipayWapNotificationTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    @alipay = AlipayWap::Notification.new(http_raw_data.strip, key: fixtures(:alipay)[:key])
  end

  def test_parsed_data
    assert_equal 'dinglang@a.com', @alipay.payload_fields['buyer_email']
    assert_equal '收银台{1283134629741}',@alipay.payload_fields['subject']
    assert_equal '509ad84678759176212c247c46bec05303',@alipay.payload_fields['notify_id']

  end

  def test_parse_data_sgcb
    @notify = AlipayWap::Notification.new(http_raw_data_sgcb.strip, key: fixtures(:'alipay-sgcb')[:key])
    puts @notify.protocol_fields['sign']
    @notify.acknowledge
  rescue StandardError => e
    if e.message.match /No fixture data was found/
      puts " WARN: testing with sgcb credentials skipped because the credentials are not found in fixtures"
    else
      raise e
    end
  end

  def test_attributes
    assert @alipay.success?
    assert_equal 'TRADE_FINISHED', @alipay.status
    assert_equal Money.new(100, 'CNY'), @alipay.amount
    assert_equal '2010083000136835', @alipay.transaction_id
  end

  private
  def http_raw_data
    <<-END_POST
http://www.xxx.com/alipay/notify_url.php?service=alipay.wap.trade.create.direct%20&sign=Rw/y4ROnNicXhaj287Fiw5pvP6viSyg53H3iNiJ61D3YVi7zGniG2680pZv6rakMCeXX++q9XRLw8Rj6I1//qHrwMAHS1hViNW6hQYsh2TqemuL/xjXRCY3vjm1HCoZOUa5zF2jU09yG23MsMIUx2FAWCL/rgbcQcOjLe5FugTc=&v=2.0&sec_id=MD5&notify_data=%3Cnotify%3E%3Cpayment_type%3E1%3C/payment_type%3E%3Csubject%3E%E6%94%B6%E9%93%B6%E5%8F%B0{1283134629741}%3C/subject%3E%3Ctrade_no%3E2010083000136835%3C/trade_no%3E%3Cbuyer_email%3Edinglang@a.com%3C/buyer_email%3E%3Cgmt_create%3E2010-08-3010:17:24%3C/gmt_create%3E%3Cnotify_type%3Etrade_status_sync%3C/notify_type%3E%3Cquantity%3E1%3C/quantity%3E%3Cout_trade_no%3E1283134629741%3C/out_trade_no%3E%3Cnotify_time%3E2010-08-3010:18:15%3C/notify_time%3E%3Cseller_id%3E2088101000137799%3C/seller_id%3E%3Ctrade_status%3ETRADE_FINISHED%3C/trade_status%3E%3Cis_total_fee_adjust%3EN%3C/is_total_fee_adjust%3E%3Ctotal_fee%3E1.00%3C/total_fee%3E%3Cgmt_payment%3E2010-08-3010:18:26%3C/gmt_payment%3E%3Cseller_email%3Echenf003@yahoo.cn%3C/seller_email%3E%3Cgmt_close%3E2010-08-3010:18:26%3C/gmt_close%3E%3Cprice%3E1.00%3C/price%3E%3Cbuyer_id%3E2088102001172352%3C/buyer_id%3E%3Cnotify_id%3E509ad84678759176212c247c46bec05303%3C/notify_id%3E%3Cuse_coupon%3EN%3C/use_coupon%3E%3C/notify%3E
    END_POST
  end

  def http_raw_data_sgcb
    <<-END_POST
    service=alipay.wap.trade.create.direct&sign=e9a155caf000f2991746b55100c35126&sec_id=MD5&v=1.0&notify_data=%3Cnotify%3E%3Cpayment_type%3E1%3C%2Fpayment_type%3E%3Csubject%3E%E8%AE%A2%E5%8D%95%E7%BC%96%E5%8F%B7%3AR580612622%3C%2Fsubject%3E%3Ctrade_no%3E2015012104931488%3C%2Ftrade_no%3E%3Cbuyer_email%3E18611543280%3C%2Fbuyer_email%3E%3Cgmt_create%3E2015-01-21+02%3A48%3A23%3C%2Fgmt_create%3E%3Cnotify_type%3Etrade_status_sync%3C%2Fnotify_type%3E%3Cquantity%3E1%3C%2Fquantity%3E%3Cout_trade_no%3ER580612622_S9KZGESX%3C%2Fout_trade_no%3E%3Cnotify_time%3E2015-01-21+02%3A48%3A37%3C%2Fnotify_time%3E%3Cseller_id%3E2088611493982911%3C%2Fseller_id%3E%3Ctrade_status%3ETRADE_SUCCESS%3C%2Ftrade_status%3E%3Cis_total_fee_adjust%3EN%3C%2Fis_total_fee_adjust%3E%3Ctotal_fee%3E0.14%3C%2Ftotal_fee%3E%3Cgmt_payment%3E2015-01-21+02%3A48%3A37%3C%2Fgmt_payment%3E%3Cseller_email%3Eacct-ali%40shiguangcaibei.com%3C%2Fseller_email%3E%3Cprice%3E0.14%3C%2Fprice%3E%3Cbuyer_id%3E2088902582208882%3C%2Fbuyer_id%3E%3Cnotify_id%3E42adf1e8bdc232cf012f0add0c756cb56w%3C%2Fnotify_id%3E%3Cuse_coupon%3EN%3C%2Fuse_coupon%3E%3C%2Fnotify%3E
    END_POST
  end
end
