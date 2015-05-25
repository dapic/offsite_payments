# encoding: utf-8
require 'openssl'
require 'base64'
module OffsitePayments #:nodoc:
  module Integrations #:nodoc:
    module Unionpay

      mattr_accessor :service_url, :credentials, :options
      mattr_writer :logger

      # this should be modified when initializing the Unionpay module
      self.service_url = 'https://101.231.204.80:5000/gateway/api/frontTransReq.do'

      def self.notification(post, options = {})
        Notification.new(post, options)
      end

      def self.return(post, options = {})
        Return.new(post, options)
      end

      def self.logger
        @@logger ||= Logger.new(STDOUT)
      end

      module Common
        COMMUNICATION_PROTOCOL_FIELDS =
            {
                'version' => '5.0.0', #版本号
                'encoding' => 'utf-8', #编码方式
                'signMethod' => '01', #签名方法 01表示RSA
            }

        def logger
          Unionpay.logger
        end

      end

      module CredentialHelper
        # :key_file must be a ".pem" file, not a '.pfx' file
        def merchant_private_key
          @merchant_private_key ||= OpenSSL::PKey::RSA.new(
              File.read(Unionpay.credentials[:merchant_pem_file])
          )
        end

        def merchant_certificate
          @merchant_certificate ||= OpenSSL::X509::Certificate.new(
              File.read(Unionpay.credentials[:merchant_pem_file])
          )
        end

        def merchant_id
          Unionpay.credentials[:merchant_id];
        end

        def merchant_certificate_id
          merchant_certificate.serial.to_s
        end

        def certificate_password
          Unionpay.credentials[:cert_password]
        end
      end

      module SignatureProcessor
        FIELDS_NOT_TO_BE_SIGNED = 'signature'

        def sign
          add_field 'signature', generate_signature
          nil
        end

        private

        # Generate the required signature as specified by unionpay official document
        # it returns the signature string
        def generate_signature
          sha1x16 = Digest::SHA1.hexdigest(signed_string)
                        .tap { |s| logger.debug "sha1x16 #{s}" }
          enc = case form_fields['signMethod']
                  when '01' # 01 means RSA
                    merchant_private_key.sign(OpenSSL::Digest::SHA1.new, sha1x16)
                        .tap { |s| logger.debug "enc  #{s}" }
                  else # at current time (2015-05-25) no other signing method is mentioned in Unionpay's official docs
                    raise "sign method #{form_fields['signMethod']} is not implemented yet."
                end
          Base64.strict_encode64(enc) # has to be strict_encode64, not encode64, as the lattter as an extra '\n'
              .tap { |s| logger.debug "final:  #{s}" }
        end

        # Generate the string to sign on from all in from_fields.
        # Currently Unionpay doc specifies that the fields are arranged alphabetically
        def signed_string
          signed_data_only = form_fields.reject { |s| FIELDS_NOT_TO_BE_SIGNED.include?(s) }
          signed_data_only.sort.collect { |s| "#{s[0]}=#{s[1]}" }.join('&')
              .tap { |ss| logger.debug "signed string is #{ss}" }
        end

      end

      class Helper < OffsitePayments::Helper
        include Common
        include CredentialHelper
        include SignatureProcessor
        BIZ_PROTOCOL_STATIC_FIELDS = {
            'txnType' => '01', #交易类型
            'txnSubType' => '01', #交易子类
            'bizType' => '000201', #业务类型, 'B2C网关支付'
            'accessType' => '0', #接入类型 0为商户直连
            'currencyCode' => '156', #交易币种
        }

        mapping :order, 'orderId' #商户订单号，我们应该用out_trade_no
        mapping :account, 'merId'
        mapping :order_time, 'txnTime'
        mapping :total_fee, 'txnAmt' #单位，分
        mapping :return_url, 'frontUrl'
        mapping :notify_url, 'backUrl'
        mapping :channel_type, 'channelType' #渠道类型，07-PC，08-手机
        mapping :reserved_msg, 'reqReserved' # 请求方保留域，透传字段，查询、通知、对账文件中均会原样出现

        def initialize(order, account, options = {})
          super
          add_field 'certId', merchant_certificate_id
        end

        def form_fields
          Common::COMMUNICATION_PROTOCOL_FIELDS
              .merge(BIZ_PROTOCOL_STATIC_FIELDS)
              .merge(fields)
        end
      end

      # for both notify and return
      module CommonIncoming
        def acknowledge
          verify_signature || raise(SecurityError, "Invalid Unionpay HTTP signature in #{self.class}")
        end

        def signature
          params['signature']
        end

        def status
          params['respCode']
        end

        def gross
          Money.new(params['txnAmt'].to_i, currency)
        end

        def currency
          Money::Currency.find_by_iso_numeric params['currencyCode'] || 'CNY'
        end

        def message
          signed_string
        end

        def success?
          '00' == status
        end

        # Return and Notify do not have 'form_fields' defined yet it's needed for the signed_string method
        def form_fields
          params
        end

        def transaction_id
          params['queryId']
        end

        def out_trade_no
          params['orderId']
        end

        private

        def has_all_required_fields?
          !self.class.const_defined?(:REQUIRED_FIELDS) || self.class::REQUIRED_FIELDS.all? { |f| params[f].present? }
        end

        def verify_signature
          sha1x16 = Digest::SHA1.hexdigest(signed_string)

          logger.debug("verifying signature #{signature} #{sha1x16} with certId #{certificate_id}")
          pub_key.verify(OpenSSL::Digest::SHA1.new, Base64.decode64(signature), sha1x16)
        end

        def pub_key
          public_certificates[certificate_id].public_key
        end

        def public_certificates
          @pub_certs ||= Dir[File.join(Unionpay.credentials[:certificates_path], '*.cer')]
                             .inject({}) { |h, cert_file|
            cert = OpenSSL::X509::Certificate.new(File.read(cert_file))
            h[cert.serial.to_s] = cert
            h
          }
        end

        def certificate_id
          params['certId']
        end

      end

      class Return < OffsitePayments::Return
        REQUIRED_FIELDS = %w(certId signature signMethod txnType txnSubType bizType accessType merId orderId txnTime txnAmt currencyCode queryId respCode respMsg)
        include Common
        include CredentialHelper
        include SignatureProcessor
        include CommonIncoming

        def initialize(post, options = {})
          super
          raise "Not valid Unionpay #{self.class}" unless has_all_required_fields?
        end
      end

      class Notifiction < OffsitePayments::Notification
        REQUIRED_FIELDS = %w(certId signature signMethod txnType txnSubType bizType accessType merId orderId txnTime txnAmt currencyCode reqReserved queryId respCode respMsg settleAmt settleCurrencyCode settleDate traceNo traceTime)

        include CommonIncoming

        def initialize(post, options = {})
          super
          raise "Not valid Unionpay #{self.class}" unless has_all_required_fields?
        end
      end
    end
  end
end
