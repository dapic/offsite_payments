# encoding: utf-8
require 'openssl'
require 'base64'
module OffsitePayments #:nodoc:
  module Integrations #:nodoc:
    module Unionpay

      mattr_accessor :service_url, :logger, :credentials, :options

      API_CONFIG = {
          front_trans: {helper_type: :FrontTransReqHelper, request_url: 'https://101.231.204.80:5000/gateway/api/frontTransReq.do'},
      }

      def self.notification(post, options = {})
        Notification.new(post, options)
      end

      def self.return(post, options = {})
        Return.new(post, options)
      end

      # Generate the required signature as specified by unionpay official document
      # pkey should be a RSA private key
      # def self.generate_signature(fields, pkey)
      #   enc = pkey.sign(OpenSSL::Digest.SHA1.new, signed_string(fields))
      #   Base64.encode64(enc)
      # end

      def self.logger
        @@logger ||= Logger.new(STDOUT)
      end

      module CredentialHelper
        # :key_file must be a ".pem" file, not a '.pfx' file
        def key
          @key ||= OpenSSL::PKey::RSA.new(File.read(Unionpay.credentials[:key_file]))
        end

        def certificate
          @certificate ||= OpenSSL::X509::Certificate.new(File.read(Unionpay.credentials[:key_file]))
        end

        def merchant_id
          Unionpay.credentials[:merchant_id];
        end

        def certificate_id
          certificate.serial.to_s
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

        # Generate the required signature as specified by unionpay official document
        # pkey should be a RSA private key
        # it returns the signature string
        def generate_signature
          sha1x16 = Digest::SHA1.hexdigest(signed_string).tap{|s| puts "sha1x16 #{s}"}
          enc = key.sign(OpenSSL::Digest::SHA1.new, sha1x16).tap{|s| puts "enc  #{s}"}
          Base64.encode64(enc).tap{|s| puts "final:  #{s}"}
        end

        # Generate the string to sign on from all in @request_fields.
        # Currently Alipay doc specifies that the fields are arranged alphabetically except for data sent to "notify_url"
        def signed_string
          signed_data_only = form_fields.reject { |s| FIELDS_NOT_TO_BE_SIGNED.include?(s) }
          signed_data_only.sort.collect { |s| "#{s[0]}=#{s[1]}" }.join('&')
          .tap{|ss| puts "signed string is #{ss}"}
        end

        def acknowledge
          (request_fields['sign'] == generate_signature) || raise(SecurityError, "Invalid Alipay HTTP signature in #{self.class}")
        end
      end


        class Helper < OffsitePayments::Helper
          include CredentialHelper
          include SignatureProcessor
          PROTOCOL_STATIC_FIELDS = {
              'version' => '5.0.0', #版本号
              'encoding' => 'UTF-8', #编码方式
              'txnType' => '01', #交易类型
              'txnSubType' => '01', #交易子类
              'bizType' => '000201', #业务类型, 'B2C网关支付'
              'signMethod' => '01', #签名方法
              'channelType' => '07', #渠道类型，07-PC，08-手机
              'accessType' => '0', #接入类型
              'currencyCode' => '156', #交易币种
              'reqReserved' => '透传信息', #请求方保留域，透传字段，查询、通知、对账文件中均会原样出现
          }

          mapping :certificate_id, 'certId' #证书ID
          mapping :order, 'orderId' #商户订单号，我们应用payment_number
          mapping :order_time, 'txnTime'
          mapping :account, 'merId'
          mapping :total_fee, 'txnAmt' #单位，分
          mapping :currency, 'currencyCode' #交易币种
          mapping :return_url, 'frontUrl'
          mapping :notify_url, 'backUrl'
          mapping :channel_type, 'channelType'

          def initialize(order, account, options = {})
            super
            add_field 'certId', certificate_id
          end

          def credential_based_url
            'https://101.231.204.80:5000/gateway/api/frontTransReq.do'
          end

          def form_fields
            fields.merge(PROTOCOL_STATIC_FIELDS)
          end
        end

    end
  end
end
