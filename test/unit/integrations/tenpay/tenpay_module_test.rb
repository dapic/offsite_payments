require 'test_helper'

class TenpayModuleTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def test_notification_method
    assert_instance_of Tenpay::Notification, Tenpay.notification('bank_type=BL&discount=0&fee_type=1&input_charset=utf-8&notify_id=Uvw12OtEhcWJOWrI_h5vddwwlJcJ2HgiLo7E88Rnsvt9FFfaFT3u5xV9ljcC9l_g0ur0ecJY3Ynru9aMFcGAfED4RMq9vxc5&out_trade_no=R710881279_XWE4TKU6&partner=1223440201&product_fee=275&sign_type=MD5&time_end=20141117154007&total_fee=275&trade_mode=1&trade_state=0&transaction_id=1223440201201411170032328302&transport_fee=0&sign=F9F83A48044D25529D82A3E0AFB0BDA3', key: fixtures(:tenpay)[:partner_key])
  end
end
